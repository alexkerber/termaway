// xterm.js and addons are loaded via script tags as globals
const { Terminal } = window;
const { FitAddon } = window.FitAddon;
const { WebglAddon } = window.WebglAddon;
const { WebLinksAddon } = window.WebLinksAddon;

// State
let ws = null;
let term = null;
let fitAddon = null;
let webglAddon = null;
let currentSession = null;
let sessions = [];
let reconnectAttempts = 0;
let reconnectTimer = null;
let contextMenuTarget = null;
let isAuthenticated = false;
let authRequired = false;

// Configuration
const MAX_RECONNECT_ATTEMPTS = 10;
const RECONNECT_BASE_DELAY = 1000;
const SCROLLBACK_LINES = 10000;
const DEFAULT_FONT_SIZE = 14;
const MIN_FONT_SIZE = 10;
const MAX_FONT_SIZE = 24;

// Settings state
let currentFontSize =
  parseInt(localStorage.getItem("fontSize")) || DEFAULT_FONT_SIZE;
let currentTheme = localStorage.getItem("theme") || "dark";
let activeModifiers = { ctrl: false, alt: false };
let quickCommands = JSON.parse(localStorage.getItem("quickCommands")) || [
  "ls -la",
  "git status",
  "git diff",
  "npm run dev",
];

// DOM Elements
const terminalContainer = document.getElementById("terminal");
const noSessionView = document.getElementById("no-session");
const tabsContainer = document.getElementById("tabs");
const newSessionBtn = document.getElementById("new-session-btn");
const createFirstSessionBtn = document.getElementById("create-first-session");
const connectionStatus = document.getElementById("connection-status");
const statusText = connectionStatus.querySelector(".status-text");
const modalOverlay = document.getElementById("modal-overlay");
const modalTitle = document.getElementById("modal-title");
const modalInput = document.getElementById("modal-input");
const modalCancel = document.getElementById("modal-cancel");
const modalConfirm = document.getElementById("modal-confirm");
const contextMenu = document.getElementById("context-menu");
const scrollToBottomBtn = document.getElementById("scroll-to-bottom");

// Theme definitions
const darkTheme = {
  background: "#0d1117",
  foreground: "#e6edf3",
  cursor: "#58a6ff",
  cursorAccent: "#0d1117",
  selectionBackground: "rgba(88, 166, 255, 0.3)",
  black: "#484f58",
  red: "#ff7b72",
  green: "#3fb950",
  yellow: "#d29922",
  blue: "#58a6ff",
  magenta: "#bc8cff",
  cyan: "#39c5cf",
  white: "#b1bac4",
  brightBlack: "#6e7681",
  brightRed: "#ffa198",
  brightGreen: "#56d364",
  brightYellow: "#e3b341",
  brightBlue: "#79c0ff",
  brightMagenta: "#d2a8ff",
  brightCyan: "#56d4dd",
  brightWhite: "#f0f6fc",
};

const lightTheme = {
  background: "#ffffff",
  foreground: "#24292f",
  cursor: "#0969da",
  cursorAccent: "#ffffff",
  selectionBackground: "rgba(9, 105, 218, 0.3)",
  black: "#24292f",
  red: "#cf222e",
  green: "#1a7f37",
  yellow: "#9a6700",
  blue: "#0969da",
  magenta: "#8250df",
  cyan: "#1b7c83",
  white: "#6e7781",
  brightBlack: "#57606a",
  brightRed: "#a40e26",
  brightGreen: "#116329",
  brightYellow: "#7d4e00",
  brightBlue: "#0550ae",
  brightMagenta: "#6639ba",
  brightCyan: "#136061",
  brightWhite: "#8c959f",
};

// WebGL disabled - canvas renderer handles theme changes better
function loadWebGL() {
  // Intentionally empty - using canvas renderer for reliable theming
}

