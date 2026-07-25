import pty from "node-pty";
import os from "os";
import { execFileSync } from "child_process";
import fs from "fs";

// =============================================================================
// Configuration
// =============================================================================

const CONFIG = {
  defaultCols: 80,
  defaultRows: 24,
  maxScrollback: 2_000_000, // ~2MB of scrollback per session
};

// =============================================================================
// tmux persistence (opt-in via TERMAWAY_TMUX=1)
// =============================================================================
//
// With tmux mode on, a session's PTY runs a tmux *client* attached to a tmux
// session instead of the login shell directly. The shell then belongs to the
// tmux server, so it survives this process exiting: restart TermAway (or the
// Mac) and `adoptTmuxSessions()` reattaches to everything still running.
//
// TermAway's own replay buffer is in-memory and still resets on restart. What
// survives is the processes and tmux's own history — attaching repaints the
// current screen.

// Absolute paths first: a server launched from Finder or a LaunchAgent gets a
// minimal PATH that usually misses Homebrew, and a PATH lookup can also find a
// wrapper rather than tmux itself.
const TMUX_PATHS = [
  "/opt/homebrew/bin/tmux",
  "/usr/local/bin/tmux",
  "/usr/bin/tmux",
  "/opt/local/bin/tmux",
];

// Deliberately not a PATH lookup: the macOS app checks the same list before it
// lets you turn persistence on, and two different answers to "is tmux here"
// would mean the toggle refusing something the server could have run.
const findTmux = () => TMUX_PATHS.find((p) => fs.existsSync(p)) ?? null;

// tmux reads "." and ":" in a target as window/pane separators, so a session
// named "my.app" is creatable but not addressable ("can't find window: my").
// Percent-encode the dot; "%" is rejected by the session-name validator, so the
// mapping stays unambiguous in both directions.
const toTmuxName = (name) => name.replaceAll(".", "%2E");
const fromTmuxName = (name) => name.replaceAll("%2E", ".");

// Verbose per-message/per-resize logging is gated behind a debug flag so a
// production server doesn't spam its logs on every output chunk. Enable with
// TERMAWAY_DEBUG=1 (or DEBUG=termaway). Lifecycle and error logs stay on.
const DEBUG =
  process.env.TERMAWAY_DEBUG === "1" || process.env.DEBUG === "termaway";
function debug(...args) {
  if (DEBUG) console.log(...args);
}

// =============================================================================
// Session Class
// =============================================================================

class Session {
  constructor(name, ptyProcess, ephemeral = false) {
    this.name = name;
    this.pty = ptyProcess;
    this.clients = new Set();
    this.scrollback = [];
    this.scrollbackSize = 0;
    this.createdAt = new Date();
    this.lastCols = CONFIG.defaultCols;
    this.lastRows = CONFIG.defaultRows;
    this.lastResizeAt = 0;
    // Track each client's terminal size for multi-client scenarios
    this.clientSizes = new WeakMap();
    // Ephemeral sessions don't show in the session list (used for split panes)
    this.ephemeral = ephemeral;
    // "Agent needs you" flag: set by a terminal bell or an explicit hook,
    // cleared when the user interacts with the session. Rides the session list.
    this.needsAttention = false;
    // Listening TCP ports in this session's process tree that are reachable
    // off-box (bound to 0.0.0.0/* or a real interface, not loopback). Populated
    // by the periodic scan in index.js so clients can offer preview links.
    this.ports = [];
    // tmux session this PTY is a client of, or null for a plain shell.
    this.tmuxName = null;
    // Set while an explicit kill is in flight so the PTY's exit isn't mistaken
    // for a detached client and reattached.
    this.killing = false;
    this.lastSpawnAt = 0;
  }

  // Store output in scrollback buffer
  pushScrollback(data) {
    this.scrollback.push(data);
    this.scrollbackSize += data.length;

    // Trim if over limit
    while (
      this.scrollbackSize > CONFIG.maxScrollback &&
      this.scrollback.length > 0
    ) {
      this.scrollbackSize -= this.scrollback.shift().length;
    }
  }

  // Get full scrollback as string
  getScrollback() {
    return this.scrollback.join("");
  }

  // Send message to one client
  send(ws, message) {
    if (ws.readyState === 1) {
      ws.send(JSON.stringify(message));
    }
  }

  // Broadcast message to all clients
  broadcast(message) {
    const json = JSON.stringify(message);
    for (const client of this.clients) {
      if (client.readyState === 1) {
        client.send(json);
      }
    }
  }
}

// =============================================================================
// Session Manager
// =============================================================================

