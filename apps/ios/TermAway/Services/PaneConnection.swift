import Foundation

/// A lightweight WebSocket connection for a single terminal pane.
/// Each split pane gets its own PaneConnection with its own session.
@MainActor
class PaneConnection: ObservableObject {
    @Published var isConnected = false
    @Published var sessionName: String?

    private var webSocket: URLSessionWebSocketTask?
    private var urlSession: URLSession?

    /// Handler for terminal output data
    var onOutput: ((String) -> Void)?

    /// Server URL to connect to
    private var serverURL: URL?

    /// Stored auth token for authentication
    private var storedAuthToken: String?

    init() {}

    // MARK: - Connection

    /// Connect to the server and create a new session
    func connect(to url: URL, authToken: String? = nil) {
        serverURL = url
        storedAuthToken = authToken

        print("PaneConnection: Connecting to \(url)")

        let config = URLSessionConfiguration.default
        urlSession = URLSession(configuration: config)
        webSocket = urlSession?.webSocketTask(with: url)
        webSocket?.resume()

        // Start receiving messages
        receiveMessage()
        isConnected = true
    }

    /// Disconnect from the server
    func disconnect() {
        webSocket?.cancel(with: .goingAway, reason: nil)
        webSocket = nil
        urlSession = nil
        isConnected = false
        sessionName = nil
    }

    // MARK: - Session Management

    /// Create a new session with auto-generated name
    private func createNewSession() {
        let name = "pane-\(UUID().uuidString.prefix(8))"
        print("PaneConnection: Creating session '\(name)'")
        send(["type": "create", "name": name, "ephemeral": true])
    }

    // MARK: - Terminal I/O

    /// Send input to the terminal
    func sendInput(_ input: String) {
        send(["type": "input", "data": input])
    }

    /// Send terminal resize
    func sendResize(cols: Int, rows: Int) {
        send(["type": "resize", "cols": cols, "rows": rows])
    }

    // MARK: - WebSocket Communication

    private func send(_ message: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: message),
              let string = String(data: data, encoding: .utf8) else { return }

        webSocket?.send(.string(string)) { error in
            if let error = error {
                print("PaneConnection send error: \(error)")
            }
        }
    }

    private func receiveMessage() {
        webSocket?.receive { [weak self] result in
            Task { @MainActor in
                switch result {
                case .success(let message):
                    self?.handleMessage(message)
                    self?.receiveMessage()
                case .failure(let error):
                    print("PaneConnection receive error: \(error)")
                    self?.isConnected = false
                }
            }
        }
    }

    private func handleMessage(_ message: URLSessionWebSocketTask.Message) {
        guard case .string(let text) = message,
              let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = json["type"] as? String else {
            print("PaneConnection: Failed to parse message")
            return
        }

        switch type {
        case "created", "attached":
            if let name = json["name"] as? String ?? json["session"] as? String {
                sessionName = name
                print("PaneConnection: Session '\(name)' ready")
            }
            if let scrollback = json["scrollback"] as? String, !scrollback.isEmpty {
                onOutput?(scrollback)
            }

        case "output":
            if let output = json["data"] as? String {
                onOutput?(output)
            }

        case "auth-required":
            let required = json["required"] as? Bool ?? false
            print("PaneConnection: auth-required, required=\(required)")
            if required {
                if let token = storedAuthToken, !token.isEmpty {
                    print("PaneConnection: Sending auth")
                    send(["type": "auth", "password": token])
                } else {
                    print("PaneConnection: No auth token!")
                }
            } else {
                createNewSession()
            }

        case "auth-success":
            print("PaneConnection: auth success")
            createNewSession()

        case "auth-failed":
            print("PaneConnection: auth failed")
            disconnect()

        case "error":
            if let errorMsg = json["message"] as? String {
                print("PaneConnection error: \(errorMsg)")
            }

        default:
            break
        }
    }
}
