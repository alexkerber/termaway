import express from "express";
import { createServer as createHttpServer } from "http";
import { createServer as createHttpsServer } from "https";
import { readFileSync, existsSync } from "fs";
import { timingSafeEqual } from "crypto";
import { WebSocketServer } from "ws";
import path from "path";
import os from "os";
import { fileURLToPath } from "url";
import { Bonjour } from "bonjour-service";
import SessionManager from "./sessionManager.js";

// Timing-safe password comparison to prevent timing attacks
function safeCompare(a, b) {
  if (typeof a !== "string" || typeof b !== "string") return false;
  const bufA = Buffer.from(a);
  const bufB = Buffer.from(b);
  if (bufA.length !== bufB.length) {
    // Compare against self to maintain constant time even on length mismatch
    timingSafeEqual(bufA, bufA);
    return false;
  }
  return timingSafeEqual(bufA, bufB);
}

// Rate limiting for authentication attempts
const authAttempts = new Map(); // IP -> { count, firstAttempt }
const MAX_AUTH_ATTEMPTS = 5;
const AUTH_WINDOW_MS = 60000; // 1 minute window

// Helper: Get formatted session list
function getSessionList() {
  return sessionManager.list().map((name) => {
    const info = sessionManager.info(name);
    return {
      name,
      clientCount: info.clientCount,
      createdAt: info.createdAt,
      isTmux: info.isTmux,
      isConnected: info.isConnected,
    };
  });
}

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

// Parse command line arguments
function parseArgs() {
  const args = process.argv.slice(2);
  const config = {};
  for (let i = 0; i < args.length; i++) {
    if (args[i] === "--password" && args[i + 1]) {
      config.password = args[i + 1];
      i++;
    } else if (args[i] === "--port" && args[i + 1]) {
      config.port = args[i + 1];
      i++;
    }
  }
  return config;
}

const cliArgs = parseArgs();

// Configuration
const PORT = cliArgs.port || process.env.PORT || 3000;
const HOST = process.env.HOST || "0.0.0.0";
const SERVICE_NAME = process.env.SERVICE_NAME || `TermAway (${os.hostname()})`;
const PASSWORD = cliArgs.password || process.env.TERMAWAY_PASSWORD || null;

// TLS certificate paths
const CERTS_DIR = path.join(os.homedir(), ".termaway", "certs");
const KEY_PATH = path.join(CERTS_DIR, "server.key");
const CERT_PATH = path.join(CERTS_DIR, "server.crt");

// Check if TLS certificates exist
const hasTLS = existsSync(KEY_PATH) && existsSync(CERT_PATH);
let tlsOptions = null;

if (hasTLS) {
  try {
    tlsOptions = {
      key: readFileSync(KEY_PATH),
      cert: readFileSync(CERT_PATH),
    };
  } catch (error) {
    console.warn("Failed to load TLS certificates:", error.message);
  }
}

// Initialize Express app
const app = express();
const server = tlsOptions
  ? createHttpsServer(tlsOptions, app)
  : createHttpServer(app);

// Initialize WebSocket server
const wss = new WebSocketServer({ server });

// Initialize session manager
const sessionManager = new SessionManager();

// Heartbeat to detect stale connections
const HEARTBEAT_INTERVAL = 30000; // 30 seconds
const wsAliveMap = new WeakMap();

const heartbeatInterval = setInterval(() => {
  for (const ws of wss.clients) {
    if (wsAliveMap.get(ws) === false) {
      // Didn't respond to last ping, terminate
      console.log("Terminating stale WebSocket connection");
      ws.terminate();
      continue;
    }
    wsAliveMap.set(ws, false);
    ws.ping();
  }
}, HEARTBEAT_INTERVAL);

// Serve static files from web client directory (no caching for development)
app.use(
  express.static(path.join(__dirname, "..", "apps", "web"), {
    etag: false,
    lastModified: false,
    setHeaders: (res) => {
      res.setHeader(
        "Cache-Control",
        "no-store, no-cache, must-revalidate, proxy-revalidate",
      );
      res.setHeader("Pragma", "no-cache");
      res.setHeader("Expires", "0");
    },
  }),
);

