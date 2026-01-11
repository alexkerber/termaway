# Split Terminal Feature

## Overview

Allow users to view two terminal sessions side by side on iPad and web (where screen space permits). This feature enables multitasking workflows like monitoring logs while running commands, or comparing outputs.

## Platforms

- **iPad**: Landscape mode, tablets with sufficient width
- **Web**: Browser windows > 1024px wide
- **iPhone**: Not supported (screen too narrow)

## User Experience

### Activation

1. Long-press on a session in the list → "Open in Split View"
2. Drag a session to the side of an existing terminal
3. Menu/toolbar button to split current view

### Deactivation

1. Tap X on one of the split panes
2. Drag divider all the way to one side
3. Double-tap divider to collapse

### Behavior

- Each pane operates independently
- Can show same session in both panes (useful for scrollback review)
- Divider is draggable to resize (50/50 default)
- Keyboard input goes to focused pane (visual indicator)

---

## Implementation Plan

### Phase 1: Data Model

**New State Management**

```swift
// iOS: New SplitTerminalState
enum PanePosition {
    case left
    case right
    case single
}

struct TerminalPane: Identifiable {
    let id: UUID
    var sessionName: String?
    var position: PanePosition
}

class SplitTerminalManager: ObservableObject {
    @Published var panes: [TerminalPane] = []
    @Published var focusedPaneId: UUID?
    @Published var splitRatio: CGFloat = 0.5
    @Published var isSplitActive: Bool = false

    func splitView(with sessionName: String)
    func closeSplitView()
    func setFocusedPane(_ id: UUID)
}
```

```javascript
// Web: Split state in app.js
const splitState = {
  enabled: false,
  leftSession: null,
  rightSession: null,
  focusedPane: "left", // 'left' | 'right'
  splitRatio: 0.5,
};
```

### Phase 2: iOS Implementation

**Files to Modify:**

- `ContentView.swift` - Add split view container
- `TerminalContainerView.swift` - Support multiple instances
- `ConnectionManager.swift` - Track which pane receives input

**New Files:**

- `SplitTerminalManager.swift` - State management
- `SplitTerminalView.swift` - Split container UI
- `TerminalPaneView.swift` - Individual pane wrapper

**UI Structure:**

```
SplitTerminalView
├── TerminalPaneView (left)
│   ├── TerminalContainerView
│   └── Focus indicator border
├── DividerView (draggable)
└── TerminalPaneView (right)
    ├── TerminalContainerView
    └── Focus indicator border
```

**Key Implementation Details:**

```swift
struct SplitTerminalView: View {
    @StateObject var splitManager = SplitTerminalManager()
    @EnvironmentObject var connectionManager: ConnectionManager

    var body: some View {
        GeometryReader { geometry in
            if splitManager.isSplitActive {
                HStack(spacing: 0) {
                    // Left pane
                    TerminalPaneView(
                        pane: splitManager.panes[0],
                        isFocused: splitManager.focusedPaneId == splitManager.panes[0].id
                    )
                    .frame(width: geometry.size.width * splitManager.splitRatio)
                    .onTapGesture {
                        splitManager.setFocusedPane(splitManager.panes[0].id)
                    }

                    // Divider
                    SplitDividerView(splitRatio: $splitManager.splitRatio)

                    // Right pane
                    TerminalPaneView(
                        pane: splitManager.panes[1],
                        isFocused: splitManager.focusedPaneId == splitManager.panes[1].id
                    )
                    .onTapGesture {
                        splitManager.setFocusedPane(splitManager.panes[1].id)
                    }
                }
            } else {
                // Single pane mode (current behavior)
                TerminalContainerView()
            }
        }
    }
}

struct SplitDividerView: View {
    @Binding var splitRatio: CGFloat
    @State private var isDragging = false

    var body: some View {
        Rectangle()
            .fill(Color.gray.opacity(0.3))
            .frame(width: isDragging ? 8 : 4)
            .gesture(
                DragGesture()
                    .onChanged { value in
                        isDragging = true
                        // Update splitRatio based on drag
                    }
                    .onEnded { _ in
                        isDragging = false
                    }
            )
            .onHover { hovering in
                // Change cursor on macOS Catalyst
            }
    }
}
```

