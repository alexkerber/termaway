# Web Terminal

A self-hosted web-based terminal that provides access to your machine's terminal sessions from any browser on your LAN. Perfect for remote coding from bed, TV, or anywhere in your home.

## Features

- **Named Persistent Sessions**: Create sessions like "backend", "frontend", "flutter" and reconnect to them anytime
- **Full Terminal Emulation**: 256 color and true color (24-bit) support via xterm.js
- **Your Shell, Your Config**: Uses your default shell ($SHELL) with all your dotfiles (.zshrc, aliases, PATH, colors)
- **Interactive CLI Support**: Works with vim, nano, htop, top, less, man pages, and claude
- **Session Persistence**: Sessions survive browser disconnect - reconnect picks up exactly where you left off
- **Responsive Design**: Works on TV (fullscreen), tablet, and phone
- **GPU Accelerated**: WebGL rendering for smooth performance
- **Clickable URLs**: URLs in terminal output are clickable
- **Auto-Reconnect**: Automatic reconnection with exponential backoff

## Quick Start

```bash
cd web-terminal
npm install
npm start
```

Then open http://localhost:3000 in your browser.

For LAN access, use your machine's IP address or hostname:
- http://192.168.x.x:3000
- http://your-machine.local:3000

## Configuration

Environment variables:

| Variable | Default | Description |
|----------|---------|-------------|
| `PORT` | 3000 | HTTP server port |
| `HOST` | 0.0.0.0 | Bind address (0.0.0.0 for all interfaces) |

## Usage

### Creating Sessions

1. Click the **+** button in the tab bar
2. Enter a name for your session (e.g., "backend", "frontend")
3. The session starts with your default shell

### Managing Sessions

- **Switch Sessions**: Click on a tab to switch
- **Kill Session**: Click the × on a tab, or right-click → Kill Session
- **Rename Session**: Right-click on a tab → Rename Session

### Keyboard Shortcuts

Terminal shortcuts work as expected:
- `Ctrl+C` - Interrupt
- `Ctrl+D` - EOF
- `Ctrl+Z` - Suspend
- `Tab` - Completion

Copy/Paste:
- `Ctrl+Shift+C` / `Ctrl+Shift+V` (Linux)
- `Cmd+C` / `Cmd+V` (Mac)

## Architecture

```
web-terminal/
├── server/
│   ├── index.js              # Express + WebSocket server
│   └── sessionManager.js     # PTY session lifecycle
├── client/
│   ├── index.html            # Main page
│   ├── terminal.js           # xterm.js + WebSocket client
│   └── styles.css            # Dark theme
├── package.json
└── README.md
```

### WebSocket Protocol

Client → Server:
- `{ type: "create", name: "session-name" }` - Create new session
- `{ type: "attach", name: "session-name" }` - Attach to session
- `{ type: "input", data: "..." }` - Terminal input
- `{ type: "resize", cols: 80, rows: 24 }` - Resize terminal
- `{ type: "kill", name: "session-name" }` - Kill session
- `{ type: "list" }` - List all sessions

Server → Client:
- `{ type: "output", data: "..." }` - Terminal output
- `{ type: "sessions", list: [...] }` - Session list
- `{ type: "attached", name: "..." }` - Confirm attachment
- `{ type: "created", name: "..." }` - Confirm creation
- `{ type: "killed", name: "..." }` - Confirm kill
- `{ type: "error", message: "..." }` - Error message

## Tech Stack

- **Backend**: Node.js, Express, ws, node-pty
- **Frontend**: Vanilla JS, xterm.js, xterm addons (fit, webgl, web-links)

## Security Notes

This is designed for LAN-only access without authentication. For external access:
- Add authentication
- Enable HTTPS
- Consider using a VPN

## Troubleshooting

### Terminal not displaying correctly
- Ensure your browser supports WebGL
- Try refreshing the page

### Session not reconnecting
- Check server is still running
- Check network connectivity
- Sessions are lost if server restarts

### Colors not working
- Your shell should detect TERM=xterm-256color
- Make sure your .zshrc/.bashrc doesn't override TERM

## License

MIT
