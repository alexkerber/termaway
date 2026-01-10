import pty from "node-pty";
import os from "os";
import { execFileSync } from "child_process";

// Tmux session prefix to avoid conflicts with user sessions
const TMUX_PREFIX = "termaway-";

/**
 * Check if tmux is available on the system
 */
function isTmuxAvailable() {
  try {
    execFileSync("which", ["tmux"], { stdio: "ignore" });
    return true;
  } catch {
    return false;
  }
}

/**
 * Get the tmux session name from user-visible name
 */
function getTmuxSessionName(name) {
  return `${TMUX_PREFIX}${name}`;
}

/**
 * Get the user-visible name from tmux session name
 */
function getUserSessionName(tmuxName) {
  if (tmuxName.startsWith(TMUX_PREFIX)) {
    return tmuxName.slice(TMUX_PREFIX.length);
  }
  return tmuxName;
}

/**
 * List all TermAway tmux sessions
 */
function listTmuxSessions() {
  try {
    const output = execFileSync(
      "tmux",
      ["list-sessions", "-F", "#{session_name}"],
      {
        encoding: "utf-8",
        stdio: ["pipe", "pipe", "ignore"],
      },
    );
    return output
      .trim()
      .split("\n")
      .filter((name) => name.startsWith(TMUX_PREFIX))
      .map(getUserSessionName)
      .filter((name) => name.length > 0);
  } catch {
    return [];
  }
}

/**
 * Check if a tmux session exists
 */
function tmuxSessionExists(name) {
  try {
    execFileSync("tmux", ["has-session", "-t", getTmuxSessionName(name)], {
      stdio: "ignore",
    });
    return true;
  } catch {
    return false;
  }
}

/**
 * Create a new tmux session (detached)
 */
function createTmuxSession(name) {
  const tmuxName = getTmuxSessionName(name);
  const shell = process.env.SHELL || "/bin/bash";

  execFileSync(
    "tmux",
    ["new-session", "-d", "-s", tmuxName, "-x", "80", "-y", "24", shell, "-l"],
    {
      env: {
        ...process.env,
        TERM: "xterm-256color",
      },
    },
  );
}

/**
 * Kill a tmux session
 */
function killTmuxSession(name) {
  try {
    execFileSync("tmux", ["kill-session", "-t", getTmuxSessionName(name)], {
      stdio: "ignore",
    });
  } catch {
    // Session may already be dead
  }
}

/**
 * Rename a tmux session
 */
function renameTmuxSession(oldName, newName) {
  execFileSync("tmux", [
    "rename-session",
    "-t",
    getTmuxSessionName(oldName),
    getTmuxSessionName(newName),
  ]);
}

/**
 * Manages PTY sessions with named persistent sessions
 * Supports tmux-backed sessions for persistence across server restarts
 */
class SessionManager {
  constructor() {
    this.sessions = new Map();
    this.scrollbackSize = 10000;
    this.sharedClipboard = "";

    // Check tmux availability at startup
    this.tmuxAvailable = isTmuxAvailable();
    if (this.tmuxAvailable) {
      console.log("tmux detected - session persistence enabled");
    } else {
      console.log("tmux not found - sessions will not persist across restarts");
    }
  }

  /**
   * Restore existing tmux sessions on server startup
   */
  restoreExistingSessions() {
    if (!this.tmuxAvailable) {
      return [];
    }

    const existingSessions = listTmuxSessions();
    const restored = [];

    for (const name of existingSessions) {
      try {
        this._attachToTmuxSession(name);
        restored.push(name);
        console.log(`Restored tmux session "${name}"`);
      } catch (error) {
        console.error(`Failed to restore session "${name}":`, error.message);
      }
    }

    return restored;
  }

  /**
   * Internal: Attach node-pty to an existing tmux session
   */
  _attachToTmuxSession(name) {
    const tmuxName = getTmuxSessionName(name);

    const env = {
      ...process.env,
      TERM: "xterm-256color",
      COLORTERM: "truecolor",
      LANG: process.env.LANG || "en_US.UTF-8",
      LC_ALL: process.env.LC_ALL || process.env.LANG || "en_US.UTF-8",
    };

    const ptyProcess = pty.spawn("tmux", ["attach-session", "-t", tmuxName], {
      name: "xterm-256color",
      cols: 80,
      rows: 24,
      cwd: process.env.HOME || os.homedir(),
      env: env,
    });

    const session = {
      name,
      pty: ptyProcess,
      scrollback: [],
      clients: new Set(),
      createdAt: new Date(),
      isTmux: true,
    };

    this._setupPtyHandlers(session);
    this.sessions.set(name, session);

    return session;
  }