// Initialize terminal
function initTerminal() {
  term = new Terminal({
    cursorBlink: true,
    cursorStyle: "block",
    fontSize: currentFontSize,
    fontFamily: 'Menlo, Monaco, "Courier New", monospace',
    theme: currentTheme === "dark" ? darkTheme : lightTheme,
    scrollback: SCROLLBACK_LINES,
    allowProposedApi: true,
    allowTransparency: true,
    convertEol: true,
  });

  fitAddon = new FitAddon();
  term.loadAddon(fitAddon);

  // WebGL addon for GPU accelerated rendering
  loadWebGL();

  // Web links addon for clickable URLs
  try {
    const webLinksAddon = new WebLinksAddon();
    term.loadAddon(webLinksAddon);
  } catch (e) {
    console.warn("WebLinks addon failed to load:", e);
  }

  term.open(terminalContainer);
  fitAddon.fit();

  // Handle terminal input
  term.onData((data) => {
    if (ws && ws.readyState === WebSocket.OPEN && currentSession) {
      ws.send(JSON.stringify({ type: "input", data }));
    }
  });

  // Handle terminal resize
  term.onResize(({ cols, rows }) => {
    if (ws && ws.readyState === WebSocket.OPEN && currentSession) {
      ws.send(JSON.stringify({ type: "resize", cols, rows }));
    }
  });

  // Handle window resize
  window.addEventListener("resize", () => {
    if (fitAddon) {
      fitAddon.fit();
    }
  });

  // Prevent browser shortcuts when terminal is focused
  terminalContainer.addEventListener("keydown", (e) => {
    // Allow Ctrl+Shift+C/V for copy/paste
    if (e.ctrlKey && e.shiftKey && (e.key === "C" || e.key === "V")) {
      return;
    }
    // Allow Cmd+C/V on Mac
    if (e.metaKey && (e.key === "c" || e.key === "v")) {
      return;
    }
    // Block other browser shortcuts
    if (e.ctrlKey || e.metaKey) {
      // Allow terminal control sequences
      if (!e.shiftKey && !e.altKey) {
        // These go to terminal, don't prevent
        return;
      }
    }
  });

  // Scroll to bottom button click handler
  if (scrollToBottomBtn) {
    scrollToBottomBtn.onclick = () => {
      if (term) {
        smoothScrollToBottom();
        scrollToBottomBtn.classList.add("scroll-hidden");
      }
    };
  }

  // Track scroll via viewport element
  setTimeout(() => {
    const viewport = term.element?.querySelector(".xterm-viewport");
    if (viewport) {
      viewport.addEventListener("scroll", updateScrollButton);
      updateScrollButton(); // Initial check
    }
  }, 100);
}

// Smooth scroll to bottom of terminal
function smoothScrollToBottom() {
  if (!term) return;
  const viewport = term.element?.querySelector(".xterm-viewport");
  if (!viewport) return;

  const targetScroll = viewport.scrollHeight - viewport.clientHeight;
  const startScroll = viewport.scrollTop;
  const distance = targetScroll - startScroll;

  if (distance <= 0) return;

  const duration = Math.min(400, Math.max(150, distance * 0.5)); // 150-400ms based on distance
  const startTime = performance.now();

  function easeOutCubic(t) {
    return 1 - Math.pow(1 - t, 3);
  }

  function animate(currentTime) {
    const elapsed = currentTime - startTime;
    const progress = Math.min(elapsed / duration, 1);
    const eased = easeOutCubic(progress);

    viewport.scrollTop = startScroll + distance * eased;

    if (progress < 1) {
      requestAnimationFrame(animate);
    }
  }

  requestAnimationFrame(animate);
}

// Check if viewport is near the bottom
function isNearBottom() {
  if (!term) return true;
  const viewport = term.element?.querySelector(".xterm-viewport");
  if (!viewport) return true;

  const scrollTop = viewport.scrollTop;
  const scrollHeight = viewport.scrollHeight;
  const clientHeight = viewport.clientHeight;

  // At bottom if within 50px of the end
  return scrollTop >= scrollHeight - clientHeight - 50;
}

// Update scroll button visibility based on scroll position
function updateScrollButton() {
  if (!term || !scrollToBottomBtn) return;

  if (isNearBottom()) {
    scrollToBottomBtn.classList.add("scroll-hidden");
  } else {
    scrollToBottomBtn.classList.remove("scroll-hidden");
  }
}

