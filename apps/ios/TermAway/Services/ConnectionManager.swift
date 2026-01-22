import Foundation
import Combine
import UIKit
import UserNotifications

@MainActor
class ConnectionManager: ObservableObject {
    @Published var isConnected = false
    @Published var isConnecting = false
    @Published var sessions: [Session] = []
    @Published var currentSession: Session?
    @Published var lastError: String?
    @Published var isReconnecting = false
    @Published var reconnectAttempts = 0
    @Published var isAuthenticated = false
    @Published var authRequired = false
    @Published var isAuthenticating = false

    private var webSocket: URLSessionWebSocketTask?
    private var urlSession: URLSession?
    private var reconnectTask: Task<Void, Never>?
    private var shouldAutoReconnect = false
    private let maxReconnectAttempts = 10
    private var appLifecycleObserver: NSObjectProtocol?

    // MARK: - Per-Session Output Handling
    //
    // Split panes show DIFFERENT sessions simultaneously.
    // Each session has its own:
    // - Output buffer (for history)
    // - Pending scrollback (for session switch timing)
    // - Output handlers (terminal views subscribed to this session)
    //
    // Flow:
    // 1. attachToSession(name) attaches to a session (can attach to multiple)
    // 2. Server sends output with session name: { type: "output", name: "Test-3", data: "..." }
    // 3. Output is routed to the correct session's handlers
    // 4. Input goes to the "active" session (focused pane)

    /// Per-session connection state
    struct SessionState {
        var outputBuffer: String = ""
        var outputHandlers: [UUID: (String) -> Void] = [:]
    }

    /// State for each attached session
    private var sessionStates: [String: SessionState] = [:]
    private let maxOutputBufferSize = 2_000_000

    /// The currently active session for input routing (focused pane's session)
    @Published var activeSessionName: String?

    /// Callback when a session is removed (killed or exited) - used to clear saved layouts
    var onSessionRemoved: ((String) -> Void)?

    /// Register a terminal output handler for a specific session
    func registerOutputHandler(for sessionName: String, handler: @escaping (String) -> Void) -> UUID {
        let id = UUID()
        if sessionStates[sessionName] == nil {
            sessionStates[sessionName] = SessionState()
        }
        sessionStates[sessionName]?.outputHandlers[id] = handler

        // Feed any existing buffered output immediately
        if let buffer = sessionStates[sessionName]?.outputBuffer, !buffer.isEmpty {
            print("registerOutputHandler[\(sessionName)]: feeding \(buffer.count) buffered chars")
            handler(buffer)
        }

        return id
    }

    /// Remove a terminal output handler
    func unregisterOutputHandler(for sessionName: String, id: UUID) {
        sessionStates[sessionName]?.outputHandlers.removeValue(forKey: id)
    }

    /// Send output to all handlers for a specific session
    private func notifySessionOutput(_ sessionName: String, _ data: String) {
        guard let state = sessionStates[sessionName] else {
            print("notifySessionOutput[\(sessionName)]: no session state!")
            return
        }
        let handlerCount = state.outputHandlers.count
        print("notifySessionOutput[\(sessionName)]: \(data.count) chars to \(handlerCount) handlers")
        for handler in state.outputHandlers.values {
            handler(data)
        }
    }

    /// Get the output buffer for a session
    func getSessionOutputBuffer(for sessionName: String) -> String {
        return sessionStates[sessionName]?.outputBuffer ?? ""
    }

    var serverURL: String? {
        UserDefaults.standard.string(forKey: "serverURL") ?? "ws://192.168.1.231:3000"
    }

    var serverPassword: String? {
        get { UserDefaults.standard.string(forKey: "serverPassword") }
        set { UserDefaults.standard.set(newValue, forKey: "serverPassword") }
    }

    var lastSessionName: String? {
        get { UserDefaults.standard.string(forKey: "lastSessionName") }
        set { UserDefaults.standard.set(newValue, forKey: "lastSessionName") }
    }

    init() {
        // Load saved server URL or use default
        if UserDefaults.standard.string(forKey: "serverURL") == nil {
            UserDefaults.standard.set("ws://192.168.1.231:3000", forKey: "serverURL")
        }

        // Observe app lifecycle to resume reconnection
        setupAppLifecycleObserver()
    }

