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
        UserDefaults.standard.set(url, forKey: "serverURL")
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
                // Request session list
                sendMessage(["type": "list"])
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
        isConnected = false
        isConnecting = false
        sessions = []
        currentSession = nil
    }

    private func receiveMessage() {
        webSocket?.receive { [weak self] result in
            Task { @MainActor in
                switch result {
                case .success(let message):
                    switch message {
                    case .string(let text):
                        self?.handleMessage(text)
                    case .data(let data):
                        if let text = String(data: data, encoding: .utf8) {
                            self?.handleMessage(text)
                        }
                    @unknown default:
                        break
                    }
                    // Continue receiving
                    self?.receiveMessage()

                case .failure(let error):
                    print("WebSocket error: \(error)")
                    self?.isConnected = false
                    self?.isConnecting = false
                    self?.lastError = error.localizedDescription

                    // Attempt to reconnect if auto-reconnect is enabled
                    if self?.shouldAutoReconnect == true {
                        self?.attemptReconnect()
                    }
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

        let message = ServerMessage(from: json)

        switch message {
        case .sessions(let sessionList):
            sessions = sessionList
            // Update current session if it still exists
            if let current = currentSession {
                currentSession = sessions.first { $0.name == current.name }
            }

        case .output(let data):
            onTerminalOutput?(data)

        case .created(let name):
            print("Session created: \(name)")

        case .attached(let name):
            currentSession = sessions.first { $0.name == name } ?? Session(name: name)

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

    private func sendMessage(_ dict: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: dict),
              let text = String(data: data, encoding: .utf8) else {
            return
        }

        webSocket?.send(.string(text)) { error in
            if let error = error {
                print("Send error: \(error)")
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
}