// WebSocket connection management
function connect() {
  const protocol = window.location.protocol === "https:" ? "wss:" : "ws:";
  const wsUrl = `${protocol}//${window.location.host}`;

  updateConnectionStatus("connecting");
  ws = new WebSocket(wsUrl);
  isAuthenticated = false;
  authRequired = false;

  ws.onopen = () => {
    console.log("WebSocket connected");
    updateConnectionStatus("connected");
    reconnectAttempts = 0;
    // Server will send auth-required message
  };

  ws.onmessage = (event) => {
    const msg = JSON.parse(event.data);
    handleMessage(msg);
  };

  ws.onclose = () => {
    console.log("WebSocket disconnected");
    updateConnectionStatus("disconnected");
    isAuthenticated = false;
    // Only auto-reconnect if not manually disconnected
    if (!manuallyDisconnected) {
      scheduleReconnect();
    }
  };

  ws.onerror = (error) => {
    console.error("WebSocket error:", error);
    updateConnectionStatus("failed");
  };
}

function scheduleReconnect() {
  if (reconnectAttempts >= MAX_RECONNECT_ATTEMPTS) {
    console.log("Max reconnect attempts reached");
    updateConnectionStatus("failed");
    return;
  }

  updateConnectionStatus("reconnecting");

  const delay = RECONNECT_BASE_DELAY * Math.pow(2, reconnectAttempts);
  reconnectAttempts++;

  console.log(`Reconnecting in ${delay}ms (attempt ${reconnectAttempts})`);

  reconnectTimer = setTimeout(() => {
    connect();
  }, delay);
}

// Manual disconnect
let manuallyDisconnected = false;

function disconnect() {
  manuallyDisconnected = true;
  if (reconnectTimer) {
    clearTimeout(reconnectTimer);
    reconnectTimer = null;
  }
  if (ws) {
    ws.close();
    ws = null;
  }
  updateConnectionStatus("disconnected");
}

function manualReconnect() {
  manuallyDisconnected = false;
  reconnectAttempts = 0;
  connect();
}

function updateConnectionStatus(status) {
  connectionStatus.className = status;
  const disconnectBtn = document.getElementById("disconnect-btn");

  switch (status) {
    case "connecting":
      statusText.textContent = "Connecting...";
      if (disconnectBtn) disconnectBtn.style.display = "none";
      break;
    case "connected":
      statusText.textContent = "Connected";
      if (disconnectBtn) {
        disconnectBtn.style.display = "inline-flex";
        // Re-init Lucide for newly visible button
        if (window.lucide) lucide.createIcons({ nodes: [disconnectBtn] });
      }
      break;
    case "disconnected":
      statusText.textContent = "Disconnected";
      if (disconnectBtn) disconnectBtn.style.display = "none";
      break;
    case "reconnecting":
      statusText.textContent = `Reconnecting (${reconnectAttempts}/${MAX_RECONNECT_ATTEMPTS})...`;
      if (disconnectBtn) disconnectBtn.style.display = "none";
      break;
    case "failed":
      statusText.textContent = "Failed - Tap to retry";
      if (disconnectBtn) disconnectBtn.style.display = "none";
      break;
  }
}

