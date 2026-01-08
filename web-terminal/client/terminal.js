// xterm.js and addons are loaded via script tags as globals
const { Terminal } = window;
const { FitAddon } = window.FitAddon;
const { WebglAddon } = window.WebglAddon;
const { WebLinksAddon } = window.WebLinksAddon;

// State
let ws = null;
let term = null;
let fitAddon = null;
let currentSession = null;
let sessions = [];
let reconnectAttempts = 0;
let reconnectTimer = null;
let contextMenuTarget = null;

// Configuration
const MAX_RECONNECT_ATTEMPTS = 10;
const RECONNECT_BASE_DELAY = 1000;
const SCROLLBACK_LINES = 10000;

// DOM Elements
const terminalContainer = document.getElementById('terminal');
const noSessionView = document.getElementById('no-session');
const tabsContainer = document.getElementById('tabs');
const newSessionBtn = document.getElementById('new-session-btn');
const createFirstSessionBtn = document.getElementById('create-first-session');
const connectionStatus = document.getElementById('connection-status');
const statusText = connectionStatus.querySelector('.status-text');
const modalOverlay = document.getElementById('modal-overlay');
const modalTitle = document.getElementById('modal-title');
const modalInput = document.getElementById('modal-input');
const modalCancel = document.getElementById('modal-cancel');
const modalConfirm = document.getElementById('modal-confirm');
const contextMenu = document.getElementById('context-menu');

