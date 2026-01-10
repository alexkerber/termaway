import Foundation
import Combine
import UIKit

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

    // Terminal data callback - set by TerminalView
    var onTerminalOutput: ((String) -> Void)?

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

        let config = URLSessionConfiguration.default
        config.waitsForConnectivity = true
        urlSession = URLSession(configuration: config)

        webSocket = urlSession?.webSocketTask(with: url)
        webSocket?.resume()

        // Start receiving messages
        receiveMessage()

        // Check connection after a delay
        Task {
            try? await Task.sleep(nanoseconds: 500_000_000)
            if webSocket?.state == .running {
                isConnected = true
                isConnecting = false
                isReconnecting = false
                reconnectAttempts = 0
                // Server will send auth-required message, which triggers auth flow
            } else {
                isConnecting = false
                lastError = "Connection failed"
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
                        self.lastError = error.localizedDescription
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

        let config = URLSessionConfiguration.default
        config.waitsForConnectivity = true
        urlSession = URLSession(configuration: config)

        webSocket = urlSession?.webSocketTask(with: url)
        webSocket?.resume()

        // Start receiving messages
        receiveMessage()

        // Check connection after a delay
        try? await Task.sleep(nanoseconds: 500_000_000)

        if webSocket?.state == .running {
            isConnected = true
            isConnecting = false
            isReconnecting = false
            reconnectAttempts = 0
            lastError = nil
            // Request session list
            sendMessage(["type": "list"])

            // Re-attach to current session if we had one
            if let sessionName = currentSession?.name {
                sendMessage(["type": "attach", "name": sessionName])
            }
        } else {
            isConnecting = false
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

        case .output(let data):
            onTerminalOutput?(data)

        case .created(let name):
            print("Session created: \(name)")

        case .attached(let name):
            currentSession = sessions.first { $0.name == name } ?? Session(name: name)
            lastSessionName = name  // Remember for next time

        case .killed(let name):
            if currentSession?.name == name {
                currentSession = nil
            }
            sessions.removeAll { $0.name == name }

        case .renamed(let oldName, let newName):
            if currentSession?.name == oldName {
                currentSession = Session(name: newName)
            }
            if let index = sessions.firstIndex(where: { $0.name == oldName }) {
                sessions[index] = Session(name: newName)
            }

        case .exited(let name, let exitCode):
            print("Session \(name) exited with code \(exitCode)")
            if currentSession?.name == name {
                currentSession = nil
            }

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

    func createSession(_ name: String) {
        sendMessage(["type": "create", "name": name])
    }

    func attachToSession(_ name: String) {
        sendMessage(["type": "attach", "name": name])
    }

    func killSession(_ name: String) {
        sendMessage(["type": "kill", "name": name])
    }

    func renameSession(_ oldName: String, _ newName: String) {
        sendMessage(["type": "rename", "oldName": oldName, "newName": newName])
    }

    // MARK: - Terminal I/O

    func sendInput(_ text: String) {
        sendMessage(["type": "input", "data": text])
    }

    func sendResize(cols: Int, rows: Int) {
        sendMessage(["type": "resize", "cols": cols, "rows": rows])
    }

    // MARK: - Clipboard Sync

    var clipboardSyncEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: "clipboardSyncEnabled") }
        set { UserDefaults.standard.set(newValue, forKey: "clipboardSyncEnabled") }
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
}
