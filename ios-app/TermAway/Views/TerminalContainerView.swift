import SwiftUI
import SwiftTerm

struct TerminalContainerView: View {
    @EnvironmentObject var connectionManager: ConnectionManager
    let session: Session

    var body: some View {
        TerminalViewRepresentable(connectionManager: connectionManager)
            .ignoresSafeArea(.keyboard)
    }
}

struct TerminalViewRepresentable: UIViewRepresentable {
    let connectionManager: ConnectionManager

    func makeUIView(context: Context) -> SwiftTerm.TerminalView {
        let terminalView = TerminalView(frame: .zero)

        // Configure terminal appearance
        terminalView.configureNativeColors()
        terminalView.installColors(self.makeColorScheme())
        terminalView.font = UIFont.monospacedSystemFont(ofSize: 14, weight: .regular)
        terminalView.nativeForegroundColor = UIColor(red: 0.9, green: 0.93, blue: 0.95, alpha: 1.0)
        terminalView.nativeBackgroundColor = UIColor(red: 0.05, green: 0.07, blue: 0.09, alpha: 1.0)

        // Set up the terminal delegate
        terminalView.terminalDelegate = context.coordinator

        // Become first responder to show keyboard
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            terminalView.becomeFirstResponder()
        }

        return terminalView
    }

    func updateUIView(_ uiView: SwiftTerm.TerminalView, context: Context) {
        // Update coordinator's connection manager reference
        context.coordinator.connectionManager = connectionManager
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(connectionManager: connectionManager)
    }

    private func makeColorScheme() -> [UIColor] {
        // GitHub Dark theme colors
        return [
            UIColor(red: 0.28, green: 0.31, blue: 0.35, alpha: 1), // black
            UIColor(red: 1.0, green: 0.48, blue: 0.45, alpha: 1),  // red
            UIColor(red: 0.25, green: 0.73, blue: 0.31, alpha: 1), // green
            UIColor(red: 0.83, green: 0.60, blue: 0.13, alpha: 1), // yellow
            UIColor(red: 0.35, green: 0.65, blue: 1.0, alpha: 1),  // blue
            UIColor(red: 0.74, green: 0.55, blue: 1.0, alpha: 1),  // magenta
            UIColor(red: 0.22, green: 0.77, blue: 0.81, alpha: 1), // cyan
            UIColor(red: 0.69, green: 0.73, blue: 0.77, alpha: 1), // white
            UIColor(red: 0.43, green: 0.46, blue: 0.50, alpha: 1), // bright black
            UIColor(red: 1.0, green: 0.63, blue: 0.60, alpha: 1),  // bright red
            UIColor(red: 0.34, green: 0.83, blue: 0.39, alpha: 1), // bright green
            UIColor(red: 0.89, green: 0.70, blue: 0.26, alpha: 1), // bright yellow
            UIColor(red: 0.47, green: 0.75, blue: 1.0, alpha: 1),  // bright blue
            UIColor(red: 0.82, green: 0.66, blue: 1.0, alpha: 1),  // bright magenta
            UIColor(red: 0.34, green: 0.83, blue: 0.87, alpha: 1), // bright cyan
            UIColor(red: 0.94, green: 0.96, blue: 0.98, alpha: 1), // bright white
        ]
    }

    class Coordinator: NSObject, TerminalViewDelegate {
        var connectionManager: ConnectionManager

        init(connectionManager: ConnectionManager) {
            self.connectionManager = connectionManager
            super.init()

            // Set up output handler
            Task { @MainActor in
                connectionManager.onTerminalOutput = { [weak self] data in
                    // This will be called when server sends output
                    // We need to feed it to the terminal
                    NotificationCenter.default.post(
                        name: .terminalOutput,
                        object: nil,
                        userInfo: ["data": data]
                    )
                }
            }
        }

        // Called when user types in terminal
        func send(source: TerminalView, data: ArraySlice<UInt8>) {
            let string = String(bytes: data, encoding: .utf8) ?? ""
            Task { @MainActor in
                connectionManager.sendInput(string)
            }
        }

        // Called when terminal is scrolled
        func scrolled(source: TerminalView, position: Double) {
            // Not needed for remote terminal
        }

        // Called when terminal title changes
        func setTerminalTitle(source: TerminalView, title: String) {
            // Could update navigation title
        }

        // Called when terminal size changes
        func sizeChanged(source: TerminalView, newCols: Int, newRows: Int) {
            Task { @MainActor in
                connectionManager.sendResize(cols: newCols, rows: newRows)
            }
        }

        // Called when clipboard operation requested
        func clipboardCopy(source: TerminalView, content: Data) {
            if let string = String(data: content, encoding: .utf8) {
                UIPasteboard.general.string = string
            }
        }

        // Called to request clipboard content
        func requestOpenLink(source: TerminalView, link: String, params: [String : String]) {
            if let url = URL(string: link) {
                UIApplication.shared.open(url)
            }
        }

        // Bell sound
        func bell(source: TerminalView) {
            // Could play haptic feedback
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.warning)
        }

        // Range changed
        func rangeChanged(source: SwiftTerm.TerminalView, startY: Int, endY: Int) {
            // Not needed
        }

        func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {
            // Not needed for remote
        }

        func hostCurrentDocumentUpdate(source: SwiftTerm.TerminalView, documentUrl: URL?) {
            // Not needed
        }
    }
}

// Custom TerminalView subclass to handle output notifications
class RemoteTerminalView: TerminalView {
    private var outputObserver: NSObjectProtocol?

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupOutputObserver()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupOutputObserver()
    }

    private func setupOutputObserver() {
        outputObserver = NotificationCenter.default.addObserver(
            forName: .terminalOutput,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            if let data = notification.userInfo?["data"] as? String {
                self?.feed(text: data)
            }
        }
    }

    deinit {
        if let observer = outputObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }
}

extension Notification.Name {
    static let terminalOutput = Notification.Name("terminalOutput")
}
