import pty from 'node-pty';
import os from 'os';

/**
 * Manages PTY sessions with named persistent sessions
 */
class SessionManager {
  constructor() {
    // Map of session name -> session object
    this.sessions = new Map();
    // Scrollback buffer size
    this.scrollbackSize = 10000;
  }

  /**
   * Get list of all session names
   */
  list() {
    return Array.from(this.sessions.keys());
  }

  /**
   * Check if a session exists
   */
  exists(name) {
    return this.sessions.has(name);
  }

  /**
   * Get a session by name
   */
  get(name) {
    return this.sessions.get(name);
  }

  /**
   * Create a new named session
   */
  create(name) {
    if (this.sessions.has(name)) {
      throw new Error(`Session "${name}" already exists`);
    }

    // Get user's default shell
    const shell = process.env.SHELL || '/bin/bash';

    // Build environment for the PTY
    const env = {
      ...process.env,
      TERM: 'xterm-256color',
      COLORTERM: 'truecolor',
      LANG: process.env.LANG || 'en_US.UTF-8',
      LC_ALL: process.env.LC_ALL || process.env.LANG || 'en_US.UTF-8',
    };

    // Spawn PTY with login shell to source dotfiles
    const ptyProcess = pty.spawn(shell, ['-l'], {
      name: 'xterm-256color',
      cols: 80,
      rows: 24,
      cwd: process.env.HOME || os.homedir(),
      env: env,
    });

    const session = {
      name,
      pty: ptyProcess,
      scrollback: [],
      clients: new Set(), // WebSocket clients attached to this session
      createdAt: new Date(),
    };

    // Capture output for scrollback buffer
    ptyProcess.onData((data) => {
      // Add to scrollback buffer
      session.scrollback.push(data);

      // Trim scrollback if too large (rough character limit)
      let totalLength = 0;
      for (const chunk of session.scrollback) {
        totalLength += chunk.length;
      }
      while (totalLength > this.scrollbackSize * 200 && session.scrollback.length > 0) {
        const removed = session.scrollback.shift();
        totalLength -= removed.length;
      }

      // Broadcast to all attached clients
      for (const client of session.clients) {
        if (client.readyState === 1) { // WebSocket.OPEN
          client.send(JSON.stringify({
            type: 'output',
            data: data,
          }));
        }
      }
    });

    ptyProcess.onExit(({ exitCode, signal }) => {
      console.log(`Session "${name}" exited with code ${exitCode}, signal ${signal}`);

      // Notify clients
      for (const client of session.clients) {
        if (client.readyState === 1) {
          client.send(JSON.stringify({
            type: 'exited',
            name: name,
            exitCode,
            signal,
          }));
        }
      }

      // Remove session
      this.sessions.delete(name);
    });

    this.sessions.set(name, session);
    console.log(`Created session "${name}" with shell ${shell}`);

    return session;
  }

  /**
   * Attach a WebSocket client to a session
   */
  attach(name, ws) {
    const session = this.sessions.get(name);
    if (!session) {
      throw new Error(`Session "${name}" not found`);
    }

    session.clients.add(ws);

    // Send scrollback buffer to catch up the client
    if (session.scrollback.length > 0) {
      const scrollbackData = session.scrollback.join('');
      ws.send(JSON.stringify({
        type: 'output',
        data: scrollbackData,
      }));
    }

    console.log(`Client attached to session "${name}" (${session.clients.size} clients)`);
    return session;
  }

  /**
   * Detach a WebSocket client from a session
   */
  detach(name, ws) {
    const session = this.sessions.get(name);
    if (session) {
      session.clients.delete(ws);
      console.log(`Client detached from session "${name}" (${session.clients.size} clients)`);
    }
  }

  /**
   * Detach a WebSocket client from all sessions
   */
  detachAll(ws) {
    for (const [name, session] of this.sessions) {
      if (session.clients.has(ws)) {
        session.clients.delete(ws);
        console.log(`Client detached from session "${name}" (${session.clients.size} clients)`);
      }
    }
  }

  /**
   * Send input to a session
   */
  write(name, data) {
    const session = this.sessions.get(name);
    if (!session) {
      throw new Error(`Session "${name}" not found`);
    }
    session.pty.write(data);
  }

  /**
   * Resize a session's PTY
   */
  resize(name, cols, rows) {
    const session = this.sessions.get(name);
    if (!session) {
      throw new Error(`Session "${name}" not found`);
    }
    session.pty.resize(cols, rows);
    console.log(`Resized session "${name}" to ${cols}x${rows}`);
  }

  /**
   * Kill a session
   */
  kill(name) {
    const session = this.sessions.get(name);
    if (!session) {
      throw new Error(`Session "${name}" not found`);
    }

    // Kill the PTY process
    session.pty.kill();

    // Notify clients
    for (const client of session.clients) {
      if (client.readyState === 1) {
        client.send(JSON.stringify({
          type: 'killed',
          name: name,
        }));
      }
    }

    this.sessions.delete(name);
    console.log(`Killed session "${name}"`);
  }

  /**
   * Rename a session
   */
  rename(oldName, newName) {
    if (!this.sessions.has(oldName)) {
      throw new Error(`Session "${oldName}" not found`);
    }
    if (this.sessions.has(newName)) {
      throw new Error(`Session "${newName}" already exists`);
    }

    const session = this.sessions.get(oldName);
    session.name = newName;
    this.sessions.delete(oldName);
    this.sessions.set(newName, session);

    // Notify clients
    for (const client of session.clients) {
      if (client.readyState === 1) {
        client.send(JSON.stringify({
          type: 'renamed',
          oldName,
          newName,
        }));
      }
    }

    console.log(`Renamed session "${oldName}" to "${newName}"`);
  }

  /**
   * Get session info
   */
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
    };
  }
}

export default SessionManager;
