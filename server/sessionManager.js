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
    // Shared clipboard (not persisted)
    this.sharedClipboard = '';
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

    const shell = process.env.SHELL || '/bin/bash';
    const env = {
      ...process.env,
      TERM: 'xterm-256color',
      COLORTERM: 'truecolor',
      LANG: process.env.LANG || 'en_US.UTF-8',
      LC_ALL: process.env.LC_ALL || process.env.LANG || 'en_US.UTF-8',
    };

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
      clients: new Set(),
      createdAt: new Date(),
    };

    ptyProcess.onData((data) => {
      session.scrollback.push(data);
      let totalLength = 0;
      for (const chunk of session.scrollback) {
        totalLength += chunk.length;
      }
      while (totalLength > this.scrollbackSize * 200 && session.scrollback.length > 0) {
        const removed = session.scrollback.shift();
        totalLength -= removed.length;
      }

      for (const client of session.clients) {
        if (client.readyState === 1) {
          client.send(JSON.stringify({
            type: 'output',
            data: data,
          }));
        }
      }
    });

    ptyProcess.onExit(({ exitCode, signal }) => {
      console.log(`Session "${name}" exited with code ${exitCode}, signal ${signal}`);
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
      this.sessions.delete(name);
    });

    this.sessions.set(name, session);
    console.log(`Created session "${name}" with shell ${shell}`);
    return session;
  }

  attach(name, ws) {
    const session = this.sessions.get(name);
    if (!session) {
      throw new Error(`Session "${name}" not found`);
    }

    session.clients.add(ws);
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

  detach(name, ws) {
    const session = this.sessions.get(name);
    if (session) {
      session.clients.delete(ws);
      console.log(`Client detached from session "${name}" (${session.clients.size} clients)`);
    }
  }

  detachAll(ws) {
    for (const [name, session] of this.sessions) {
      if (session.clients.has(ws)) {
        session.clients.delete(ws);
        console.log(`Client detached from session "${name}" (${session.clients.size} clients)`);
      }
    }
  }

  write(name, data) {
    const session = this.sessions.get(name);
    if (!session) {
      throw new Error(`Session "${name}" not found`);
    }
    session.pty.write(data);
  }

  resize(name, cols, rows) {
    const session = this.sessions.get(name);
    if (!session) {
      throw new Error(`Session "${name}" not found`);
    }
    session.pty.resize(cols, rows);
    console.log(`Resized session "${name}" to ${cols}x${rows}`);
  }

  kill(name) {
    const session = this.sessions.get(name);
    if (!session) {
      throw new Error(`Session "${name}" not found`);
    }

    session.pty.kill();
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

  setClipboard(content) {
    this.sharedClipboard = content || '';
    console.log(`Clipboard updated (${this.sharedClipboard.length} chars)`);
  }

  getClipboard() {
    return this.sharedClipboard;
  }
}

export default SessionManager;