class SessionManager {
  constructor({ port = 0 } = {}) {
    this.sessions = new Map();
    this.clipboard = "";
    // Set by index.js before shutdown so tmux sessions are left running.
    this.shuttingDown = false;
    // onAttentionChange is set by index.js to fan out attention changes.

    this.tmux = null;
    if (process.env.TERMAWAY_TMUX === "1") {
      const bin = findTmux();
      if (bin) {
        // A private socket keeps TermAway out of the user's own tmux server, so
        // their ~/.tmux.conf (visual-bell, exit-unattached, …) and their own
        // sessions can't change how TermAway behaves. -f /dev/null does the
        // same for the config.
        this.tmux = { bin, socket: `termaway-${port}` };
        console.log(
          `tmux persistence enabled (${bin}, socket ${this.tmux.socket})`,
        );
      } else {
        console.error(
          "TERMAWAY_TMUX=1 but tmux was not found — sessions will NOT survive a " +
            "restart. Install it with: brew install tmux",
        );
      }
    }
    debug("Session manager ready (PTY mode)");
  }

  // ---------------------------------------------------------------------------
  // tmux helpers
  // ---------------------------------------------------------------------------

  // Argument prefix for any tmux invocation, so callers can't forget the socket.
  tmuxArgs(...args) {
    return ["-L", this.tmux.socket, "-f", "/dev/null", ...args];
  }

  // Run a tmux command and report how it went. `status` is tmux's own exit code
  // and `error` is set when tmux could not be run at all (missing binary,
  // timeout) — the two must stay distinguishable, because "tmux did not answer"
  // is not the same as "the session is gone".
  _tmuxResult(...args) {
    try {
      const stdout = execFileSync(this.tmux.bin, this.tmuxArgs(...args), {
        encoding: "utf8",
        timeout: 3000,
        stdio: ["ignore", "pipe", "pipe"],
      });
      return { ok: true, stdout, status: 0 };
    } catch (err) {
      return { ok: false, stdout: "", status: err.status ?? null, error: err };
    }
  }

  // For commands that change tmux state. These must never fail quietly: a
  // swallowed kill-session leaves a session running that TermAway has already
  // forgotten, and a swallowed rename makes the old name come back on restart.
  _tmux(...args) {
    const result = this._tmuxResult(...args);
    if (!result.ok) {
      const detail =
        String(result.error?.stderr || "").trim() ||
        result.error?.message ||
        `exit ${result.status}`;
      throw new Error(`tmux ${args[0]} failed: ${detail}`);
    }
    return result.stdout;
  }

  // true, false, or null when tmux itself could not be asked. A transient
  // failure must not be read as "the session died".
  _tmuxAlive(tmuxName) {
    const result = this._tmuxResult("has-session", "-t", `=${tmuxName}`);
    if (result.ok) return true;
    return result.status === 1 ? false : null;
  }

  // Reattach to every tmux session left behind by a previous run. Attach only —
  // creating here could resurrect a session that was killed between listing and
  // attaching.
  adoptTmuxSessions() {
    if (!this.tmux) return 0;
    const listed = this._tmuxResult("list-sessions", "-F", "#{session_name}");
    if (!listed.ok) return 0; // no server running yet — nothing to adopt
    let adopted = 0;
    for (const line of listed.stdout.split("\n")) {
      const tmuxName = line.trim();
      if (!tmuxName) continue;
      const name = fromTmuxName(tmuxName);
      if (this.sessions.has(name)) continue;
      try {
        this._register(name, tmuxName, false);
        adopted++;
      } catch (err) {
        console.error(`Failed to adopt tmux session "${name}": ${err.message}`);
      }
    }
    if (adopted)
      console.log(`Adopted ${adopted} tmux session(s) from a previous run`);
    return adopted;
  }

  // ---------------------------------------------------------------------------
  // Session Lifecycle
  // ---------------------------------------------------------------------------

  // Spawn the PTY backing a session: a tmux client when the session is
  // persistent, the login shell otherwise.
  _spawnPty(tmuxName) {
    const [file, args] = tmuxName
      ? // Attach only. The session is created up front by create(), so this
        // never has to decide whether one should exist.
        [this.tmux.bin, this.tmuxArgs("attach-session", "-t", `=${tmuxName}`)]
      : [process.env.SHELL || "/bin/bash", ["-l"]];

    return pty.spawn(file, args, {
      name: "xterm-256color",
      cols: CONFIG.defaultCols,
      rows: CONFIG.defaultRows,
      cwd: process.env.HOME || os.homedir(),
      env: {
        ...process.env,
        TERM: "xterm-256color",
        COLORTERM: "truecolor",
        LANG: process.env.LANG || "en_US.UTF-8",
        LC_ALL: process.env.LC_ALL || process.env.LANG || "en_US.UTF-8",
        // Suppress zsh's PROMPT_SP (the % character shown when output lacks newline)
        PROMPT_EOL_MARK: "",
      },
    });
  }