// Serve xterm.js from node_modules
app.use(
  "/xterm",
  express.static(path.join(__dirname, "..", "node_modules", "xterm")),
);
app.use(
  "/xterm-addon-fit",
  express.static(
    path.join(__dirname, "..", "node_modules", "@xterm", "addon-fit"),
  ),
);
app.use(
  "/xterm-addon-webgl",
  express.static(
    path.join(__dirname, "..", "node_modules", "@xterm", "addon-webgl"),
  ),
);
app.use(
  "/xterm-addon-web-links",
  express.static(
    path.join(__dirname, "..", "node_modules", "@xterm", "addon-web-links"),
  ),
);

// API endpoint to list sessions (for debugging/health check)
app.get("/api/sessions", (req, res) => {
  res.json({ sessions: sessionManager.list() });
});

// Track which session each WebSocket is attached to
const wsSessionMap = new WeakMap();

// Track authenticated WebSocket connections
const wsAuthMap = new WeakMap();

// Track client metadata for notifications
const wsClientInfo = new WeakMap();

// Get connected client count
function getConnectedClientCount() {
  let count = 0;
  for (const client of wss.clients) {
    if (wsAuthMap.get(client)) count++;
  }
  return count;
}

// Broadcast client connection event to all clients
function broadcastClientEvent(eventType, clientIP) {
  const message = JSON.stringify({
    type: eventType,
    clientIP,
    clientCount: getConnectedClientCount(),
    timestamp: new Date().toISOString(),
  });
  for (const client of wss.clients) {
    if (client.readyState === 1) {
      client.send(message);
    }
  }
}

// WebSocket connection handling
wss.on("connection", (ws, req) => {
  const clientIP =
    req.socket.remoteAddress?.replace("::ffff:", "") || "unknown";
  console.log(`WebSocket connected from ${clientIP}`);

  // Mark as alive for heartbeat
  wsAliveMap.set(ws, true);
  ws.on("pong", () => wsAliveMap.set(ws, true));

  // Store client info
  wsClientInfo.set(ws, { ip: clientIP, connectedAt: new Date() });

  // If no password is set, auto-authenticate and broadcast
  if (!PASSWORD) {
    wsAuthMap.set(ws, true);
    // Defer broadcast to next tick to ensure client setup is complete
    setImmediate(() => broadcastClientEvent("client-connected", clientIP));
  }

  // Send auth requirement status
  ws.send(
    JSON.stringify({
      type: "auth-required",
      required: !!PASSWORD,
    }),
  );

  ws.on("message", (message) => {
    let msg;
    try {
      msg = JSON.parse(message.toString());
    } catch (e) {
      ws.send(JSON.stringify({ type: "error", message: "Invalid JSON" }));
      return;
    }

    // Handle auth message separately
    if (msg.type === "auth") {
      handleAuth(ws, msg.password);
      return;
    }

    // Block all other messages if not authenticated
    if (PASSWORD && !wsAuthMap.get(ws)) {
      ws.send(
        JSON.stringify({ type: "error", message: "Authentication required" }),
      );
      return;
    }

    handleMessage(ws, msg);
  });

  // Helper to clean up WebSocket state
  function cleanup() {
    const wasAuthenticated = wsAuthMap.get(ws);
    const clientInfo = wsClientInfo.get(ws);
    sessionManager.detachAll(ws);
    wsSessionMap.delete(ws);
    wsAuthMap.delete(ws);
    wsClientInfo.delete(ws);
    if (wasAuthenticated && clientInfo) {
      broadcastClientEvent("client-disconnected", clientInfo.ip);
    }
  }

  ws.on("close", () => {
    console.log("WebSocket disconnected");
    cleanup();
  });

  ws.on("error", (error) => {
    console.error("WebSocket error:", error);
    cleanup();
  });
});

/**
 * Handle authentication
 */