    deinit {
        if let observer = appLifecycleObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    private func setupAppLifecycleObserver() {
        appLifecycleObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.willEnterForegroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                // Resume reconnection if we were trying to reconnect
                if self?.shouldAutoReconnect == true && self?.isConnected == false {
                    self?.attemptReconnect()
                }
            }
        }
    }

    func setServerURL(_ url: String) {
        // Auto-correct http:// to ws:// and https:// to wss://
        var correctedURL = url
        if correctedURL.hasPrefix("http://") {
            correctedURL = "ws://" + correctedURL.dropFirst(7)
        } else if correctedURL.hasPrefix("https://") {
            correctedURL = "wss://" + correctedURL.dropFirst(8)
        } else if !correctedURL.hasPrefix("ws://") && !correctedURL.hasPrefix("wss://") {
            // If no protocol, assume ws://
            correctedURL = "ws://" + correctedURL
        }
        UserDefaults.standard.set(correctedURL, forKey: "serverURL")
    }

    func connect() {
        guard !isConnecting, !isConnected else { return }
        guard let serverURL = serverURL, let url = URL(string: serverURL) else {
            lastError = "Invalid server URL"
            return
        }

        isConnecting = true
        isReconnecting = false
        lastError = nil
        shouldAutoReconnect = true
        reconnectAttempts = 0
        isAuthenticated = false
        authRequired = false
        isAuthenticating = false
        sessionStates.removeAll()
        activeSessionName = nil

        let config = URLSessionConfiguration.default
        config.waitsForConnectivity = true
        urlSession = URLSession(configuration: config)

        webSocket = urlSession?.webSocketTask(with: url)
        webSocket?.resume()

        // Start receiving messages
        receiveMessage()

        // Timeout if server doesn't respond within 5 seconds
        // We only mark as connected when we receive auth-required message
        Task {
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            // If still connecting after 5s, the server isn't responding
            if isConnecting && !isConnected {
                isConnecting = false
                lastError = "Unable to connect to server"
                webSocket?.cancel(with: .goingAway, reason: nil)
                webSocket = nil
                attemptReconnect()
            }
        }
    }

    func disconnect() {
        shouldAutoReconnect = false
        reconnectTask?.cancel()
        reconnectTask = nil
        isReconnecting = false
        reconnectAttempts = 0

        webSocket?.cancel(with: .goingAway, reason: nil)
        webSocket = nil
        urlSession?.invalidateAndCancel()
        urlSession = nil
        isConnected = false
        isConnecting = false
        isAuthenticated = false
        authRequired = false
        sessions = []
        currentSession = nil
        activeSessionName = nil
        sessionStates.removeAll()
        lastError = nil  // Clear any error on intentional disconnect
    }

    private func receiveMessage() {
        webSocket?.receive { [weak self] result in
            Task { @MainActor in
                guard let self = self else { return }

                switch result {
                case .success(let message):
                    switch message {
                    case .string(let text):
                        self.handleMessage(text)
                    case .data(let data):
                        if let text = String(data: data, encoding: .utf8) {
                            self.handleMessage(text)
                        }
                    @unknown default:
                        break
                    }
                    // Continue receiving
                    self.receiveMessage()

                case .failure(let error):
                    print("WebSocket error: \(error)")
                    self.isConnected = false
                    self.isConnecting = false

                    // Only show error and attempt reconnect if we were supposed to be connected
                    if self.shouldAutoReconnect {
                        // Show user-friendly error instead of raw WebSocket error
                        self.lastError = "Unable to connect to server"
                        self.attemptReconnect()
                    }
                    // If intentionally disconnected (shouldAutoReconnect = false), don't show error
                }
            }
        }
    }

    private func attemptReconnect() {
        guard shouldAutoReconnect else { return }
        guard reconnectAttempts < maxReconnectAttempts else {
            isReconnecting = false
            lastError = "Connection failed after \(maxReconnectAttempts) attempts. Tap to retry."
            return
        }

        // Cancel any existing reconnect task
        reconnectTask?.cancel()

        isReconnecting = true
        reconnectAttempts += 1

        // Calculate delay with exponential backoff: 1s, 2s, 4s, 8s, 16s, 30s (max)
        let baseDelay = min(pow(2.0, Double(reconnectAttempts - 1)), 30.0)
        let delayNanoseconds = UInt64(baseDelay * 1_000_000_000)

        reconnectTask = Task {
            do {
                try await Task.sleep(nanoseconds: delayNanoseconds)

                // Only proceed if we should still reconnect
                guard !Task.isCancelled, shouldAutoReconnect else { return }

                // Try to reconnect
                await performReconnect()
            } catch {
                // Task was cancelled or sleep failed
            }
        }
    }

    private func performReconnect() async {
        guard let serverURL = serverURL, let url = URL(string: serverURL) else {
            lastError = "Invalid server URL"
            isReconnecting = false
            return
        }

        isConnecting = true

        // Clear stale session data - server will send fresh list
        sessions = []
        sessionStates.removeAll()
        activeSessionName = nil

        let config = URLSessionConfiguration.default
        config.waitsForConnectivity = true
        urlSession = URLSession(configuration: config)

        webSocket = urlSession?.webSocketTask(with: url)
        webSocket?.resume()

        // Start receiving messages
        receiveMessage()

        // Timeout if server doesn't respond within 5 seconds
        // Connection is confirmed when we receive auth-required message
        try? await Task.sleep(nanoseconds: 5_000_000_000)

        // If still connecting after 5s, the server isn't responding
        if isConnecting && !isConnected {
            isConnecting = false
            webSocket?.cancel(with: .goingAway, reason: nil)
            webSocket = nil
            // Try again
            attemptReconnect()
        }
    }

    func manualReconnect() {
        reconnectAttempts = 0
        shouldAutoReconnect = true
        isReconnecting = false
        lastError = nil
        connect()
    }

    private func handleMessage(_ text: String) {
        guard let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return
        }

        let type = json["type"] as? String ?? ""

        // Handle auth messages first
        switch type {
        case "auth-required":
            // Server responded - we're truly connected now
            isConnected = true
            isConnecting = false
            isReconnecting = false
            reconnectAttempts = 0

            let required = json["required"] as? Bool ?? false
            authRequired = required
            if required {
                // Auto-send password if we have one saved
                if let password = serverPassword, !password.isEmpty {
                    isAuthenticating = true
                    sendMessage(["type": "auth", "password": password])
                }
            } else {
                // No auth required, we're good
                isAuthenticated = true
                sendMessage(["type": "list"])
            }
            return

        case "auth-success":
            isAuthenticated = true
            isAuthenticating = false
            lastError = nil
            // Now request session list
            sendMessage(["type": "list"])
            // Re-attach to current session if we had one
            if let sessionName = currentSession?.name {
                sendMessage(["type": "attach", "name": sessionName])
            }
            return

        case "auth-failed":
            isAuthenticated = false
            isAuthenticating = false
            lastError = json["message"] as? String ?? "Authentication failed"
            return

        case "clipboard-update", "clipboard-content":
            // Received clipboard from server - update local pasteboard
            if clipboardSyncEnabled, let content = json["content"] as? String {
                UIPasteboard.general.string = content
            }
            return

        case "clipboard-set-ok":
            // Clipboard was successfully set on server
            return

        case "client-connected":
            // Another client connected to the server
            if let clientIP = json["clientIP"] as? String,
               clientIP != "127.0.0.1" && clientIP != "localhost" {
                showConnectionNotification(clientIP: clientIP)
            }
            return

        default:
            break
        }

        let message = ServerMessage(from: json)

        switch message {
        case .sessions(let sessionList):
            sessions = sessionList
            // Update current session if it still exists
            if let current = currentSession {
                currentSession = sessions.first { $0.name == current.name }
            }
            // Auto-select session if none selected
            if currentSession == nil && !sessions.isEmpty {
                if sessions.count == 1 {
                    // Only one session - auto-attach
                    attachToSession(sessions[0].name)
                } else if let lastUsed = lastSessionName,
                          sessions.contains(where: { $0.name == lastUsed }) {
                    // Multiple sessions - attach to last used
                    attachToSession(lastUsed)
                }
            }

        case .output(let sessionName, let data):
            // Route output to the correct session's state
            let targetSession = sessionName.isEmpty ? (activeSessionName ?? currentSession?.name ?? "") : sessionName

            // Ensure session state exists
            if sessionStates[targetSession] == nil {
                sessionStates[targetSession] = SessionState()
            }

            // Append to buffer and trim if needed
            sessionStates[targetSession]?.outputBuffer += data
            if let bufferCount = sessionStates[targetSession]?.outputBuffer.count,
               bufferCount > maxOutputBufferSize {
                sessionStates[targetSession]?.outputBuffer.removeFirst(bufferCount - maxOutputBufferSize)
            }

            // Notify all handlers
            notifySessionOutput(targetSession, data)

        case .created(let name):
            print("Session created: \(name)")

        case .attached(let name):
            // Don't switch currentSession for pane sessions (created during split)
            if !paneSessions.contains(name) {
                currentSession = sessions.first { $0.name == name } ?? Session(name: name)
                lastSessionName = name  // Remember for next time
            }
            // Set as active session if not already set
            if activeSessionName == nil {
                activeSessionName = name
            }

        case .activeSessionSet(let name):
            activeSessionName = name

        case .killed(let name):
            if currentSession?.name == name {
                currentSession = nil
            }
            if activeSessionName == name {
                activeSessionName = nil
            }
            sessionStates.removeValue(forKey: name)
            sessions.removeAll { $0.name == name }
            onSessionRemoved?(name)

        case .renamed(let oldName, let newName):
            if currentSession?.name == oldName {
                currentSession = Session(name: newName)
            }
            if activeSessionName == oldName {
                activeSessionName = newName
            }
            // Move session state to new name
            if let state = sessionStates.removeValue(forKey: oldName) {
                sessionStates[newName] = state
            }
            if let index = sessions.firstIndex(where: { $0.name == oldName }) {
                sessions[index] = Session(name: newName)
            }

        case .exited(let name, let exitCode):
            print("Session \(name) exited with code \(exitCode)")
            if currentSession?.name == name {
                currentSession = nil
            }
            onSessionRemoved?(name)

        case .error(let message):
            lastError = message

        case .unknown:
            break
        }
    }

    // MARK: - Authentication

    func authenticate(password: String) {
        serverPassword = password
        isAuthenticating = true
        sendMessage(["type": "auth", "password": password])
    }

    private func sendMessage(_ dict: [String: Any]) {
        // Don't try to send if not connected or WebSocket is nil
        guard let socket = webSocket, isConnected || isConnecting else {
            return
        }

        guard let data = try? JSONSerialization.data(withJSONObject: dict),
              let text = String(data: data, encoding: .utf8) else {
            return
        }

        socket.send(.string(text)) { [weak self] error in
            if let error = error {
                print("Send error: \(error)")
                // Don't set lastError here for send failures after disconnect
                // as it causes confusing error messages
            }
        }
    }

    // MARK: - Session Management

    /// Sessions created for split panes (should not switch currentSession)
    private var paneSessions: Set<String> = []

    func createSession(_ name: String) {
        sendMessage(["type": "create", "name": name])
    }

    /// Create a session for a split pane - doesn't switch currentSession when attached
    func createPaneSession(_ name: String) {
        paneSessions.insert(name)
        sendMessage(["type": "create", "name": name, "ephemeral": true])
        sendMessage(["type": "attach", "name": name])
    }

    /// Attach to a session by name.
    /// Supports multiple simultaneous attachments for split panes.
    func attachToSession(_ name: String) {
        sendMessage(["type": "attach", "name": name])
    }

    /// Detach from a specific session
    func detachFromSession(_ name: String) {
        sessionStates.removeValue(forKey: name)
        sendMessage(["type": "detach", "name": name])
        // Clear active session if this was it
        if activeSessionName == name {
            activeSessionName = nil
        }
    }

    /// Set the active session for input routing (called when pane focus changes)
    func setActiveSession(_ name: String) {
        activeSessionName = name
        sendMessage(["type": "set-active-session", "name": name])
    }


    func killSession(_ name: String) {
        sendMessage(["type": "kill", "name": name])
    }

    func renameSession(_ oldName: String, _ newName: String) {
        sendMessage(["type": "rename", "oldName": oldName, "newName": newName])
    }

    // MARK: - Terminal I/O

    /// Send input to a specific session, or the active session if none specified
    func sendInput(_ text: String, to sessionName: String? = nil) {
        var msg: [String: Any] = ["type": "input", "data": text]
        if let name = sessionName {
            msg["name"] = name
        }
        sendMessage(msg)
    }

    /// Send resize to a specific session, or the active session if none specified
    func sendResize(cols: Int, rows: Int, for sessionName: String? = nil) {
        var msg: [String: Any] = ["type": "resize", "cols": cols, "rows": rows]
        if let name = sessionName {
            msg["name"] = name
        }
        sendMessage(msg)
    }

    // MARK: - Clipboard Sync

    var clipboardSyncEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: "clipboardSyncEnabled") }
        set { UserDefaults.standard.set(newValue, forKey: "clipboardSyncEnabled") }
    }

    var connectionNotificationsEnabled: Bool {
        get {
            // Default to true
            if UserDefaults.standard.object(forKey: "connectionNotificationsEnabled") == nil {
                return true
            }
            return UserDefaults.standard.bool(forKey: "connectionNotificationsEnabled")
        }
        set { UserDefaults.standard.set(newValue, forKey: "connectionNotificationsEnabled") }
    }

    func sendClipboard(_ content: String) {
        guard clipboardSyncEnabled else { return }
        sendMessage(["type": "clipboard-set", "content": content])
    }

    func requestClipboard() {
        sendMessage(["type": "clipboard-get"])
    }

    func syncLocalClipboard() {
        guard clipboardSyncEnabled, isConnected, isAuthenticated else { return }
        if let content = UIPasteboard.general.string, !content.isEmpty {
            sendClipboard(content)
        }
    }

    // MARK: - Notifications

    func requestNotificationPermissions() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, error in
            if let error = error {
                print("Notification permission error: \(error)")
            }
        }
    }

    private func showConnectionNotification(clientIP: String) {
        guard connectionNotificationsEnabled else { return }

        let content = UNMutableNotificationContent()
        content.title = "Client Connected"
        content.body = "\(clientIP) connected to your Mac"
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )

        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("Notification error: \(error)")
            }
        }
    }
}