// Initialize terminal
function initTerminal() {
  term = new Terminal({
    cursorBlink: true,
    cursorStyle: 'block',
    fontSize: 14,
    fontFamily: 'Menlo, Monaco, "Courier New", monospace',
    theme: {
      background: '#0d1117',
      foreground: '#e6edf3',
      cursor: '#58a6ff',
      cursorAccent: '#0d1117',
      selectionBackground: 'rgba(88, 166, 255, 0.3)',
      black: '#484f58',
      red: '#ff7b72',
      green: '#3fb950',
      yellow: '#d29922',
      blue: '#58a6ff',
      magenta: '#bc8cff',
      cyan: '#39c5cf',
      white: '#b1bac4',
      brightBlack: '#6e7681',
      brightRed: '#ffa198',
      brightGreen: '#56d364',
      brightYellow: '#e3b341',
      brightBlue: '#79c0ff',
      brightMagenta: '#d2a8ff',
      brightCyan: '#56d4dd',
      brightWhite: '#f0f6fc',
    },
    scrollback: SCROLLBACK_LINES,
    allowProposedApi: true,
    allowTransparency: true,
    convertEol: true,
  });

  fitAddon = new FitAddon();
  term.loadAddon(fitAddon);

  // WebGL addon for GPU accelerated rendering
  try {
    const webglAddon = new WebglAddon();
    webglAddon.onContextLoss(() => {
      webglAddon.dispose();
    });
    term.loadAddon(webglAddon);
  } catch (e) {
    console.warn('WebGL addon failed to load, falling back to canvas renderer:', e);
  }

  // Web links addon for clickable URLs
  try {
    const webLinksAddon = new WebLinksAddon();
    term.loadAddon(webLinksAddon);
  } catch (e) {
    console.warn('WebLinks addon failed to load:', e);
  }

  term.open(terminalContainer);
  fitAddon.fit();

  // Handle terminal input
  term.onData((data) => {
    if (ws && ws.readyState === WebSocket.OPEN && currentSession) {
      ws.send(JSON.stringify({ type: 'input', data }));
    }
  });

  // Handle terminal resize
  term.onResize(({ cols, rows }) => {
    if (ws && ws.readyState === WebSocket.OPEN && currentSession) {
      ws.send(JSON.stringify({ type: 'resize', cols, rows }));
    }
  });

  // Handle window resize
  window.addEventListener('resize', () => {
    if (fitAddon) {
      fitAddon.fit();
    }
  });

  // Prevent browser shortcuts when terminal is focused
  terminalContainer.addEventListener('keydown', (e) => {
    // Allow Ctrl+Shift+C/V for copy/paste
    if (e.ctrlKey && e.shiftKey && (e.key === 'C' || e.key === 'V')) {
      return;
    }
    // Allow Cmd+C/V on Mac
    if (e.metaKey && (e.key === 'c' || e.key === 'v')) {
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
}

// WebSocket connection management
function connect() {
  const protocol = window.location.protocol === 'https:' ? 'wss:' : 'ws:';
  const wsUrl = `${protocol}//${window.location.host}`;

  ws = new WebSocket(wsUrl);

  ws.onopen = () => {
    console.log('WebSocket connected');
    updateConnectionStatus('connected');
    reconnectAttempts = 0;

    // Request session list
    ws.send(JSON.stringify({ type: 'list' }));

    // If we had a session, try to reattach
    if (currentSession) {
      ws.send(JSON.stringify({ type: 'attach', name: currentSession }));
    }
  };

  ws.onmessage = (event) => {
    const msg = JSON.parse(event.data);
    handleMessage(msg);
  };

  ws.onclose = () => {
    console.log('WebSocket disconnected');
    updateConnectionStatus('disconnected');
    scheduleReconnect();
  };

  ws.onerror = (error) => {
    console.error('WebSocket error:', error);
  };
}

function scheduleReconnect() {
  if (reconnectAttempts >= MAX_RECONNECT_ATTEMPTS) {
    console.log('Max reconnect attempts reached');
    return;
  }

  updateConnectionStatus('reconnecting');

  const delay = RECONNECT_BASE_DELAY * Math.pow(2, reconnectAttempts);
  reconnectAttempts++;

  console.log(`Reconnecting in ${delay}ms (attempt ${reconnectAttempts})`);

  reconnectTimer = setTimeout(() => {
    connect();
  }, delay);
}

function updateConnectionStatus(status) {
  connectionStatus.className = status;
  switch (status) {
    case 'connected':
      statusText.textContent = 'Connected';
      break;
    case 'disconnected':
      statusText.textContent = 'Disconnected';
      break;
    case 'reconnecting':
      statusText.textContent = 'Reconnecting...';
      break;
  }
}

// Handle incoming WebSocket messages
function handleMessage(msg) {
  switch (msg.type) {
    case 'output':
      if (term) {
        term.write(msg.data);
      }
      break;

    case 'sessions':
      sessions = msg.list || [];
      renderTabs();
      updateView();
      break;

    case 'created':
      console.log(`Session created: ${msg.name}`);
      break;

    case 'attached':
      currentSession = msg.name;
      updateView();
      // Send resize after attaching
      if (fitAddon && term) {
        const dims = fitAddon.proposeDimensions();
        if (dims) {
          ws.send(JSON.stringify({ type: 'resize', cols: dims.cols, rows: dims.rows }));
        }
      }
      // Focus terminal
      if (term) {
        term.focus();
      }
      break;

    case 'killed':
      if (currentSession === msg.name) {
        currentSession = null;
        if (term) {
          term.clear();
        }
      }
      // Session list will be updated via broadcast
      break;

    case 'renamed':
      if (currentSession === msg.oldName) {
        currentSession = msg.newName;
      }
      break;

    case 'exited':
      if (currentSession === msg.name) {
        term.write(`\r\n\x1b[33m[Session "${msg.name}" exited with code ${msg.exitCode}]\x1b[0m\r\n`);
        currentSession = null;
      }
      break;

    case 'error':
      console.error('Server error:', msg.message);
      // Show error in terminal if attached
      if (term && currentSession) {
        term.write(`\r\n\x1b[31m[Error: ${msg.message}]\x1b[0m\r\n`);
      }
      break;
  }
}

// Render session tabs
function renderTabs() {
  tabsContainer.innerHTML = '';

  for (const session of sessions) {
    const tab = document.createElement('div');
    tab.className = 'tab' + (session.name === currentSession ? ' active' : '');
    tab.dataset.session = session.name;

    const nameSpan = document.createElement('span');
    nameSpan.className = 'session-name';
    nameSpan.textContent = session.name;

    const closeBtn = document.createElement('span');
    closeBtn.className = 'close-tab';
    closeBtn.textContent = '×';
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
    document.title = 'Web Terminal';
  }
}

// Update view based on state
function updateView() {
  if (currentSession) {
    noSessionView.classList.add('hidden');
    terminalContainer.style.display = 'block';
    if (fitAddon) {
      fitAddon.fit();
    }
  } else if (sessions.length === 0) {
    noSessionView.classList.remove('hidden');
    terminalContainer.style.display = 'none';
  } else {
    // We have sessions but none selected - auto-select first
    attachToSession(sessions[0].name);
  }

  renderTabs();

  // Save to localStorage
  if (currentSession) {
    localStorage.setItem('currentSession', currentSession);
  } else {
    localStorage.removeItem('currentSession');
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
    ws.send(JSON.stringify({ type: 'create', name }));
  }
}

function attachToSession(name) {
  if (ws && ws.readyState === WebSocket.OPEN) {
    // Clear terminal before attaching
    if (term) {
      term.clear();
      term.reset();
    }
    ws.send(JSON.stringify({ type: 'attach', name }));
  }
}

function killSession(name) {
  if (ws && ws.readyState === WebSocket.OPEN) {
    ws.send(JSON.stringify({ type: 'kill', name }));
  }
}

function renameSession(oldName, newName) {
  if (ws && ws.readyState === WebSocket.OPEN) {
    ws.send(JSON.stringify({ type: 'rename', oldName, newName }));
  }
}

// Modal management
let modalCallback = null;

function showModal(title, placeholder, confirmText, callback) {
  modalTitle.textContent = title;
  modalInput.placeholder = placeholder;
  modalInput.value = '';
  modalConfirm.textContent = confirmText;
  modalCallback = callback;
  modalOverlay.classList.remove('hidden');
  modalInput.focus();
}

function hideModal() {
  modalOverlay.classList.add('hidden');
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
  contextMenu.classList.remove('hidden');
}

function hideContextMenu() {
  contextMenu.classList.add('hidden');
  contextMenuTarget = null;
}

// Event listeners
newSessionBtn.onclick = () => {
  showModal('New Session', 'Session name', 'Create', (name) => {
    createSession(name);
  });
};

createFirstSessionBtn.onclick = () => {
  showModal('New Session', 'Session name', 'Create', (name) => {
    createSession(name);
  });
};

modalCancel.onclick = hideModal;

modalConfirm.onclick = confirmModal;

modalInput.onkeydown = (e) => {
  if (e.key === 'Enter') {
    confirmModal();
  } else if (e.key === 'Escape') {
    hideModal();
  }
};

modalOverlay.onclick = (e) => {
  if (e.target === modalOverlay) {
    hideModal();
  }
};

// Context menu event listeners
document.addEventListener('click', hideContextMenu);

contextMenu.onclick = (e) => {
  const action = e.target.dataset.action;
  if (!action || !contextMenuTarget) return;

  switch (action) {
    case 'rename':
      showModal('Rename Session', 'New name', 'Rename', (newName) => {
        renameSession(contextMenuTarget, newName);
      });
      break;
    case 'kill':
      killSession(contextMenuTarget);
      break;
  }

  hideContextMenu();
};

// Keyboard shortcuts
document.addEventListener('keydown', (e) => {
  // Close modal on Escape
  if (e.key === 'Escape') {
    if (!modalOverlay.classList.contains('hidden')) {
      hideModal();
    }
    if (!contextMenu.classList.contains('hidden')) {
      hideContextMenu();
    }
  }
});

// Initialize
function init() {
  initTerminal();
  connect();

  // Restore current session from localStorage
  const savedSession = localStorage.getItem('currentSession');
  if (savedSession) {
    currentSession = savedSession;
  }
}

// Start the app when DOM is ready
if (document.readyState === 'loading') {
  document.addEventListener('DOMContentLoaded', init);
} else {
  init();
}