function handleAuth(ws, password) {
  const clientInfo = wsClientInfo.get(ws);
  const clientIP = clientInfo?.ip || "unknown";
  const wasAlreadyAuthenticated = wsAuthMap.get(ws);

  if (!PASSWORD) {
    // No password required - already auto-authenticated at connection
    wsAuthMap.set(ws, true);
    ws.send(JSON.stringify({ type: "auth-success" }));
    // Don't broadcast again if already authenticated
    if (!wasAlreadyAuthenticated) {
      broadcastClientEvent("client-connected", clientIP);
    }
    return;
  }

  // Rate limiting check
  const now = Date.now();
  const attempts = authAttempts.get(clientIP) || {
    count: 0,
    firstAttempt: now,
  };

  // Reset if window has passed
  if (now - attempts.firstAttempt > AUTH_WINDOW_MS) {
    attempts.count = 0;
    attempts.firstAttempt = now;
  }

  if (attempts.count >= MAX_AUTH_ATTEMPTS) {
    const remainingMs = AUTH_WINDOW_MS - (now - attempts.firstAttempt);
    const remainingSec = Math.ceil(remainingMs / 1000);
    console.log(`Rate limited auth attempt from ${clientIP}`);
    ws.send(
      JSON.stringify({
        type: "auth-failed",
        message: `Too many attempts. Try again in ${remainingSec}s`,
      }),
    );
    return;
  }

  if (safeCompare(password, PASSWORD)) {
    // Success - clear rate limit for this IP
    authAttempts.delete(clientIP);
    wsAuthMap.set(ws, true);
    console.log("Client authenticated successfully");
    ws.send(JSON.stringify({ type: "auth-success" }));
    if (!wasAlreadyAuthenticated) {
      broadcastClientEvent("client-connected", clientIP);
    }
  } else {
    // Failed - increment rate limit counter
    attempts.count++;
    authAttempts.set(clientIP, attempts);
    console.log(
      `Client authentication failed (attempt ${attempts.count}/${MAX_AUTH_ATTEMPTS})`,
    );
    ws.send(
      JSON.stringify({ type: "auth-failed", message: "Invalid password" }),
    );
  }
}

/**
 * Handle incoming WebSocket messages
 */
function handleMessage(ws, msg) {
  try {
    switch (msg.type) {
      case "list":
        handleList(ws);
        break;

      case "create":
        handleCreate(ws, msg.name);
        break;

      case "attach":
        handleAttach(ws, msg.name);
        break;

      case "input":
        handleInput(ws, msg.data);
        break;

      case "resize":
        handleResize(ws, msg.cols, msg.rows);
        break;

      case "kill":
        handleKill(ws, msg.name);
        break;

      case "rename":
        handleRename(ws, msg.oldName, msg.newName);
        break;

      case "detach":
        handleDetach(ws);
        break;

      case "clipboard-set":
        handleClipboardSet(ws, msg.content);
        break;

      case "clipboard-get":
        handleClipboardGet(ws);
        break;

      case "list-clients":
        handleListClients(ws);
        break;

      case "kick-client":
        handleKickClient(ws, msg.clientId);
        break;

      default:
        ws.send(
          JSON.stringify({
            type: "error",
            message: `Unknown message type: ${msg.type}`,
          }),
        );
    }
  } catch (error) {
    console.error("Error handling message:", error);
    ws.send(JSON.stringify({ type: "error", message: error.message }));
  }
}

/**
 * List all sessions
 */
function handleList(ws) {
  ws.send(JSON.stringify({ type: "sessions", list: getSessionList() }));
}

/**
 * Create a new session
 */
function handleCreate(ws, name) {
  if (!name || typeof name !== "string") {
    ws.send(
      JSON.stringify({ type: "error", message: "Session name is required" }),
    );
    return;
  }

  // Sanitize session name
  const sanitizedName = name.trim().replace(/[^a-zA-Z0-9-_]/g, "-");
  if (!sanitizedName) {
    ws.send(JSON.stringify({ type: "error", message: "Invalid session name" }));
    return;
  }

  if (sessionManager.exists(sanitizedName)) {
    ws.send(
      JSON.stringify({
        type: "error",
        message: `Session "${sanitizedName}" already exists`,
      }),
    );
    return;
  }

  sessionManager.create(sanitizedName);
  sessionManager.attach(sanitizedName, ws);
  wsSessionMap.set(ws, sanitizedName);

  ws.send(JSON.stringify({ type: "created", name: sanitizedName }));
  ws.send(JSON.stringify({ type: "attached", name: sanitizedName }));

  // Broadcast updated session list to all clients
  broadcastSessionList();
}

