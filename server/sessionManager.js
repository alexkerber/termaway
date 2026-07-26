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

// How long after a resize to hold the next one, so two clients with different
// window sizes can't ping-pong the PTY between them.
const RESIZE_COOLDOWN = 100;

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

const isExecutable = (p) => {
  try {
    fs.accessSync(p, fs.constants.X_OK);
    return true;
  } catch {
    return false;
  }
};

// No PATH lookup: the macOS app checks the same four paths before it lets you
// turn persistence on, and a second answer to "is tmux here" would mean the
// toggle refusing something the server could have run. TERMAWAY_TMUX_BIN is the
// escape hatch for installs that live elsewhere (Nix, a local build) — it only
// applies where there is no toggle to disagree with, since an app launched from
// Finder never sees a shell's environment anyway.
function findTmux() {
  const override = process.env.TERMAWAY_TMUX_BIN;
  if (override) return isExecutable(override) ? override : null;
  return TMUX_PATHS.find(isExecutable) ?? null;
}

// =============================================================================
// OSC notifications
// =============================================================================
//
// Terminals converged on two escape sequences for "tell the user something",
// and agent CLIs, ntfy hooks and tmux hooks already speak one of them:
//
//   OSC 9   ESC ] 9 ; message                  BEL | ST
//   OSC 777 ESC ] 777 ; notify ; title ; body  BEL | ST
//
// A payload can contain neither BEL nor ESC, which is what makes matching them
// with one regex safe.
const OSC_NOTIFICATION = /\x1b\](9|777);([^\x07\x1b\x18\x1a]*)(?:\x07|\x1b\\)/g;

// Any OSC, notification or not. BEL is a valid OSC terminator, so a shell that
// sets the window title on every prompt emits one constantly — those must not
// be read as the program ringing for attention.
//
// CAN (0x18) and SUB (0x1a) abort a sequence in progress, which is why no
// payload may contain them: a terminal would stop parsing there and treat the
// rest as ordinary output, and so must we.
const ANY_OSC = /\x1b\][^\x07\x1b\x18\x1a]*(?:\x07|\x1b\\)/g;

// A sequence can straddle two PTY reads, so an unterminated tail is carried to
// the next chunk. Bounded: something that opens an OSC and never closes it must
// not be able to grow memory.
const MAX_OSC_CARRY = 4096;

// What a carried fragment is allowed to look like: a lone ESC, an opener with
// an unfinished payload, or a payload plus the first half of an ST. Anything
// else is not a sequence in progress — a program that abandoned one with a
// stray ESC, most often — and must settle so the bells after it still count.
const OSC_IN_PROGRESS = /^\x1b(\][^\x07\x1b\x18\x1a]*\x1b?)?$/;

// An OSC notification can be driven by whatever is on the terminal: a remote
// host, a file being cat'd. Unlike the loopback hook it isn't a deliberate
// local act, so it is rate-limited per session.
const OSC_NOTIFY_INTERVAL = 2000;

