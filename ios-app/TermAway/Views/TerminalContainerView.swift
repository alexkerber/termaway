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
    @ObservedObject var themeManager = ThemeManager.shared

    func makeUIView(context: Context) -> SwiftTerm.TerminalView {
        let terminalView = TerminalView(frame: .zero)

        // Configure terminal appearance using ThemeManager
        applyTheme(to: terminalView)

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

        // Apply theme updates
        applyTheme(to: uiView)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(connectionManager: connectionManager)
    }

    private func applyTheme(to terminalView: TerminalView) {
        let theme = themeManager.currentTheme

        terminalView.configureNativeColors()
        terminalView.installColors(theme.ansiColors.map { $0.uiColor })
        terminalView.font = UIFont.monospacedSystemFont(ofSize: themeManager.fontSize, weight: .regular)
        terminalView.nativeForegroundColor = theme.foreground.uiColor
        terminalView.nativeBackgroundColor = theme.background.uiColor
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