// Handle incoming WebSocket messages
function handleMessage(msg) {
  switch (msg.type) {
    case "auth-required":
      authRequired = msg.required;
      if (msg.required) {
        // Check if we have a saved password
        const savedPassword = sessionStorage.getItem("serverPassword");
        if (savedPassword) {
          ws.send(JSON.stringify({ type: "auth", password: savedPassword }));
        } else {
          showAuthModal();
        }
      } else {
        // No auth required
        isAuthenticated = true;
        onAuthenticated();
      }
      break;

    case "auth-success":
      isAuthenticated = true;
      hideAuthModal();
      onAuthenticated();
      break;

    case "auth-failed":
      isAuthenticated = false;
      sessionStorage.removeItem("serverPassword");
      showAuthModal(msg.message || "Invalid password");
      break;

    case "output":
      if (term) {
        // Check scroll position before write
        const wasAtBottom = isNearBottom();
        term.write(msg.data);
        // Only auto-scroll if user was already at bottom
        if (wasAtBottom) {
          requestAnimationFrame(() => term.scrollToBottom());
        } else {
          // Show scroll button when new content arrives while scrolled up
          requestAnimationFrame(() => updateScrollButton());
        }
      }
      break;

    case "sessions":
      sessions = msg.list || [];
      renderTabs();
      updateView();
      break;

    case "created":
      console.log(`Session created: ${msg.name}`);
      break;

    case "attached":
      currentSession = msg.name;
      updateView();
      // Send resize after attaching
      if (fitAddon && term) {
        const dims = fitAddon.proposeDimensions();
        if (dims) {
          ws.send(
            JSON.stringify({
              type: "resize",
              cols: dims.cols,
              rows: dims.rows,
            }),
          );
        }
      }
      // Focus terminal
      if (term) {
        term.focus();
      }
      break;

    case "killed":
      if (currentSession === msg.name) {
        currentSession = null;
        if (term) {
          term.clear();
        }
      }
      // Session list will be updated via broadcast
      break;

    case "renamed":
      if (currentSession === msg.oldName) {
        currentSession = msg.newName;
      }
      break;

    case "exited":
      if (currentSession === msg.name) {
        term.write(
          `\r\n\x1b[33m[Session "${msg.name}" exited with code ${msg.exitCode}]\x1b[0m\r\n`,
        );
        currentSession = null;
      }
      break;

    case "error":
      console.error("Server error:", msg.message);
      // Handle "session not found" gracefully - just clear and show no session view
      if (msg.message && msg.message.includes("not found")) {
        currentSession = null;
        localStorage.removeItem("currentSession");
        if (term) {
          term.clear();
        }
        updateView();
      } else if (term && currentSession) {
        // Show other errors in terminal
        term.write(`\r\n\x1b[31m[Error: ${msg.message}]\x1b[0m\r\n`);
      }
      break;
  }
}

// Called after successful authentication
function onAuthenticated() {
  // Request session list
  ws.send(JSON.stringify({ type: "list" }));

  // If we had a session, try to reattach
  if (currentSession) {
    // Clear terminal before reattaching to avoid mixing old content with new scrollback
    if (term) {
      term.clear();
      term.reset();
    }
    ws.send(JSON.stringify({ type: "attach", name: currentSession }));
  }
}

// Auth modal functions
function showAuthModal(errorMessage) {
  modalTitle.textContent = errorMessage
    ? "Authentication Failed"
    : "Password Required";
  modalInput.placeholder = "Enter server password";
  modalInput.value = "";
  modalInput.type = "password";
  modalConfirm.textContent = "Connect";

  if (errorMessage) {
    // Show error message
    let errorEl = document.getElementById("modal-error");
    if (!errorEl) {
      errorEl = document.createElement("div");
      errorEl.id = "modal-error";
      errorEl.style.cssText =
        "color: #ff7b72; font-size: 0.9rem; margin-bottom: 12px;";
      modalInput.parentNode.insertBefore(errorEl, modalInput);
    }
    errorEl.textContent = errorMessage;
  }

  modalCallback = (password) => {
    sessionStorage.setItem("serverPassword", password);
    ws.send(JSON.stringify({ type: "auth", password }));
  };

  modalOverlay.classList.remove("hidden");
  modalInput.focus();
}

function hideAuthModal() {
  modalInput.type = "text";
  const errorEl = document.getElementById("modal-error");
  if (errorEl) {
    errorEl.remove();
  }
}

// Render session tabs
function renderTabs() {
  tabsContainer.innerHTML = "";

  for (const session of sessions) {
    const tab = document.createElement("div");
    tab.className = "tab" + (session.name === currentSession ? " active" : "");
    tab.dataset.session = session.name;

    const nameSpan = document.createElement("span");
    nameSpan.className = "session-name";
    nameSpan.textContent = session.name;

    const closeBtn = document.createElement("span");
    closeBtn.className = "close-tab";
    closeBtn.textContent = "×";
    closeBtn.onclick = (e) => {
      e.stopPropagation();
      killSession(session.name);
    };

    tab.appendChild(nameSpan);
    tab.appendChild(closeBtn);

    tab.onclick = () => {
      if (currentSession !== session.name) {
        attachToSession(session.name);
      }
    };

    tab.oncontextmenu = (e) => {
      e.preventDefault();
      showContextMenu(e, session.name);
    };

    tabsContainer.appendChild(tab);
  }

  // Update document title
  if (currentSession) {
    document.title = `${currentSession} - Web Terminal`;
  } else {
    document.title = "Web Terminal";
  }
}