**Focus Handling:**

- Tapping a pane sets it as focused
- Focused pane has subtle border highlight (brand color)
- All keyboard input routes to focused pane's session
- External keyboard support maintained

### Phase 3: Web Implementation

**Files to Modify:**

- `apps/web/index.html` - Add split container structure
- `apps/web/styles.css` - Split view styles
- `apps/web/app.js` - Split state and terminal management

**HTML Structure:**

```html
<div id="terminal-container">
  <div id="split-container" class="split-view">
    <div id="pane-left" class="terminal-pane">
      <div class="pane-header">
        <span class="session-name">Session 1</span>
        <button class="close-split">×</button>
      </div>
      <div id="terminal-left" class="terminal"></div>
    </div>
    <div id="split-divider" class="divider"></div>
    <div id="pane-right" class="terminal-pane">
      <div class="pane-header">
        <span class="session-name">Session 2</span>
        <button class="close-split">×</button>
      </div>
      <div id="terminal-right" class="terminal"></div>
    </div>
  </div>
</div>
```

**CSS:**

```css
.split-view {
  display: flex;
  height: 100%;
}

.terminal-pane {
  display: flex;
  flex-direction: column;
  min-width: 200px;
}

.terminal-pane.focused {
  outline: 2px solid var(--brand-orange);
  outline-offset: -2px;
}

.pane-header {
  display: flex;
  justify-content: space-between;
  align-items: center;
  padding: 4px 8px;
  background: var(--header-bg);
  border-bottom: 1px solid var(--border-color);
}

.divider {
  width: 4px;
  background: var(--divider-color);
  cursor: col-resize;
  transition:
    width 0.1s,
    background 0.1s;
}

.divider:hover,
.divider.dragging {
  width: 8px;
  background: var(--brand-orange);
}

/* Hide split on narrow screens */
@media (max-width: 768px) {
  .split-controls {
    display: none;
  }
}
```

**JavaScript:**

```javascript
class SplitTerminalManager {
  constructor() {
    this.leftTerminal = null;
    this.rightTerminal = null;
    this.leftSession = null;
    this.rightSession = null;
    this.focusedPane = "left";
    this.splitRatio = 0.5;
    this.isSplitActive = false;
  }

  enableSplit(rightSessionName) {
    if (this.isSplitActive) return;

    // Create right terminal
    this.rightTerminal = new Terminal(terminalOptions);
    this.rightTerminal.open(document.getElementById("terminal-right"));

    // Attach to session
    this.rightSession = rightSessionName;
    this.attachToSession("right", rightSessionName);

    this.isSplitActive = true;
    document.body.classList.add("split-active");

    this.setupDividerDrag();
    this.updateLayout();
  }

  disableSplit() {
    if (!this.isSplitActive) return;

    // Dispose right terminal
    this.rightTerminal.dispose();
    this.rightTerminal = null;
    this.rightSession = null;

    this.isSplitActive = false;
    document.body.classList.remove("split-active");

    this.updateLayout();
  }

  setFocus(pane) {
    this.focusedPane = pane;
    document.querySelectorAll(".terminal-pane").forEach((el) => {
      el.classList.remove("focused");
    });
    document.getElementById(`pane-${pane}`).classList.add("focused");

    // Focus the terminal
    const term = pane === "left" ? this.leftTerminal : this.rightTerminal;
    term?.focus();
  }

  handleInput(data) {
    // Route input to focused pane's session
    const session =
      this.focusedPane === "left" ? this.leftSession : this.rightSession;

    if (session) {
      ws.send(JSON.stringify({ type: "input", data, session }));
    }
  }

  setupDividerDrag() {
    const divider = document.getElementById("split-divider");
    let isDragging = false;

    divider.addEventListener("mousedown", (e) => {
      isDragging = true;
      divider.classList.add("dragging");
    });

    document.addEventListener("mousemove", (e) => {
      if (!isDragging) return;

      const container = document.getElementById("split-container");
      const rect = container.getBoundingClientRect();
      this.splitRatio = Math.max(
        0.2,
        Math.min(0.8, (e.clientX - rect.left) / rect.width),
      );
      this.updateLayout();
    });

    document.addEventListener("mouseup", () => {
      isDragging = false;
      divider.classList.remove("dragging");
    });
  }

  updateLayout() {
    const leftPane = document.getElementById("pane-left");
    const rightPane = document.getElementById("pane-right");

    if (this.isSplitActive) {
      leftPane.style.width = `${this.splitRatio * 100}%`;
      rightPane.style.width = `${(1 - this.splitRatio) * 100}%`;
      rightPane.style.display = "flex";
    } else {
      leftPane.style.width = "100%";
      rightPane.style.display = "none";
    }

    // Trigger terminal resize
    this.leftTerminal?.fit();
    this.rightTerminal?.fit();
  }
}
```