  /**
   * Setup PTY event handlers for a session
   */
  _setupPtyHandlers(session) {
    const { name, pty: ptyProcess } = session;

    ptyProcess.onData((data) => {
      session.scrollback.push(data);
      let totalLength = 0;
      for (const chunk of session.scrollback) {
        totalLength += chunk.length;
      }
      while (
        totalLength > this.scrollbackSize * 200 &&
        session.scrollback.length > 0
      ) {
        const removed = session.scrollback.shift();
        totalLength -= removed.length;
      }

      for (const client of session.clients) {
        if (client.readyState === 1) {
          client.send(
            JSON.stringify({
              type: "output",
              data: data,
            }),
          );
        }
      }
    });

    ptyProcess.onExit(({ exitCode, signal }) => {
      console.log(
        `Session "${name}" PTY exited with code ${exitCode}, signal ${signal}`,
      );

      // For tmux sessions, the PTY exit might just mean detach
      if (session.isTmux && tmuxSessionExists(name)) {
        console.log(`tmux session "${name}" still exists - can be reattached`);
        for (const client of session.clients) {
          if (client.readyState === 1) {
            client.send(
              JSON.stringify({
                type: "disconnected",
                name: name,
                message: "PTY disconnected, tmux session still running",
              }),
            );
          }
        }
        session.clients.clear();
        session.pty = null;
        return;
      }

      // Non-tmux session or tmux session is gone
      for (const client of session.clients) {
        if (client.readyState === 1) {
          client.send(
            JSON.stringify({
              type: "exited",
              name: name,
              exitCode,
              signal,
            }),
          );
        }
      }
      this.sessions.delete(name);
    });

    console.log(
      `Session "${name}" ready (${session.isTmux ? "tmux" : "raw shell"})`,
    );
  }

  /**
   * Create a new session backed by tmux
   */
  _createTmuxSession(name) {
    if (tmuxSessionExists(name)) {
      throw new Error(`tmux session "${name}" already exists`);
    }

    createTmuxSession(name);
    return this._attachToTmuxSession(name);
  }

  /**
   * Create a raw PTY session (fallback when tmux unavailable)
   */
  _createRawSession(name) {
    const shell = process.env.SHELL || "/bin/bash";
    const env = {
      ...process.env,
      TERM: "xterm-256color",
      COLORTERM: "truecolor",
      LANG: process.env.LANG || "en_US.UTF-8",
      LC_ALL: process.env.LC_ALL || process.env.LANG || "en_US.UTF-8",
    };

    const ptyProcess = pty.spawn(shell, ["-l"], {
      name: "xterm-256color",
      cols: 80,
      rows: 24,
      cwd: process.env.HOME || os.homedir(),
      env: env,
    });

    const session = {
      name,
      pty: ptyProcess,
      scrollback: [],
      clients: new Set(),
      createdAt: new Date(),
      isTmux: false,
    };

    this._setupPtyHandlers(session);
    this.sessions.set(name, session);

    console.log(`Created session "${name}" with shell ${shell} (no tmux)`);
    return session;
  }

  /**
   * Reconnect to a session whose PTY was disconnected but tmux is still running
   */
  reconnect(name) {
    const session = this.sessions.get(name);
    if (!session) {
      throw new Error(`Session "${name}" not found`);
    }

    if (session.pty) {
      return session;
    }

    if (!session.isTmux || !this.tmuxAvailable) {
      throw new Error(
        `Session "${name}" cannot be reconnected (not a tmux session)`,
      );
    }

    if (!tmuxSessionExists(name)) {
      this.sessions.delete(name);
      throw new Error(`tmux session "${name}" no longer exists`);
    }

    const tmuxName = getTmuxSessionName(name);
    const env = {
      ...process.env,
      TERM: "xterm-256color",
      COLORTERM: "truecolor",
      LANG: process.env.LANG || "en_US.UTF-8",
      LC_ALL: process.env.LC_ALL || process.env.LANG || "en_US.UTF-8",
    };

    const ptyProcess = pty.spawn("tmux", ["attach-session", "-t", tmuxName], {
      name: "xterm-256color",
      cols: 80,
      rows: 24,
      cwd: process.env.HOME || os.homedir(),
      env: env,
    });

    session.pty = ptyProcess;
    session.scrollback = [];
    this._setupPtyHandlers(session);

    console.log(`Reconnected to tmux session "${name}"`);
    return session;
  }