  // Wire a Session around a freshly spawned PTY. Shared by create() and by
  // adoption, which must not create anything.
  _register(name, tmuxName, ephemeral) {
    const session = new Session(name, this._spawnPty(tmuxName), ephemeral);
    session.tmuxName = tmuxName;
    session.lastSpawnAt = Date.now();
    this.sessions.set(name, session);
    this._setupHandlers(session);
    return session;
  }

  create(name, ephemeral = false) {
    if (this.sessions.has(name)) {
      throw new Error(`Session "${name}" already exists`);
    }

    // Ephemeral split-pane sessions stay plain shells: they're hidden from the
    // session list and auto-killed on detach, so persisting one would leave an
    // invisible tmux session nobody can reach.
    const tmuxName = this.tmux && !ephemeral ? toTmuxName(name) : null;
    // Create the tmux session up front and synchronously. Letting the PTY do it
    // with `new-session -A` leaves a window where the session does not exist
    // yet: an immediate kill or rename would silently miss, and tmux would then
    // finish creating it — orphaning a session that gets adopted on next start.
    if (tmuxName) this._tmux("new-session", "-d", "-s", tmuxName);

    const session = this._register(name, tmuxName, ephemeral);
    console.log(`Created ${ephemeral ? "ephemeral " : ""}session "${name}"`);
    return session;
  }

  kill(name) {
    const session = this.sessions.get(name);
    if (!session) {
      throw new Error(`Session "${name}" not found`);
    }

    // Killing the PTY only disconnects the tmux client — the session and its
    // processes keep running. An explicit kill has to end the tmux session too,
    // or it comes back on the next restart. Shutdown is the opposite case: leave
    // the tmux session alone so the next run can adopt it.
    // This runs before any state changes so a failure leaves the session intact
    // rather than dropping it from the list while it is still running.
    if (session.tmuxName && !this.shuttingDown) {
      this._tmux("kill-session", "-t", `=${session.tmuxName}`);
    }

    session.killing = true;
    session.pty.kill();
    // Shutting down is not a kill: the sessions are still there (tmux) or the
    // whole server is going away (plain shells). Telling clients they were
    // killed makes them drop local state — iOS discards the composer draft.
    if (!this.shuttingDown) {
      session.broadcast({ type: "killed", name });
    }
    this.sessions.delete(name);

    console.log(`Killed session "${name}"`);
  }

  rename(oldName, newName) {
    const session = this.sessions.get(oldName);
    if (!session) {
      throw new Error(`Session "${oldName}" not found`);
    }
    if (this.sessions.has(newName)) {
      throw new Error(`Session "${newName}" already exists`);
    }

    // Rename the tmux session too, or the old name reappears after a restart.
    if (session.tmuxName) {
      const next = toTmuxName(newName);
      this._tmux("rename-session", "-t", `=${session.tmuxName}`, next);
      session.tmuxName = next;
    }

    session.name = newName;
    this.sessions.delete(oldName);
    this.sessions.set(newName, session);
    session.broadcast({ type: "renamed", oldName, newName });

    console.log(`Renamed "${oldName}" to "${newName}"`);
  }

  // ---------------------------------------------------------------------------
  // Client Management
  // ---------------------------------------------------------------------------

  /**
   * Attach a client to a session and send existing scrollback.
   * Returns a Promise that resolves when all scrollback has been sent.
   * This ensures the caller can wait before sending 'attached' confirmation.
   */
  attach(name, ws) {
    const session = this.sessions.get(name);
    if (!session) {
      throw new Error(`Session "${name}" not found`);
    }

    session.clients.add(ws);

    // Send existing scrollback to new client in chunks to prevent overwhelming mobile clients
    const CHUNK_SIZE = 100_000; // 100KB per chunk
    const scrollback = session.getScrollback();

    // Create a promise that resolves when all scrollback is sent
    const scrollbackPromise = new Promise((resolve) => {
      if (!scrollback || scrollback.length === 0) {
        resolve();
        return;
      }

      debug(
        `Sending scrollback (${scrollback.length} bytes, ${session.scrollback.length} chunks)`,
      );

      if (scrollback.length <= CHUNK_SIZE) {
        // Small enough to send in one message
        session.send(ws, {
          type: "output",
          name: session.name,
          data: scrollback,
        });
        resolve();
      } else {
        // Send in chunks with small delays to let client process
        let offset = 0;
        const sendChunk = () => {
          if (offset >= scrollback.length) {
            resolve(); // All chunks sent
            return;
          }
          const chunk = scrollback.slice(offset, offset + CHUNK_SIZE);
          session.send(ws, { type: "output", name: session.name, data: chunk });
          offset += CHUNK_SIZE;
          if (offset < scrollback.length) {
            setTimeout(sendChunk, 50); // 50ms delay between chunks
          } else {
            resolve(); // Last chunk sent
          }
        };
        sendChunk();
      }
    });

    debug(`Client attached to "${name}" (${session.clients.size} clients)`);

    // Return both session and scrollback promise
    session.scrollbackPromise = scrollbackPromise;
    return session;
  }

