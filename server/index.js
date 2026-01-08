import express from 'express';
import { createServer } from 'http';
import { WebSocketServer } from 'ws';
import path from 'path';
import os from 'os';
import { fileURLToPath } from 'url';
import { Bonjour } from 'bonjour-service';
import SessionManager from './sessionManager.js';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

// Configuration
const PORT = process.env.PORT || 3000;
const HOST = process.env.HOST || '0.0.0.0';
const SERVICE_NAME = process.env.SERVICE_NAME || `Claude Terminal (${os.hostname()})`;

// Initialize Express app
const app = express();
const server = createServer(app);

// Initialize WebSocket server
const wss = new WebSocketServer({ server });

// Initialize session manager
const sessionManager = new SessionManager();

// Serve static files from client directory
app.use(express.static(path.join(__dirname, '..', 'client')));

// Serve xterm.js from node_modules
app.use('/xterm', express.static(path.join(__dirname, '..', 'node_modules', 'xterm')));
app.use('/xterm-addon-fit', express.static(path.join(__dirname, '..', 'node_modules', '@xterm', 'addon-fit')));
app.use('/xterm-addon-webgl', express.static(path.join(__dirname, '..', 'node_modules', '@xterm', 'addon-webgl')));
app.use('/xterm-addon-web-links', express.static(path.join(__dirname, '..', 'node_modules', '@xterm', 'addon-web-links')));

// API endpoint to list sessions (for debugging/health check)
app.get('/api/sessions', (req, res) => {
  res.json({ sessions: sessionManager.list() });
});

// Track which session each WebSocket is attached to
const wsSessionMap = new WeakMap();

// WebSocket connection handling
wss.on('connection', (ws, req) => {
  console.log(`WebSocket connected from ${req.socket.remoteAddress}`);

  ws.on('message', (message) => {
    let msg;
    try {
      msg = JSON.parse(message.toString());
    } catch (e) {
      ws.send(JSON.stringify({ type: 'error', message: 'Invalid JSON' }));
      return;
    }

    handleMessage(ws, msg);
  });

  ws.on('close', () => {
    console.log('WebSocket disconnected');
    sessionManager.detachAll(ws);
    wsSessionMap.delete(ws);
  });

  ws.on('error', (error) => {
    console.error('WebSocket error:', error);
    sessionManager.detachAll(ws);
    wsSessionMap.delete(ws);
  });
});

/**
 * Handle incoming WebSocket messages
 */
function handleMessage(ws, msg) {
  try {
    switch (msg.type) {
      case 'list':
        handleList(ws);
        break;

      case 'create':
        handleCreate(ws, msg.name);
        break;

      case 'attach':
        handleAttach(ws, msg.name);
        break;

      case 'input':
        handleInput(ws, msg.data);
        break;

      case 'resize':
        handleResize(ws, msg.cols, msg.rows);
        break;

      case 'kill':
        handleKill(ws, msg.name);
        break;

      case 'rename':
        handleRename(ws, msg.oldName, msg.newName);
        break;

      case 'detach':
        handleDetach(ws);
        break;

      default:
        ws.send(JSON.stringify({ type: 'error', message: `Unknown message type: ${msg.type}` }));
    }
  } catch (error) {
    console.error('Error handling message:', error);
    ws.send(JSON.stringify({ type: 'error', message: error.message }));
  }
}

/**
 * List all sessions
 */
function handleList(ws) {
  const sessions = sessionManager.list().map(name => {
    const info = sessionManager.info(name);
    return {
      name,
      clientCount: info.clientCount,
      createdAt: info.createdAt,
    };
  });
  ws.send(JSON.stringify({ type: 'sessions', list: sessions }));
}

/**
 * Create a new session
 */
function handleCreate(ws, name) {
  if (!name || typeof name !== 'string') {
    ws.send(JSON.stringify({ type: 'error', message: 'Session name is required' }));
    return;
  }

  // Sanitize session name
  const sanitizedName = name.trim().replace(/[^a-zA-Z0-9-_]/g, '-');
  if (!sanitizedName) {
    ws.send(JSON.stringify({ type: 'error', message: 'Invalid session name' }));
    return;
  }

  if (sessionManager.exists(sanitizedName)) {
    ws.send(JSON.stringify({ type: 'error', message: `Session "${sanitizedName}" already exists` }));
    return;
  }

  sessionManager.create(sanitizedName);
  sessionManager.attach(sanitizedName, ws);
  wsSessionMap.set(ws, sanitizedName);

  ws.send(JSON.stringify({ type: 'created', name: sanitizedName }));
  ws.send(JSON.stringify({ type: 'attached', name: sanitizedName }));

  // Broadcast updated session list to all clients
  broadcastSessionList();
}

/**
 * Attach to an existing session
 */
