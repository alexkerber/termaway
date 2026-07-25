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

## Project Structure

```
termaway/
├── apps/
│   ├── ios/          # iOS/iPadOS app (SwiftUI + SwiftTerm)
│   ├── macos/        # macOS menu bar app (AppKit)
│   └── web/          # Web terminal client (xterm.js)
├── server/           # Node.js WebSocket server
├── website/          # Marketing site (Astro, termaway.app)
│   ├── src/
│   │   ├── components/   # Header, Footer
│   │   ├── layouts/      # Base layout
│   │   ├── pages/        # index, policy
│   │   └── styles/       # Global CSS
│   └── public/assets/    # Images, icons
└── builds/           # Release artifacts (.dmg, .tar.gz)
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

#### tmux persistence (opt-in)

With `TERMAWAY_TMUX=1` (the macOS app's "Keep sessions running when the server
stops" preference), a session's PTY runs a tmux _client_ instead of the login
shell, so the shell belongs to the tmux server and outlives this process.
`adoptTmuxSessions()` reattaches to everything still running at startup.

Four things have to stay true, and each has a case in
`server/sessionManager.tmux.test.js`:

- **Shutdown must not kill tmux sessions.** `shutdown()` walks every session
  through `kill()`; the `shuttingDown` flag makes it disconnect the client and
  leave the session running. Getting this wrong silently defeats the feature.
  It also has to stay quiet — iOS discards the composer draft on both `killed`
  and `exited`, so announcing either would lose work for a live session.
- **An explicit kill must end the tmux session**, or it returns on next start.
- **Rename must rename the tmux session**, or the old name returns.
- **A PTY exit is not a dead session.** `tmux detach` and a killed client look
  identical to a shell exiting; `_reattach()` checks `has-session` and spawns a
  new client instead of reporting the session gone.

The session is created detached and synchronously; adoption is attach-only; and
tmux commands that change state throw rather than return null, so nothing is
mutated before tmux agrees. The reasons are on those lines in the code.

#### Agents talking to each other

A side effect worth knowing: because each named session *is* a tmux session on a
shared private socket, tmux sets `$TMUX` inside it, so plain tmux commands reach
the right server with no socket flag and no TermAway API:

```bash
tmux list-sessions -F '#{session_name}'          # who else is running
tmux display -p '#{session_name}'                # who am I
tmux capture-pane -p -t '=codex:' | tail -30     # read their screen
tmux send-keys -t '=codex:' 'your message' Enter # write to them
```

`=name:` is an exact match, so `claude` won't also hit `claude-2`. This only
works between *named* sessions — split panes are ephemeral and deliberately not
tmux-backed, so they are not on the socket and can't be addressed.

Two details that are easy to get wrong: tmux accepts a `.` in a session name but
reads it as a window separator in a target, so names are percent-encoded
(`app.web` → `app%2Eweb`); and in tmux mode the port scanner has to root at the
panes' PIDs, because the shell is a child of the tmux server rather than of the
client PTY. Ephemeral split panes stay plain shells. TermAway's own replay buffer
is in memory and still resets — what survives is the processes and tmux history.

### iOS App (SwiftUI + SwiftTerm)

- **apps/ios/**: Native iOS/iPadOS client using SwiftTerm for terminal emulation
- Connects via WebSocket to the server
- Bonjour discovery for finding servers on LAN

### macOS App (AppKit)

- **apps/macos/**: Menu bar app that runs the terminal server
- Manages server lifecycle (start/stop)
- Shows connection URL

### Web Client

- **apps/web/**: Browser-based terminal client using xterm.js
- PWA support for home screen installation

### Website

- **website/**: Marketing site at termaway.app, built with Astro
- Shared components: Header, Footer, Layout
- Auto-deploys via Vercel on push to main

### WebSocket Protocol

Client → Server:

- `create` / `attach` / `detach` / `kill` / `rename` - session lifecycle
- `input` / `resize` - terminal I/O
- `list` - get all sessions
- `auth` - authentication
- `clipboard-set` / `clipboard-get` - clipboard sync

Server → Client:

- `output` - terminal data
- `sessions` - session list updates (broadcast to all clients)
- `attached` / `created` / `killed` / `renamed` / `exited` - confirmations
- `auth-required` / `auth-success` / `auth-failed` - authentication
- `client-connected` / `client-disconnected` - connection notifications
- `clipboard-update` / `clipboard-content` - clipboard sync
- `error` - error messages

## iOS Development

### Build Commands

```bash
# Build for iPhone simulator
xcodebuild -project apps/ios/TermAway.xcodeproj -scheme TermAway \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro,OS=18.6' build

# Build for iPad simulator
xcodebuild -project apps/ios/TermAway.xcodeproj -scheme TermAway \
  -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M4),OS=18.6' build