function parseOscNotification(code, payload) {
  if (code === "9") {
    // OSC 9 is multiplexed: iTerm2 sends progress as `9;4;state;percent` and
    // ConEmu uses `9;<digit>;…` for several other things. Only the plain
    // `9;message` form is a notification — without this, a build with a
    // progress bar raises an alert on every tick.
    if (!payload || /^\d+(;|$)/.test(payload)) return null;
    return { title: "", body: payload };
  }
  // 777 addresses several kinds of thing; only "notify" concerns us.
  const parts = payload.split(";");
  if (parts[0] !== "notify") return null;
  const title = parts[1] ?? "";
  const body = parts.slice(2).join(";");
  return title || body ? { title, body } : null;
}

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
    // Timer holding the last resize of a burst until the cooldown expires.
    this.pendingResize = null;
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
    // Tail of an OSC sequence that hasn't been terminated yet.
    this.oscCarry = "";
    this.lastOscNotifyAt = 0;
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
            "restart. Install tmux with your package manager, or point " +
            "TERMAWAY_TMUX_BIN at it, and restart TermAway.",
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
      return { ok: true, stdout };
    } catch (err) {
      return { ok: false, status: err.status ?? null, error: err };
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

    let session;
    try {
      session = this._register(name, tmuxName, ephemeral);
    } catch (err) {
      // The tmux session exists but nothing references it — clean it up rather
      // than leave an orphan for the next start to adopt.
      if (tmuxName) this._tmuxResult("kill-session", "-t", `=${tmuxName}`);
      throw err;
    }
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
    clearTimeout(session.pendingResize);
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

  // Recalculate PTY size based on remaining clients. Also what a deferred
  // resize runs when its cooldown expires, so it supersedes any pending one.
  _recalculateSize(session) {
    clearTimeout(session.pendingResize);
    session.pendingResize = null;
    // A deferred resize outlives the session by up to the cooldown, and every
    // way a session goes — killed, shell exited, reattach gave up — drops it
    // from the map without touching the timer. rename() updates session.name
    // before it moves the entry, so this still recognises a renamed session.
    if (this.sessions.get(session.name) !== session) return;
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
        this._applySize(session, minCols, minRows);
        console.log(
          `Recalculated "${session.name}" to ${minCols}x${minRows} (${session.clients.size} clients)`,
        );
      }
    }
  }

  // The one place the PTY's size changes, so lastResizeAt can't drift out of
  // step with it and let the next burst through the cooldown.
  _applySize(session, cols, rows) {
    session.lastCols = cols;
    session.lastRows = rows;
    session.lastResizeAt = Date.now();
    session.pty.resize(cols, rows);
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

    // Resize cooldown, to stop two clients fighting over the size. It has to
    // coalesce the burst rather than drop it: a rotation emits several sizes in
    // a few milliseconds, and dropping the last one leaves the PTY on an
    // intermediate width while the client renders at the final one. Nothing
    // retries, so the shell then wraps every prompt at the wrong column until
    // some later resize happens to miss the window.
    const now = Date.now();
    const wait = session.lastResizeAt + RESIZE_COOLDOWN - now;
    if (wait > 0) {
      // The size is already in clientSizes, so the deferred work is only
      // "recompute the minimum once the window closes". Capturing this call's
      // size instead would go stale the moment a client resizes again, leaves,
      // or resizes back to the size already applied — each of which would then
      // hand the PTY a width nobody asked for.
      session.pendingResize ??= setTimeout(() => {
        session.pendingResize = null;
        this._recalculateSize(session);
      }, wait);
      return;
    }

    this._applySize(session, minCols, minRows);
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
      // Attention, in order of how much the program told us.
      //
      // An OSC notification carries a real message, so it is treated like the
      // explicit /api/notify hook rather than a bell. Checking it first also
      // keeps its own terminating BEL from firing a second, blank alert.
      const { notification, bell } = this._scanAttention(session, data);
      let notified = false;
      if (notification) {
        // Rate-limited rather than gated on `changed`: gating would mute a
        // second, different message until the user acknowledged the first,
        // while a chatty or hostile stream could otherwise raise one banner per
        // chunk of output.
        const now = Date.now();
        if (now - session.lastOscNotifyAt >= OSC_NOTIFY_INTERVAL) {
          session.lastOscNotifyAt = now;
          notified = true;
          this.markAttention(session.name, {
            source: "notify",
            title: notification.title || session.name,
            body: notification.body,
          });
        }
      }
      // A chunk can carry both. If the notification was rate-limited away, a
      // bare bell in the same chunk still has to be heard.
      if (!notified && bell) {
        // A bare bell means "look at me" with nothing else to say. Claude Code,
        // Codex, OpenCode and most CLIs ring it on notifications, permission
        // prompts and task completion — zero config, any tool.
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

  // What this chunk of output is asking for: `notification` when the program
  // sent an OSC 9/777 (the last one, since attention is a single flag and the
  // newest message is the useful one), and `bell` when a BEL appears outside
  // any escape sequence.
  _scanAttention(session, data) {
    const buf = session.oscCarry + data;

    let latest = null;
    OSC_NOTIFICATION.lastIndex = 0;
    let match;
    while ((match = OSC_NOTIFICATION.exec(buf)) !== null) {
      latest = parseOscNotification(match[1], match[2]) ?? latest;
    }

    // Where the last complete sequence ends. Only the tail after it can still
    // hold one in progress — an opener earlier than that was abandoned the
    // moment the next sequence began, so carrying it would let a later bell be
    // swallowed as its terminator.
    let completeEnd = 0;
    ANY_OSC.lastIndex = 0;
    while ((match = ANY_OSC.exec(buf)) !== null) {
      completeEnd = match.index + match[0].length;
    }
    const tail = buf.slice(completeEnd);

    // Whatever opens a sequence without closing it may finish in the next read.
    // A read can also end between the ESC and the "]", so a trailing lone ESC
    // has to be kept too.
    const opened = tail.lastIndexOf("\x1b]");
    let carry = "";
    if (opened !== -1) carry = tail.slice(opened);
    else if (tail.endsWith("\x1b")) carry = "\x1b";
    if (!OSC_IN_PROGRESS.test(carry)) carry = "";

    // A BEL counts when it is outside every complete sequence and outside the
    // fragment being carried.
    const settled =
      buf.slice(0, completeEnd).replace(ANY_OSC, "") +
      tail.slice(0, tail.length - carry.length);

    // A sequence that never ends must not grow memory — but dropping the carry
    // entirely would forget that we are inside one, and its eventual
    // terminating BEL would then read as a bell. Two bytes remember it.
    session.oscCarry = carry.length > MAX_OSC_CARRY ? "\x1b]" : carry;

    return { notification: latest, bell: settled.includes("\x07") };
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
      // A new PTY is a new stream; a fragment from the old one would splice
      // onto it and invent a sequence that was never sent.
      session.oscCarry = "";
    } catch (err) {
      // tmux still has the session, we just can't reach it right now. Drop it
      // from the list quietly: reporting an exit would make clients discard
      // state for a session that is running, and the next start re-adopts it.
      console.error(
        `Failed to reattach "${session.name}", leaving it to tmux: ${err.message}`,
      );
      this.sessions.delete(session.name);
      return true;
    }
    session.lastSpawnAt = Date.now();
    this._setupHandlers(session);
    session.pty.resize(session.lastCols, session.lastRows);
    return true;
  }
}

export default SessionManager;