/**
 * Attach to an existing session.
 * Waits for all scrollback to be sent before confirming attachment.
 * This ensures the client receives all history before updating its UI.
 */
async function handleAttach(ws, name) {
  if (!name || typeof name !== "string") {
    ws.send(
      JSON.stringify({ type: "error", message: "Session name is required" }),
    );
    return;
  }

  if (!sessionManager.exists(name)) {
    ws.send(
      JSON.stringify({ type: "error", message: `Session "${name}" not found` }),
    );
    return;
  }

  // Detach from current session if any
  const currentSession = wsSessionMap.get(ws);
  if (currentSession) {
    sessionManager.detach(currentSession, ws);
  }

  const session = sessionManager.attach(name, ws);
  wsSessionMap.set(ws, name);

  // Wait for all scrollback chunks to be sent before confirming
  // This prevents the client from creating its terminal too early
  if (session.scrollbackPromise) {
    await session.scrollbackPromise;
  }

  ws.send(JSON.stringify({ type: "attached", name }));
}

/**
 * Handle terminal input
 */
function handleInput(ws, data) {
  const sessionName = wsSessionMap.get(ws);
  if (!sessionName) {
    ws.send(
      JSON.stringify({ type: "error", message: "Not attached to any session" }),
    );
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

  if (
    typeof cols !== "number" ||
    typeof rows !== "number" ||
    cols < 1 ||
    rows < 1
  ) {
    return;
  }

  sessionManager.resize(sessionName, cols, rows, ws);
}

/**
 * Kill a session
 */
function handleKill(ws, name) {
  if (!name || typeof name !== "string") {
    ws.send(
      JSON.stringify({ type: "error", message: "Session name is required" }),
    );
    return;
  }

  if (!sessionManager.exists(name)) {
    ws.send(
      JSON.stringify({ type: "error", message: `Session "${name}" not found` }),
    );
    return;
  }

  // If the caller is attached to this session, detach first
  const currentSession = wsSessionMap.get(ws);
  if (currentSession === name) {
    wsSessionMap.delete(ws);
  }

  sessionManager.kill(name);

  ws.send(JSON.stringify({ type: "killed", name }));

  // Broadcast updated session list to all clients
  broadcastSessionList();
}

/**
 * Rename a session
 */
function handleRename(ws, oldName, newName) {
  if (!oldName || !newName) {
    ws.send(
      JSON.stringify({
        type: "error",
        message: "Both old and new names are required",
      }),
    );
    return;
  }

  const sanitizedNewName = newName.trim().replace(/[^a-zA-Z0-9-_]/g, "-");
  if (!sanitizedNewName) {
    ws.send(
      JSON.stringify({ type: "error", message: "Invalid new session name" }),
    );
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
    ws.send(JSON.stringify({ type: "detached" }));
  }
}

/**
 * Set clipboard content
 */
const MAX_CLIPBOARD_SIZE = 1024 * 1024; // 1MB limit

function handleClipboardSet(ws, content) {
  if (typeof content !== "string") {
    ws.send(
      JSON.stringify({ type: "error", message: "Invalid clipboard content" }),
    );
    return;
  }
  if (content.length > MAX_CLIPBOARD_SIZE) {
    ws.send(
      JSON.stringify({ type: "error", message: "Clipboard content too large" }),
    );
    return;
  }

  sessionManager.setClipboard(content);
  // Broadcast to all other connected clients
  const message = JSON.stringify({ type: "clipboard-update", content });
  for (const client of wss.clients) {
    if (client !== ws && client.readyState === 1) {
      client.send(message);
    }
  }
  ws.send(JSON.stringify({ type: "clipboard-set-ok" }));
}

/**
 * Get clipboard content
 */
function handleClipboardGet(ws) {
  const content = sessionManager.getClipboard();
  ws.send(JSON.stringify({ type: "clipboard-content", content }));
}

/**
 * List all connected clients
 */
function handleListClients(ws) {
  const clients = [];
  let id = 0;
  for (const client of wss.clients) {
    if (wsAuthMap.get(client)) {
      const info = wsClientInfo.get(client);
      const sessionName = wsSessionMap.get(client);
      clients.push({
        id: id++,
        ip: info?.ip || "unknown",
        connectedAt: info?.connectedAt?.toISOString() || null,
        session: sessionName || null,
      });
    }
  }
  ws.send(JSON.stringify({ type: "clients", list: clients }));
}

/**
 * Kick a specific client by ID
 */
function handleKickClient(ws, clientId) {
  let id = 0;
  for (const client of wss.clients) {
    if (wsAuthMap.get(client)) {
      if (id === clientId) {
        // Don't allow kicking yourself
        if (client === ws) {
          ws.send(
            JSON.stringify({ type: "error", message: "Cannot kick yourself" }),
          );
          return;
        }
        const info = wsClientInfo.get(client);
        console.log(`Kicking client ${info?.ip}`);
        client.close(1000, "Kicked by admin");
        ws.send(JSON.stringify({ type: "client-kicked", clientId }));
        return;
      }
      id++;
    }
  }
  ws.send(JSON.stringify({ type: "error", message: "Client not found" }));
}

/**
 * Broadcast session list to all connected clients
 */
function broadcastSessionList() {
  const message = JSON.stringify({ type: "sessions", list: getSessionList() });

  for (const client of wss.clients) {
    if (client.readyState === 1) {
      // WebSocket.OPEN
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
      if (iface.family === "IPv4" && !iface.internal) {
        return iface.address;
      }
    }
  }
  return "localhost";
}

// Start server
server.listen(PORT, HOST, () => {
  const localIP = getLocalIP();
  const protocol = tlsOptions ? "https" : "http";
  const wsProtocol = tlsOptions ? "wss" : "ws";

  console.log(`Web Terminal Server running at ${protocol}://${HOST}:${PORT}`);
  console.log(`Access from LAN: ${protocol}://${localIP}:${PORT}`);
  if (tlsOptions) {
    console.log(`TLS: ENABLED (self-signed certificate)`);
  } else {
    console.log(
      `TLS: DISABLED (run 'node server/generate-certs.js' to enable)`,
    );
  }
  if (PASSWORD) {
    console.log(`Authentication: ENABLED (password required)`);
  } else {
    console.log(`Authentication: DISABLED (open access)`);
  }
  console.log("");

  // Publish mDNS service for discovery
  bonjourService = bonjour.publish({
    name: SERVICE_NAME,
    type: "http",
    port: parseInt(PORT, 10),
    txt: {
      path: "/",
      protocol: wsProtocol,
      tls: tlsOptions ? "true" : "false",
      auth: PASSWORD ? "required" : "none",
    },
  });

  console.log(`Bonjour: Published as "${SERVICE_NAME}" (_http._tcp)`);
  console.log("         Discoverable on local network");
  console.log("");
  console.log("Press Ctrl+C to stop the server");
});

// Graceful shutdown
process.on("SIGINT", () => {
  console.log("\nShutting down...");

  // Stop heartbeat
  clearInterval(heartbeatInterval);

  // Unpublish Bonjour service
  if (bonjourService) {
    bonjourService.stop();
  }
  bonjour.destroy();

  // Kill all sessions
  for (const name of sessionManager.list()) {
    try {
      sessionManager.kill(name);
    } catch {
      // Ignore errors during shutdown
    }
  }

  // Close WebSocket server
  wss.close(() => {
    // Close HTTP server
    server.close(() => {
      console.log("Server stopped");
      process.exit(0);
    });
  });
});