// Update view based on state
function updateView() {
  if (currentSession) {
    noSessionView.classList.add("hidden");
    terminalContainer.style.display = "block";
    if (fitAddon) {
      fitAddon.fit();
    }
  } else if (sessions.length === 0) {
    noSessionView.classList.remove("hidden");
    terminalContainer.style.display = "none";
  } else {
    // We have sessions but none selected - auto-select first
    attachToSession(sessions[0].name);
  }

  renderTabs();

  // Save to localStorage
  if (currentSession) {
    localStorage.setItem("currentSession", currentSession);
  } else {
    localStorage.removeItem("currentSession");
  }
}

// Session management functions
function createSession(name) {
  if (ws && ws.readyState === WebSocket.OPEN) {
    // Clear terminal for new session
    if (term) {
      term.clear();
      term.reset();
    }
    ws.send(JSON.stringify({ type: "create", name }));
  }
}

function attachToSession(name) {
  if (ws && ws.readyState === WebSocket.OPEN) {
    // Clear terminal before attaching
    if (term) {
      term.clear();
      term.reset();
    }
    ws.send(JSON.stringify({ type: "attach", name }));
  }
}

function killSession(name) {
  if (ws && ws.readyState === WebSocket.OPEN) {
    ws.send(JSON.stringify({ type: "kill", name }));
  }
}

function renameSession(oldName, newName) {
  if (ws && ws.readyState === WebSocket.OPEN) {
    ws.send(JSON.stringify({ type: "rename", oldName, newName }));
  }
}

// Modal management
let modalCallback = null;

function showModal(title, placeholder, confirmText, callback) {
  modalTitle.textContent = title;
  modalInput.placeholder = placeholder;
  modalInput.value = "";
  modalConfirm.textContent = confirmText;
  modalCallback = callback;
  modalOverlay.classList.remove("hidden");
  modalInput.focus();
}

function hideModal() {
  modalOverlay.classList.add("hidden");
  modalCallback = null;
  // Return focus to terminal
  if (term) {
    term.focus();
  }
}

function confirmModal() {
  const value = modalInput.value.trim();
  if (value && modalCallback) {
    modalCallback(value);
  }
  hideModal();
}

// Context menu management
function showContextMenu(event, sessionName) {
  contextMenuTarget = sessionName;
  contextMenu.style.left = `${event.clientX}px`;
  contextMenu.style.top = `${event.clientY}px`;
  contextMenu.classList.remove("hidden");
}

function hideContextMenu() {
  contextMenu.classList.add("hidden");
  contextMenuTarget = null;
}

// Event listeners
newSessionBtn.onclick = () => {
  showModal("New Session", "Session name", "Create", (name) => {
    createSession(name);
  });
};

createFirstSessionBtn.onclick = () => {
  showModal("New Session", "Session name", "Create", (name) => {
    createSession(name);
  });
};

modalCancel.onclick = hideModal;

modalConfirm.onclick = confirmModal;

modalInput.onkeydown = (e) => {
  if (e.key === "Enter") {
    confirmModal();
  } else if (e.key === "Escape") {
    hideModal();
  }
};

modalOverlay.onclick = (e) => {
  if (e.target === modalOverlay) {
    hideModal();
  }
};

// Context menu event listeners
document.addEventListener("click", hideContextMenu);

contextMenu.onclick = (e) => {
  const action = e.target.dataset.action;
  if (!action || !contextMenuTarget) return;

  switch (action) {
    case "rename":
      showModal("Rename Session", "New name", "Rename", (newName) => {
        renameSession(contextMenuTarget, newName);
      });
      break;
    case "kill":
      killSession(contextMenuTarget);
      break;
  }

  hideContextMenu();
};

// Keyboard shortcuts
document.addEventListener("keydown", (e) => {
  // Close modal on Escape
  if (e.key === "Escape") {
    if (!modalOverlay.classList.contains("hidden")) {
      hideModal();
    }
    if (!contextMenu.classList.contains("hidden")) {
      hideContextMenu();
    }
    const settingsPanel = document.getElementById("settings-panel");
    if (settingsPanel && !settingsPanel.classList.contains("hidden")) {
      hideSettings();
    }
  }
});