```

### Reusable Components

**Always check for existing components before creating new ones:**

- `GlassCircleButton` - Circle button with liquid glass effect (iOS 26) or ultraThinMaterial fallback. Use for floating action buttons, icon buttons in overlays. Has built-in haptic feedback.
- `GlassPillButton` - Pill-shaped glass button for status indicators
- `ConnectionStatusLabel` - Green dot + connected/disconnected text (wrap in a Button for a tap action)

Located in: `apps/ios/TermAway/Views/GlassComponents.swift`

### SwiftUI Patterns

- **Swipe Actions**: Use `.swipeActions` with `Image(systemName:)` only (no Label) for icon-only buttons. Shape is system-controlled.
- **Delete Confirmation**: Always show confirmation alert before destructive actions
- **iPad vs iPhone**: Check `UIDevice.current.userInterfaceIdiom == .pad` for device-specific layouts
- **Toolbar on iPad**: Use `.toolbar` with `.topBarTrailing` placement - aligns with NavigationSplitView sidebar toggle
- **Safe Area**: iPhone overlays should respect safe area (Dynamic Island). iPad can ignore top safe area to align with system nav bar.

## Releasing

When creating a new release:

1. **Bump the version, then commit and push to main before tagging** (`gh release create`
   tags the remote HEAD, so an unpushed bump ships the previous commit):
   - `apps/macos/TermAway/Info.plist` - CFBundleShortVersionString and CFBundleVersion
   - `apps/ios/TermAway.xcodeproj/project.pbxproj` - MARKETING_VERSION and CURRENT_PROJECT_VERSION
     (both appear twice, Debug and Release; bump in the Xcode target settings to hit both)
   - `package.json` - version (it silently drifted three releases behind before this
     line existed)

   Only the marketing versions need to match across the apps
   (CFBundleShortVersionString ↔ MARKETING_VERSION). Build numbers are independent and
   only have to increase — macOS reuses the marketing version, iOS counts 1, 2, 3.

2. **Build and upload the iOS app:**

   ```bash
   apps/ios/release.sh                                          # archive + export IPA
   apps/ios/release.sh --upload --api-key <KEY_ID> --api-issuer <ISSUER_ID>
   ```

   Without `--upload`, finish in Xcode: Organizer → Distribute App → App Store Connect.
   Either way, select the build in App Store Connect and submit it for review.

3. **Build the macOS app — use the script, do not hand-roll it:**

   ```bash
   apps/macos/release.sh              # --no-notarize for a test build
   ```

   It reads the version from Info.plist, archives with Developer ID, bundles the Node
   server + web client + production deps inside the app, signs every Mach-O (node-pty
   ships `pty.node` and `spawn-helper`), notarizes, staples, and writes
   `builds/TermAway-macOS-v{version}.dmg`.

   Ship the DMG, never a zip. Extraction tools can break the signature of a zipped
   `.app`, and a hand-built zip omits the bundled server — if the artifact is under a
   megabyte, the server is missing and the app is broken.

4. **Build Linux server package:**

   ```bash
   # Create tarball from repo root
   mkdir -p /tmp/termaway-linux/apps
   cp -r server /tmp/termaway-linux/
   cp -r apps/web /tmp/termaway-linux/apps/web
   cp package.json /tmp/termaway-linux/
   cp server/install-linux.sh /tmp/termaway-linux/install.sh
   cp server/uninstall-linux.sh /tmp/termaway-linux/uninstall.sh
   cd /tmp && tar czf TermAway-Linux-v{version}.tar.gz termaway-linux
   mv TermAway-Linux-v{version}.tar.gz /path/to/termaway/builds/
   rm -rf /tmp/termaway-linux
   ```

5. **Publish the GitHub release:**

   ```bash
   gh release create v{version} --draft \
     builds/TermAway-macOS-v{version}.dmg \
     builds/TermAway-Linux-v{version}.tar.gz

   gh release edit v{version} --draft=false   # once the App Store build is live
   ```

   Keep it a draft until the iOS version is actually live — approved is not enough if
   the release is manual — so the Mac and Linux downloads never run ahead of the App
   Store. The website's download buttons resolve from the latest _published_ release
   and match assets by name, `assets.find(a => a.name.includes('macOS'))`, so there
   must be exactly one macOS asset and one Linux asset or a leftover can win over the
   DMG.

### Notarization Setup (one-time)

If the keychain profile is missing, set it up:

```bash
xcrun notarytool store-credentials "notarytool" \
  --apple-id "alex@alexkerber.com" \
  --team-id "3KFU9JQ5LH"
```

Enter an app-specific password from appleid.apple.com → Security → App-Specific Passwords.