function handleAttach(ws, name) {
  if (!name || typeof name !== 'string') {
    ws.send(JSON.stringify({ type: 'error', message: 'Session name is required' }));
    return;
  }

  if (!sessionManager.exists(name)) {
    ws.send(JSON.stringify({ type: 'error', message: `Session "${name}" not found` }));
    return;
  }

  // Detach from current session if any
  const currentSession = wsSessionMap.get(ws);
  if (currentSession) {
    sessionManager.detach(currentSession, ws);
  }

  sessionManager.attach(name, ws);
  wsSessionMap.set(ws, name);

  ws.send(JSON.stringify({ type: 'attached', name }));
}

/**
 * Handle terminal input
 */
function handleInput(ws, data) {
  const sessionName = wsSessionMap.get(ws);
  if (!sessionName) {
    ws.send(JSON.stringify({ type: 'error', message: 'Not attached to any session' }));
    return;
  }

  sessionManager.write(sessionName, data);
}

/**
 * Handle terminal resize
 */
function handleResize(ws, cols, rows) {
  const sessionName = wsSessionMap.get(ws);
  if (!sessionName) {
    // Silently ignore resize if not attached
    return;
  }

  if (typeof cols !== 'number' || typeof rows !== 'number' || cols < 1 || rows < 1) {
    return;
  }

  sessionManager.resize(sessionName, cols, rows);
}

/**
 * Kill a session
 */
function handleKill(ws, name) {
  if (!name || typeof name !== 'string') {
    ws.send(JSON.stringify({ type: 'error', message: 'Session name is required' }));
    return;
  }

  if (!sessionManager.exists(name)) {
    ws.send(JSON.stringify({ type: 'error', message: `Session "${name}" not found` }));
    return;
  }

  // If the caller is attached to this session, detach first
  const currentSession = wsSessionMap.get(ws);
  if (currentSession === name) {
    wsSessionMap.delete(ws);
  }

  sessionManager.kill(name);

  ws.send(JSON.stringify({ type: 'killed', name }));

  // Broadcast updated session list to all clients
  broadcastSessionList();
}

/**
 * Rename a session
 */
function handleRename(ws, oldName, newName) {
  if (!oldName || !newName) {
    ws.send(JSON.stringify({ type: 'error', message: 'Both old and new names are required' }));
    return;
  }

  const sanitizedNewName = newName.trim().replace(/[^a-zA-Z0-9-_]/g, '-');
  if (!sanitizedNewName) {
    ws.send(JSON.stringify({ type: 'error', message: 'Invalid new session name' }));
    return;
  }

  sessionManager.rename(oldName, sanitizedNewName);

  // Update session map for all attached clients
  for (const client of wss.clients) {
    if (wsSessionMap.get(client) === oldName) {
      wsSessionMap.set(client, sanitizedNewName);
    }
  }

  // Broadcast updated session list to all clients
  broadcastSessionList();
}

/**
 * Detach from current session
 */
function handleDetach(ws) {
  const currentSession = wsSessionMap.get(ws);
  if (currentSession) {
    sessionManager.detach(currentSession, ws);
    wsSessionMap.delete(ws);
    ws.send(JSON.stringify({ type: 'detached' }));
  }
}

/**
 * Broadcast session list to all connected clients
 */
function broadcastSessionList() {
  const sessions = sessionManager.list().map(name => {
    const info = sessionManager.info(name);
    return {
      name,
      clientCount: info.clientCount,
      createdAt: info.createdAt,
    };
  });

  const message = JSON.stringify({ type: 'sessions', list: sessions });

  for (const client of wss.clients) {
    if (client.readyState === 1) { // WebSocket.OPEN
      client.send(message);
    }
  }
}

// Initialize Bonjour/mDNS
const bonjour = new Bonjour();
let bonjourService = null;

// Get local IP address
function getLocalIP() {
  const interfaces = os.networkInterfaces();
  for (const name of Object.keys(interfaces)) {
    for (const iface of interfaces[name]) {
      if (iface.family === 'IPv4' && !iface.internal) {
        return iface.address;
      }
    }
  }
  return 'localhost';
}

// Start server
server.listen(PORT, HOST, () => {
  const localIP = getLocalIP();
  console.log(`Web Terminal Server running at http://${HOST}:${PORT}`);
  console.log(`Access from LAN: http://${localIP}:${PORT}`);
  console.log('');

  // Publish mDNS service for discovery
  bonjourService = bonjour.publish({
    name: SERVICE_NAME,
    type: 'http',
    port: parseInt(PORT, 10),
    txt: {
      path: '/',
      protocol: 'ws',
    }
  });

  console.log(`Bonjour: Published as "${SERVICE_NAME}" (_http._tcp)`);
  console.log('         Discoverable on local network');
  console.log('');
  console.log('Press Ctrl+C to stop the server');
});

// Graceful shutdown
process.on('SIGINT', () => {
  console.log('\nShutting down...');

  // Unpublish Bonjour service
  if (bonjourService) {
    bonjourService.stop();
  }
  bonjour.destroy();

  // Kill all sessions
  for (const name of sessionManager.list()) {
    try {
      sessionManager.kill(name);
    } catch (e) {
      // Ignore errors during shutdown
    }
  }

  // Close WebSocket server
  wss.close(() => {
    // Close HTTP server
    server.close(() => {
      console.log('Server stopped');
      process.exit(0);
    });
  });
});