// Touch toolbar elements
const touchToolbar = document.getElementById("touch-toolbar");
const fontDecrease = document.getElementById("font-decrease");
const fontIncrease = document.getElementById("font-increase");
const settingsPanel = document.getElementById("settings-panel");
const settingsClose = document.getElementById("settings-close");
const fontSizeSlider = document.getElementById("font-size-slider");
const fontSizeDisplay = document.getElementById("font-size-display");
const quickCommandsContainer = document.getElementById("quick-commands");
const newCmdInput = document.getElementById("new-cmd-input");
const addCmdBtn = document.getElementById("add-cmd-btn");

// Header buttons
const toolbarToggle = document.getElementById("toolbar-toggle");
const themeToggleHeader = document.getElementById("theme-toggle-header");
const settingsBtnHeader = document.getElementById("settings-btn-header");

// Toolbar toggle state
let toolbarVisible = localStorage.getItem("toolbarVisible") === "true";

// Apply theme
function applyTheme(theme) {
  currentTheme = theme;
  document.documentElement.setAttribute("data-theme", theme);
  localStorage.setItem("theme", theme);

  if (term) {
    term.options.theme = theme === "dark" ? darkTheme : lightTheme;
  }
}

// Font size functions
function setFontSize(size) {
  size = Math.max(MIN_FONT_SIZE, Math.min(MAX_FONT_SIZE, size));
  currentFontSize = size;
  if (term) {
    term.options.fontSize = size;
    if (fitAddon) {
      fitAddon.fit();
    }
  }
  if (fontSizeSlider) fontSizeSlider.value = size;
  if (fontSizeDisplay) fontSizeDisplay.textContent = size + "px";
  localStorage.setItem("fontSize", size);
}

// Settings panel
function showSettings() {
  if (settingsPanel) {
    settingsPanel.classList.remove("hidden");
    renderQuickCommands();
  }
}

function hideSettings() {
  if (settingsPanel) {
    settingsPanel.classList.add("hidden");
  }
  if (term) term.focus();
}

// Quick commands - using safe DOM methods
function renderQuickCommands() {
  if (!quickCommandsContainer) return;

  // Clear existing buttons safely
  while (quickCommandsContainer.firstChild) {
    quickCommandsContainer.removeChild(quickCommandsContainer.firstChild);
  }

  quickCommands.forEach((cmd, index) => {
    const btn = document.createElement("button");
    btn.className = "quick-cmd";
    btn.textContent = cmd;
    btn.onclick = () => {
      if (ws && ws.readyState === WebSocket.OPEN && currentSession) {
        ws.send(JSON.stringify({ type: "input", data: cmd + "\n" }));
      }
      hideSettings();
    };
    btn.oncontextmenu = (e) => {
      e.preventDefault();
      quickCommands.splice(index, 1);
      localStorage.setItem("quickCommands", JSON.stringify(quickCommands));
      renderQuickCommands();
    };
    quickCommandsContainer.appendChild(btn);
  });
}

function addQuickCommand(cmd) {
  if (cmd && !quickCommands.includes(cmd)) {
    quickCommands.push(cmd);
    localStorage.setItem("quickCommands", JSON.stringify(quickCommands));
    renderQuickCommands();
  }
}

// Touch toolbar event handlers
if (touchToolbar) {
  touchToolbar.addEventListener("click", (e) => {
    const btn = e.target.closest(".toolbar-btn");
    if (!btn) return;

    // Handle modifier keys
    if (btn.dataset.modifier) {
      const mod = btn.dataset.modifier;
      activeModifiers[mod] = !activeModifiers[mod];
      btn.classList.toggle("active", activeModifiers[mod]);
      return;
    }

    // Handle key sequences (^C, ^D, ^Z)
    if (btn.dataset.sequence) {
      const seq = btn.dataset.sequence;
      let data = "";
      if (seq === "ctrl+c") data = "\x03";
      else if (seq === "ctrl+d") data = "\x04";
      else if (seq === "ctrl+z") data = "\x1a";

      if (data && ws && ws.readyState === WebSocket.OPEN && currentSession) {
        ws.send(JSON.stringify({ type: "input", data }));
      }
      return;
    }

    // Handle regular keys
    if (btn.dataset.key) {
      let data = "";
      const key = btn.dataset.key;

      switch (key) {
        case "Escape":
          data = "\x1b";
          break;
        case "Tab":
          data = "\t";
          break;
        case "ArrowUp":
          data = "\x1b[A";
          break;
        case "ArrowDown":
          data = "\x1b[B";
          break;
        case "ArrowRight":
          data = "\x1b[C";
          break;
        case "ArrowLeft":
          data = "\x1b[D";
          break;
      }

      // Apply modifiers
      if (activeModifiers.ctrl && data.length === 1) {
        const code = data.toUpperCase().charCodeAt(0);
        if (code >= 65 && code <= 90) {
          data = String.fromCharCode(code - 64);
        }
      }

      if (data && ws && ws.readyState === WebSocket.OPEN && currentSession) {
        ws.send(JSON.stringify({ type: "input", data }));
      }

      // Clear modifiers after use
      activeModifiers.ctrl = false;
      activeModifiers.alt = false;
      touchToolbar
        .querySelectorAll(".modifier")
        .forEach((m) => m.classList.remove("active"));
    }
  });
}

