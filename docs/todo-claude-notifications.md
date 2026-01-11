# Claude Code Task Completion Notifications

## Goal

Send notifications to iOS app (and Apple Watch) when Claude Code completes a task.

## Implementation Options

### Option A: WebSocket Command (Recommended)

Add a new message type to TermAway server that triggers notifications.

**Server changes (`server/index.js`):**

- Add `notify` message type handler
- Broadcast notification to all connected iOS clients

**iOS changes:**

- Handle `notify` message type
- Show local notification with custom title/body

**Claude Code hook:**

```json
{
  "hooks": {
    "Stop": [
      {
        "command": "node -e \"const ws = new (require('ws'))('ws://localhost:3000'); ws.on('open', () => { ws.send(JSON.stringify({type:'notify',title:'Claude Done',body:'Task completed'})); ws.close(); });\""
      }
    ]
  }
}
```

### Option B: HTTP Endpoint

Add REST endpoint to server for simpler curl-based notifications.

**Server changes:**

- Add `POST /notify` endpoint
- Forward to WebSocket clients

**Claude Code hook:**

```json
{
  "hooks": {
    "Stop": [
      {
        "command": "curl -s -X POST http://localhost:3000/notify -H 'Content-Type: application/json' -d '{\"title\":\"Claude Done\",\"body\":\"Task completed\"}'"
      }
    ]
  }
}
```

## Tasks

- [ ] Add `notify` message type to server
- [ ] Add HTTP endpoint as alternative trigger
- [ ] Handle `notify` in iOS ConnectionManager
- [ ] Show notification with customizable title/body
- [ ] Test with Claude Code hook
- [ ] Document hook setup in README

## Hook Events Available

- `PreToolUse` - Before a tool runs
- `PostToolUse` - After a tool completes
- `Stop` - When Claude stops responding (good for "task done")
- `Notification` - When Claude sends a notification
