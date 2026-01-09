# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project: TermAway

TermAway is a self-hosted terminal access solution. Your Mac terminal, on your iPad.

## Commands

```bash
bun install            # Install dependencies (fast)
node server/index.js   # Start the server (http://localhost:3000)
node --watch server/index.js  # Start with auto-reload
```

Note: node-pty requires Node.js runtime (not bun) due to native bindings.

## Architecture

This is a web-based terminal application that provides remote terminal access over WebSocket. It uses node-pty for pseudo-terminal emulation and xterm.js for browser rendering.

### Server (Node.js)

- **server/index.js**: Express HTTP server + WebSocket server. Handles client connections, routes WebSocket messages to session manager, and serves static files. Maps each WebSocket connection to a session via `wsSessionMap`.

- **server/sessionManager.js**: Manages PTY sessions. Each session has:
  - A node-pty process spawned with user's default shell (`$SHELL -l`)
  - A scrollback buffer for reconnecting clients
  - A set of attached WebSocket clients
  - Sessions persist until explicitly killed or the shell exits

### iOS App (SwiftUI + SwiftTerm)

- **ios-app/**: Native iOS/iPadOS client using SwiftTerm for terminal emulation
- Connects via WebSocket to the server
- Bonjour discovery for finding servers on LAN

### macOS App (AppKit)

- **macos-app/**: Menu bar app that runs the terminal server
- Manages server lifecycle (start/stop)
- Shows connection URL

### Website

- **website/**: Marketing site at termaway.app

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
