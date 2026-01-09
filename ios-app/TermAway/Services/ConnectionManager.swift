import Foundation
import Combine

@MainActor
class ConnectionManager: ObservableObject {
    @Published var isConnected = false
    @Published var isConnecting = false
    @Published var sessions: [Session] = []
    @Published var currentSession: Session?
    @Published var lastError: String?

    private var webSocket: URLSessionWebSocketTask?
    private var urlSession: URLSession?

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
        lastError = nil

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
                // Request session list
                sendMessage(["type": "list"])
            } else {
                isConnecting = false
                lastError = "Connection failed"
            }
        }
    }

    func disconnect() {
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
                    self?.lastError = error.localizedDescription
                }
            }
        }
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