  detach(name, ws) {
    const session = this.sessions.get(name);
    if (session && session.clients.delete(ws)) {
      console.log(
        `Client detached from "${name}" (${session.clients.size} clients)`,
      );
      // Recalculate size now that this client is gone
      this._recalculateSize(session);
      // Auto-kill ephemeral sessions when no clients remain
      if (session.ephemeral && session.clients.size === 0) {
        console.log(`Auto-killing ephemeral session "${name}"`);
        this.kill(name);
      }
    }
  }

  detachAll(ws) {
    const sessionsToKill = [];
    for (const [name, session] of this.sessions) {
      if (session.clients.delete(ws)) {
        console.log(
          `Client detached from "${name}" (${session.clients.size} clients)`,
        );
        // Recalculate size now that this client is gone
        this._recalculateSize(session);
        // Mark ephemeral sessions for cleanup
        if (session.ephemeral && session.clients.size === 0) {
          sessionsToKill.push(name);
        }
      }
    }
    // Kill ephemeral sessions after iteration
    for (const name of sessionsToKill) {
      console.log(`Auto-killing ephemeral session "${name}"`);
      this.kill(name);
    }
  }

  // Recalculate PTY size based on remaining clients
  _recalculateSize(session) {
    if (session.clients.size === 0) return;

    let minCols = Infinity;
    let minRows = Infinity;

    for (const client of session.clients) {
      const size = session.clientSizes.get(client);
      if (size) {
        minCols = Math.min(minCols, size.cols);
        minRows = Math.min(minRows, size.rows);
      }
    }

    // If we found valid sizes and they differ from current, resize
    if (minCols !== Infinity && minRows !== Infinity) {
      if (minCols !== session.lastCols || minRows !== session.lastRows) {
        session.lastCols = minCols;
        session.lastRows = minRows;
        session.pty.resize(minCols, minRows);
        console.log(
          `Recalculated "${session.name}" to ${minCols}x${minRows} (${session.clients.size} clients)`,
        );
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Terminal I/O
  // ---------------------------------------------------------------------------

  write(name, data) {
    const session = this.sessions.get(name);
    if (!session) {
      throw new Error(`Session "${name}" not found`);
    }
    session.pty.write(data);
    // User is interacting with this session — it no longer needs attention.
    if (session.needsAttention) this.clearAttention(name);
  }

  // ---------------------------------------------------------------------------
  // Attention (agent needs you)
  // ---------------------------------------------------------------------------

  // Flag a session as needing attention. `source` is "bell" (passive, detected
  // in PTY output) or "notify" (explicit agent hook). `changed` tells the
  // listener whether this was a false->true transition (so the badge/list only
  // re-broadcasts on real changes, while explicit notifies always fire).
  markAttention(name, { source = "bell", title, body } = {}) {
    const session = this.sessions.get(name);
    if (!session) return;
    // Note: ephemeral split-pane sessions are excluded from list() so they
    // never show a badge, but they still raise the event here so an agent
    // running in a pane can alert.
    const changed = !session.needsAttention;
    session.needsAttention = true;
    this.onAttentionChange?.(session, { source, title, body, changed });
  }

  clearAttention(name) {
    const session = this.sessions.get(name);
    if (!session || !session.needsAttention) return;
    session.needsAttention = false;
    this.onAttentionChange?.(session, { source: "clear", changed: true });
  }

  resize(name, cols, rows, ws = null) {
    const session = this.sessions.get(name);
    if (!session) {
      throw new Error(`Session "${name}" not found`);
    }

    // Ignore tiny sizes that break terminal rendering
    if (cols < 10 || rows < 5) {
      debug(`Ignoring tiny resize for "${name}": ${cols}x${rows}`);
      return;
    }

    // Store this client's preferred size
    if (ws) {
      session.clientSizes.set(ws, { cols, rows });
    }

    // Calculate minimum size across all connected clients
    let minCols = cols;
    let minRows = rows;
    for (const client of session.clients) {
      const size = session.clientSizes.get(client);
      if (size) {
        minCols = Math.min(minCols, size.cols);
        minRows = Math.min(minRows, size.rows);
      }
    }

    // Ignore if effective size hasn't changed
    if (minCols === session.lastCols && minRows === session.lastRows) {
      return;
    }

    // Resize cooldown: ignore resizes within 100ms of last resize
    // This prevents "resize fights" when multiple clients connect
    const now = Date.now();
    if (now - session.lastResizeAt < 100) {
      debug(`Ignoring rapid resize for "${name}": ${minCols}x${minRows}`);
      return;
    }

    session.lastCols = minCols;
    session.lastRows = minRows;
    session.lastResizeAt = now;
    session.pty.resize(minCols, minRows);
    debug(
      `Resized "${name}" to ${minCols}x${minRows} (min of ${session.clients.size} clients)`,
    );
  }

  // ---------------------------------------------------------------------------
  // Queries
  // ---------------------------------------------------------------------------

  list() {
    // Filter out ephemeral sessions (used for split panes)
    return Array.from(this.sessions.entries())
      .filter(([_, session]) => !session.ephemeral)
      .map(([name]) => name);
  }

  exists(name) {
    return this.sessions.has(name);
  }

  get(name) {
    return this.sessions.get(name);
  }

  info(name) {
    const session = this.sessions.get(name);
    if (!session) return null;

    return {
      name: session.name,
      clientCount: session.clients.size,
      createdAt: session.createdAt,
      scrollbackLength: session.scrollback.length,
      needsAttention: session.needsAttention,
      ports: session.ports,
      isTmux: session.tmuxName !== null,
      isConnected: true,
    };
  }

  // ---------------------------------------------------------------------------
  // Clipboard
  // ---------------------------------------------------------------------------

  setClipboard(content) {
    this.clipboard = content || "";
  }

  getClipboard() {
    return this.clipboard;
  }

  // ---------------------------------------------------------------------------
  // Internal
  // ---------------------------------------------------------------------------

  _setupHandlers(session) {
    session.pty.onData((data) => {
      session.pushScrollback(data);
      // Passive attention: a terminal bell (BEL, \x07) means "look at me".
      // Claude Code, Codex, OpenCode and most CLIs ring it on notifications,
      // permission prompts and task completion — zero config, any tool.
      if (data.includes("\x07")) {
        this.markAttention(session.name, { source: "bell" });
      }
      // Include session name so clients can route to correct pane
      const msg = { type: "output", name: session.name, data };
      debug(`Broadcasting output for "${session.name}": ${data.length} chars`);
      session.broadcast(msg);
    });

    session.pty.onExit(({ exitCode, signal }) => {
      // An explicit kill has already told clients, and a shutdown deliberately
      // leaves tmux sessions running. Reporting an exit in either case makes
      // clients discard state for a session that is fine.
      if (session.killing || this.shuttingDown) return;

      // For a tmux-backed session the PTY is only the client. It also exits on
      // `tmux detach` (Ctrl-b d) or if the client is killed, while the session
      // itself keeps running — reattach instead of reporting it as gone.
      if (this._reattach(session)) return;

      console.log(
        `Session "${session.name}" exited (code ${exitCode}, signal ${signal})`,
      );
      session.broadcast({
        type: "exited",
        name: session.name,
        exitCode,
        signal,
      });
      this.sessions.delete(session.name);
    });
  }

  // Replace the PTY of a tmux-backed session whose client went away but whose
  // tmux session is still alive. Returns true if the session was kept.
  _reattach(session) {
    if (!session.tmuxName || session.killing || this.shuttingDown) return false;
    // A client that dies immediately after spawning means something is wrong
    // with tmux itself; let the session go rather than respawn in a tight loop.
    if (Date.now() - session.lastSpawnAt < 1000) return false;
    // Only a definite "no such session" ends the session. If tmux could not be
    // asked, assume it is still there and let the spawn below be the real test.
    if (this._tmuxAlive(session.tmuxName) === false) return false;

    console.log(`Reattaching tmux session "${session.name}"`);
    try {
      session.pty = this._spawnPty(session.tmuxName);
    } catch (err) {
      console.error(`Failed to reattach "${session.name}": ${err.message}`);
      return false;
    }
    session.lastSpawnAt = Date.now();
    this._setupHandlers(session);
    session.pty.resize(session.lastCols, session.lastRows);
    return true;
  }
}

export default SessionManager;
