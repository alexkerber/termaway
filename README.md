# TermAway

**Your Mac terminal, on your iPad.**

TermAway is a self-hosted terminal for iPhone, iPad and the browser. A menu bar app on your Mac runs a small Node server; a native SwiftTerm client connects over your Wi-Fi or through Tailscale. No cloud, no account, no tracking — your terminal never leaves your network.

[Download on the App Store](https://apps.apple.com/app/termaway/id6757634428) · [Download for Mac](https://github.com/alexkerber/termaway/releases/latest) · [termaway.app](https://termaway.app)

## Features

- **Nothing in the middle.** Your Mac talks to your iPad directly, over your own network or your own tailnet.
- **Named sessions that stay put.** Create "backend", "frontend", "agent" and reattach from any device. Turn on tmux persistence and they survive a server restart or a reboot.
- **Built for agents.** A session that rings the terminal bell — or posts to the local notify hook — raises a notification, and tapping it opens that session.
- **Real terminal.** Your `$SHELL` with your dotfiles, 24-bit colour, and everything interactive: vim, htop, less, Claude Code, Codex.
- **Made for touch.** A prompt composer with per-session drafts, an accessory bar with Tab, arrows, Esc and Ctrl chords, split panes on iPad, and tappable links to dev servers you start in a session.
- **Several screens at once.** iPhone, iPad and a browser can watch the same session live.

## Quick start

```bash
bun install
node server/index.js
```

Then open <http://localhost:3000>, or point the iOS app at your machine — it finds the server on your network by itself.

> node-pty ships native bindings, so the server needs the Node runtime. Bun is only used to install.

Most people never run this by hand: the [macOS app](https://github.com/alexkerber/termaway/releases/latest) bundles the server and runs it from the menu bar.

## Apps

|                  |                                                    |
| ---------------- | -------------------------------------------------- |
| **iOS / iPadOS** | Native SwiftTerm client — `apps/ios/`              |
| **macOS**        | Menu bar app that hosts the server — `apps/macos/` |
| **Web**          | Browser client, xterm.js — `apps/web/`             |
| **Linux**        | Server only, via the release tarball — `server/`   |

## Configuration

| Variable            | Default                      | Description                                                               |
| ------------------- | ---------------------------- | ------------------------------------------------------------------------- |
| `PORT`              | `3000`                       | HTTP server port. Also `--port`.                                          |
| `HOST`              | `0.0.0.0`                    | Bind address.                                                             |
| `TERMAWAY_PASSWORD` | —                            | Require this password before a client can do anything. Also `--password`. |
| `SERVICE_NAME`      | `TermAway (<computer name>)` | How the server advertises itself over Bonjour.                            |
| `TERMAWAY_TMUX`     | off                          | Set to `1` to run sessions inside tmux so they survive a server restart.  |
| `TERMAWAY_TMUX_BIN` | —                            | Path to tmux, if it isn't in a standard location.                         |
| `TERMAWAY_DEBUG`    | off                          | Set to `1` for per-message logging.                                       |

## Security

- **Local by default.** The server binds to your network and never phones home. There is no TermAway-hosted cloud or relay.
- **Password auth.** Set `TERMAWAY_PASSWORD` (or `--password`). Attempts are rate-limited and compared in constant time.
- **TLS.** Run `node server/generate-certs.js` to create a self-signed pair in `~/.termaway/certs`; the server then serves HTTPS and WSS.
- **Reaching it from outside.** Use [Tailscale](https://tailscale.com) or another VPN, and set a password. Don't port-forward TermAway to the open internet.

## Architecture

```
├── apps/
│   ├── ios/                  # Native iOS/iPadOS client (SwiftUI + SwiftTerm)
│   ├── macos/                # Menu bar server app (AppKit)
│   └── web/                  # Web terminal client (xterm.js)
├── server/
│   ├── index.js              # Express + WebSocket server
│   └── sessionManager.js     # PTY session lifecycle
├── website/                  # Marketing website (termaway.app)
└── builds/                   # Release artifacts (.dmg, .tar.gz)
```

A session is a [node-pty](https://github.com/microsoft/node-pty) process running your login shell. The server keeps a scrollback buffer per session and fans output out to every attached client, so several devices can watch the same terminal. With `TERMAWAY_TMUX=1` the PTY runs a tmux _client_ instead, and the shell belongs to the tmux server — which is what lets sessions outlive the TermAway process.

### WebSocket protocol

Client → server:

| Message                                            | Purpose                              |
| -------------------------------------------------- | ------------------------------------ |
| `auth`                                             | Authenticate, when a password is set |
| `create` / `attach` / `detach` / `kill` / `rename` | Session lifecycle                    |
| `input` / `resize`                                 | Terminal I/O                         |
| `list`                                             | Ask for the session list             |
| `clipboard-set` / `clipboard-get`                  | Clipboard sync                       |

Server → client:

| Message                                                  | Purpose                                        |
| -------------------------------------------------------- | ---------------------------------------------- |
| `output`                                                 | Terminal data                                  |
| `sessions`                                               | Session list, broadcast on any change          |
| `created` / `attached` / `killed` / `renamed` / `exited` | Lifecycle confirmations                        |
| `auth-required` / `auth-success` / `auth-failed`         | Authentication                                 |
| `attention`                                              | A session wants the user (bell or notify hook) |
| `client-connected` / `client-disconnected`               | Someone else attached                          |
| `clipboard-update` / `clipboard-content`                 | Clipboard sync                                 |
| `error`                                                  | Something went wrong                           |

## Development

```bash
node --watch server/index.js   # server with auto-reload
npm test                       # server self-checks
```

Building the apps and cutting a release is documented in [CLAUDE.md](CLAUDE.md).

## Tech stack

- **Server** — Node.js, Express, ws, node-pty
- **Web client** — vanilla JS, xterm.js
- **iOS client** — Swift, SwiftUI, SwiftTerm
- **macOS app** — Swift, AppKit
- **Website** — Astro

## Troubleshooting

**Colours look wrong.** Your shell should see `TERM=xterm-256color`; check that your `.zshrc`/`.bashrc` doesn't override it.

**A session disappeared after restarting the server.** That's the default — sessions are tied to the server process. Turn on tmux persistence to keep them.

**The iOS app can't find the server.** Discovery uses Bonjour, which needs both devices on the same network. Over Tailscale, type the tailnet address by hand.

**The web terminal renders oddly.** It uses WebGL; try another browser or reload.

## License

MIT
