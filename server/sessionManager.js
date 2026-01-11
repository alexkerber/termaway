import pty from "node-pty";
import os from "os";

// =============================================================================
// Configuration
// =============================================================================

const CONFIG = {
  defaultCols: 80,
  defaultRows: 24,
  maxScrollback: 2_000_000, // ~2MB of scrollback per session
};

// =============================================================================
// Session Class
// =============================================================================

class Session {
  constructor(name, ptyProcess) {
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
  constructor() {
    this.sessions = new Map();
    this.clipboard = "";
    console.log("Session manager ready (PTY mode)");
  }

  // ---------------------------------------------------------------------------
  // Session Lifecycle
  // ---------------------------------------------------------------------------

  create(name) {
    if (this.sessions.has(name)) {
      throw new Error(`Session "${name}" already exists`);
    }

    const shell = process.env.SHELL || "/bin/bash";
    const ptyProcess = pty.spawn(shell, ["-l"], {
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

    const session = new Session(name, ptyProcess);
    this.sessions.set(name, session);
    this._setupHandlers(session);

    console.log(`Created session "${name}"`);
    return session;
  }

  kill(name) {
    const session = this.sessions.get(name);
    if (!session) {
      throw new Error(`Session "${name}" not found`);
    }

    session.pty.kill();
    session.broadcast({ type: "killed", name });
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

      console.log(
        `Sending scrollback (${scrollback.length} bytes, ${session.scrollback.length} chunks)`,
      );

      if (scrollback.length <= CHUNK_SIZE) {
        // Small enough to send in one message
        session.send(ws, { type: "output", data: scrollback });
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
          session.send(ws, { type: "output", data: chunk });
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

    console.log(
      `Client attached to "${name}" (${session.clients.size} clients)`,
    );

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
    }
  }

  detachAll(ws) {
    for (const [name, session] of this.sessions) {
      if (session.clients.delete(ws)) {
        console.log(
          `Client detached from "${name}" (${session.clients.size} clients)`,
        );
        // Recalculate size now that this client is gone
        this._recalculateSize(session);
      }
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
  }

  resize(name, cols, rows, ws = null) {
    const session = this.sessions.get(name);
    if (!session) {
      throw new Error(`Session "${name}" not found`);
    }

    // Ignore tiny sizes that break terminal rendering
    if (cols < 10 || rows < 5) {
      console.log(`Ignoring tiny resize for "${name}": ${cols}x${rows}`);
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
      console.log(`Ignoring rapid resize for "${name}": ${minCols}x${minRows}`);
      return;
    }

    session.lastCols = minCols;
    session.lastRows = minRows;
    session.lastResizeAt = now;
    session.pty.resize(minCols, minRows);
    console.log(
      `Resized "${name}" to ${minCols}x${minRows} (min of ${session.clients.size} clients)`,
    );
  }

  // ---------------------------------------------------------------------------
  // Queries
  // ---------------------------------------------------------------------------

  list() {
    return Array.from(this.sessions.keys());
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
      isTmux: false,
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
      session.broadcast({ type: "output", data });
    });

    session.pty.onExit(({ exitCode, signal }) => {
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
}

export default SessionManager;