  list() {
    return Array.from(this.sessions.keys());
  }

  exists(name) {
    return this.sessions.has(name);
  }

  get(name) {
    return this.sessions.get(name);
  }

  create(name) {
    if (this.sessions.has(name)) {
      throw new Error(`Session "${name}" already exists`);
    }

    if (this.tmuxAvailable) {
      return this._createTmuxSession(name);
    }

    return this._createRawSession(name);
  }

  attach(name, ws) {
    const session = this.sessions.get(name);
    if (!session) {
      throw new Error(`Session "${name}" not found`);
    }

    // If PTY is disconnected but tmux session exists, reconnect
    if (!session.pty && session.isTmux) {
      this.reconnect(name);
    }

    session.clients.add(ws);
    if (session.scrollback.length > 0) {
      const scrollbackData = session.scrollback.join("");
      ws.send(
        JSON.stringify({
          type: "output",
          data: scrollbackData,
        }),
      );
    }

    console.log(
      `Client attached to session "${name}" (${session.clients.size} clients)`,
    );
    return session;
  }

  detach(name, ws) {
    const session = this.sessions.get(name);
    if (session) {
      session.clients.delete(ws);
      console.log(
        `Client detached from session "${name}" (${session.clients.size} clients)`,
      );
    }
  }

  detachAll(ws) {
    for (const [name, session] of this.sessions) {
      if (session.clients.has(ws)) {
        session.clients.delete(ws);
        console.log(
          `Client detached from session "${name}" (${session.clients.size} clients)`,
        );
      }
    }
  }

  write(name, data) {
    const session = this.sessions.get(name);
    if (!session) {
      throw new Error(`Session "${name}" not found`);
    }
    if (!session.pty) {
      throw new Error(`Session "${name}" is disconnected`);
    }
    session.pty.write(data);
  }

  resize(name, cols, rows) {
    const session = this.sessions.get(name);
    if (!session) {
      throw new Error(`Session "${name}" not found`);
    }
    if (!session.pty) {
      throw new Error(`Session "${name}" is disconnected`);
    }
    session.pty.resize(cols, rows);
    console.log(`Resized session "${name}" to ${cols}x${rows}`);
  }

  kill(name) {
    const session = this.sessions.get(name);
    if (!session) {
      throw new Error(`Session "${name}" not found`);
    }

    // Kill the tmux session if applicable
    if (session.isTmux && this.tmuxAvailable) {
      killTmuxSession(name);
    }

    // Kill the PTY process
    if (session.pty) {
      session.pty.kill();
    }

    for (const client of session.clients) {
      if (client.readyState === 1) {
        client.send(
          JSON.stringify({
            type: "killed",
            name: name,
          }),
        );
      }
    }

    this.sessions.delete(name);
    console.log(`Killed session "${name}"`);
  }

  rename(oldName, newName) {
    if (!this.sessions.has(oldName)) {
      throw new Error(`Session "${oldName}" not found`);
    }
    if (this.sessions.has(newName)) {
      throw new Error(`Session "${newName}" already exists`);
    }

    const session = this.sessions.get(oldName);

    // Rename the tmux session if applicable
    if (session.isTmux && this.tmuxAvailable) {
      renameTmuxSession(oldName, newName);
    }

    session.name = newName;
    this.sessions.delete(oldName);
    this.sessions.set(newName, session);

    for (const client of session.clients) {
      if (client.readyState === 1) {
        client.send(
          JSON.stringify({
            type: "renamed",
            oldName,
            newName,
          }),
        );
      }
    }

    console.log(`Renamed session "${oldName}" to "${newName}"`);
  }

  info(name) {
    const session = this.sessions.get(name);
    if (!session) {
      return null;
    }
    return {
      name: session.name,
      clientCount: session.clients.size,
      createdAt: session.createdAt,
      scrollbackLength: session.scrollback.length,
      isTmux: session.isTmux || false,
      isConnected: !!session.pty,
    };
  }

  setClipboard(content) {
    this.sharedClipboard = content || "";
    console.log(`Clipboard updated (${this.sharedClipboard.length} chars)`);
  }

  getClipboard() {
    return this.sharedClipboard;
  }

  /**
   * Gracefully detach all PTYs without killing tmux sessions
   * Called during server shutdown
   */
  detachAllPtys() {
    for (const [name, session] of this.sessions) {
      if (session.pty) {
        session.pty.kill();
        session.pty = null;
      }
    }
  }
}

export default SessionManager;