### Phase 4: Server Changes

**Minimal changes needed** - the server already supports multiple sessions and clients.

**Potential Enhancement:**

- Add message routing for split view input (optional, can use existing session targeting)

```javascript
// In handleInput - already supports session targeting
function handleInput(ws, data, targetSession) {
  const sessionName = targetSession || wsSessionMap.get(ws);
  if (!sessionName) return;
  sessionManager.write(sessionName, data);
}
```

---

## UI/UX Details

### Visual Indicators

**Focused Pane:**

- 2px border in brand orange
- Slightly elevated shadow (subtle)
- Session name bold in header

**Unfocused Pane:**

- No border highlight
- Dimmed header (opacity 0.7)

**Divider:**

- Default: 4px, gray
- Hover: 8px, brand orange
- Dragging: 8px, brand orange, cursor: col-resize

### Keyboard Shortcuts (Web)

| Shortcut       | Action                        |
| -------------- | ----------------------------- |
| `Cmd/Ctrl + \` | Toggle split view             |
| `Cmd/Ctrl + 1` | Focus left pane               |
| `Cmd/Ctrl + 2` | Focus right pane              |
| `Cmd/Ctrl + W` | Close focused pane (if split) |

### Context Menu (iPad)

Long-press on session in sidebar:

- "Open" (default)
- "Open in Split View" (when not split)
- "Replace Left Pane" (when split)
- "Replace Right Pane" (when split)

---

## Edge Cases

1. **Session ends in one pane**: Keep pane open with "Session ended" message, option to select new session
2. **Same session in both panes**: Allowed - useful for scrollback review
3. **Resize below minimum**: Snap to 20% minimum width per pane
4. **Orientation change (iPad)**: Collapse to single pane in portrait, restore split in landscape
5. **Disconnect**: Both panes show reconnecting state independently

---

## Testing Plan

1. **Split activation**: Long-press → Open in Split View
2. **Focus switching**: Tap between panes, keyboard input routes correctly
3. **Divider drag**: Resize works, minimum widths respected
4. **Split close**: X button, drag to edge, double-tap divider
5. **Session independence**: Commands in one pane don't affect other
6. **Same session**: Both panes update with same output
7. **Orientation**: Portrait collapses, landscape restores
8. **Keyboard shortcuts**: Web shortcuts work correctly
9. **Performance**: No lag with two terminals rendering

---

## Estimated Complexity

| Component          | Effort |
| ------------------ | ------ |
| Data model & state | Low    |
| iOS split view UI  | Medium |
| iOS focus handling | Medium |
| Web split view UI  | Medium |
| Web divider drag   | Low    |
| Keyboard shortcuts | Low    |
| Context menus      | Low    |
| Edge cases         | Medium |
| Testing            | Medium |

**Total: Medium-High complexity**

---

## Future Enhancements

- Vertical split option (top/bottom)
- More than 2 panes (grid layout)
- Save split configuration per device
- Drag sessions between panes
- Tab groups within panes