// Font controls
if (fontDecrease) {
  fontDecrease.onclick = () => setFontSize(currentFontSize - 1);
}
if (fontIncrease) {
  fontIncrease.onclick = () => setFontSize(currentFontSize + 1);
}

// Toolbar toggle function
function toggleToolbar() {
  toolbarVisible = !toolbarVisible;
  if (touchToolbar) {
    touchToolbar.classList.toggle("hidden", !toolbarVisible);
  }
  if (toolbarToggle) {
    toolbarToggle.classList.toggle("active", toolbarVisible);
  }
  localStorage.setItem("toolbarVisible", toolbarVisible);
  // Refit terminal after toolbar toggle
  if (fitAddon) {
    setTimeout(() => fitAddon.fit(), 100);
  }
}

// Apply toolbar state on load
function applyToolbarState() {
  if (touchToolbar) {
    touchToolbar.classList.toggle("hidden", !toolbarVisible);
  }
  if (toolbarToggle) {
    toolbarToggle.classList.toggle("active", toolbarVisible);
  }
}

// Toolbar toggle button
if (toolbarToggle) {
  toolbarToggle.onclick = toggleToolbar;
}

// Theme toggle (header button)
if (themeToggleHeader) {
  themeToggleHeader.onclick = () => {
    applyTheme(currentTheme === "dark" ? "light" : "dark");
  };
}

// Settings button (header button)
if (settingsBtnHeader) {
  settingsBtnHeader.onclick = showSettings;
}
if (settingsClose) {
  settingsClose.onclick = hideSettings;
}

// Font size slider
if (fontSizeSlider) {
  fontSizeSlider.value = currentFontSize;
  fontSizeSlider.oninput = () => setFontSize(parseInt(fontSizeSlider.value));
}
if (fontSizeDisplay) {
  fontSizeDisplay.textContent = currentFontSize + "px";
}

// Add command button
if (addCmdBtn && newCmdInput) {
  addCmdBtn.onclick = () => {
    const cmd = newCmdInput.value.trim();
    if (cmd) {
      addQuickCommand(cmd);
      newCmdInput.value = "";
    }
  };
  newCmdInput.onkeydown = (e) => {
    if (e.key === "Enter") {
      addCmdBtn.click();
    }
  };
}

// Disconnect button and connection status click handlers
const disconnectBtn = document.getElementById("disconnect-btn");
if (disconnectBtn) {
  disconnectBtn.onclick = () => {
    if (confirm("Disconnect from server?")) {
      disconnect();
    }
  };
}

// Click on connection status to reconnect when disconnected
if (connectionStatus) {
  connectionStatus.onclick = () => {
    if (
      connectionStatus.className === "disconnected" ||
      connectionStatus.className === "failed"
    ) {
      manualReconnect();
    }
  };
  connectionStatus.style.cursor = "pointer";
}

// Initialize
function init() {
  // Apply saved theme to document (CSS variables)
  document.documentElement.setAttribute("data-theme", currentTheme);

  // Initialize terminal (will use currentTheme for colors)
  initTerminal();
  connect();

  // Apply toolbar visibility state
  applyToolbarState();

  // Restore current session from localStorage
  const savedSession = localStorage.getItem("currentSession");
  if (savedSession) {
    currentSession = savedSession;
  }
}

// Start the app when DOM is ready
if (document.readyState === "loading") {
  document.addEventListener("DOMContentLoaded", init);
} else {
  init();
}
