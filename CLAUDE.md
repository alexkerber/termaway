# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Commands

```bash
bun install     # Install dependencies
bun start       # Start the server (http://localhost:3000)
bun run dev     # Start with auto-reload on file changes
```

## Architecture

This is a web-based terminal application that provides remote terminal access over WebSocket. It uses node-pty for pseudo-terminal emulation and xterm.js for browser rendering.

### Server (Node.js)

- **server/index.js**: Express HTTP server + WebSocket server. Handles client connections, routes WebSocket messages to session manager, and serves static files. Maps each WebSocket connection to a session via `wsSessionMap`.

- **server/sessionManager.js**: Manages PTY sessions. Each session has:
  - A node-pty process spawned with user's default shell (`$SHELL -l`)
  - A scrollback buffer for reconnecting clients
  - A set of attached WebSocket clients
  - Sessions persist until explicitly killed or the shell exits

### Client (Vanilla JS)

- **client/terminal.js**: xterm.js terminal with WebGL rendering, auto-reconnect with exponential backoff, and tab-based session UI. Communicates via JSON messages over WebSocket.

### WebSocket Protocol

Client → Server:
- `create` / `attach` / `detach` / `kill` / `rename` - session lifecycle
- `input` / `resize` - terminal I/O
- `list` - get all sessions

Server → Client:
- `output` - terminal data
- `sessions` - session list updates (broadcast to all clients)
- `attached` / `created` / `killed` / `renamed` / `exited` - confirmations
- `error` - error messages
