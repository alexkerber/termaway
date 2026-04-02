import SwiftUI
import SwiftTerm
import UIKit

/// A terminal view for secondary split panes with its own independent session.
/// Each pane creates its own WebSocket connection and session.
struct IndependentTerminalView: View {
    @EnvironmentObject var connectionManager: ConnectionManager
    @EnvironmentObject var themeManager: ThemeManager
    let paneId: UUID
    let isFocused: Bool
    var onTap: (() -> Void)?

    @State private var terminalView: TerminalView?
    @StateObject private var paneConnection = PaneConnection()

    var body: some View {
        IndependentTerminalViewRepresentable(
            paneConnection: paneConnection,
            connectionManager: connectionManager,
            themeManager: themeManager,
            isFocused: isFocused,
            terminalView: $terminalView,
            onTap: onTap
        )
        .onDisappear {
            paneConnection.disconnect()
        }
    }
}

struct IndependentTerminalViewRepresentable: UIViewRepresentable {
    @ObservedObject var paneConnection: PaneConnection
    let connectionManager: ConnectionManager
    @ObservedObject var themeManager: ThemeManager
    let isFocused: Bool
    @Binding var terminalView: TerminalView?
    var onTap: (() -> Void)?

    func makeUIView(context: Context) -> SwiftTerm.TerminalView {
        let terminalView = TerminalView(frame: .zero)

        // Configure terminal appearance from theme
        let theme = themeManager.currentTheme
        terminalView.font = UIFont.monospacedSystemFont(ofSize: themeManager.fontSize, weight: .regular)
        terminalView.nativeForegroundColor = theme.foregroundColor
        terminalView.caretColor = theme.cursorColor
        terminalView.nativeBackgroundColor = theme.backgroundColor

        // Hide iOS keyboard accessory bar
        terminalView.inputAccessoryView = nil
        terminalView.overrideUserInterfaceStyle = themeManager.isChromeLightMode ? .light : .dark

        // Set up the terminal delegate
        terminalView.terminalDelegate = context.coordinator
        context.coordinator.onTap = onTap
        context.coordinator.terminalView = terminalView

        // Add tap gesture to detect focus changes
        let tapGesture = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap))
        tapGesture.cancelsTouchesInView = false
        terminalView.addGestureRecognizer(tapGesture)

        // Store reference
        DispatchQueue.main.async {
            self.terminalView = terminalView
        }

        return terminalView
    }

    func updateUIView(_ uiView: SwiftTerm.TerminalView, context: Context) {
        // Update theme if changed
        let theme = themeManager.currentTheme
        uiView.font = UIFont.monospacedSystemFont(ofSize: themeManager.fontSize, weight: .regular)
        uiView.nativeForegroundColor = theme.foregroundColor
        uiView.caretColor = theme.cursorColor
        uiView.nativeBackgroundColor = theme.backgroundColor
        uiView.overrideUserInterfaceStyle = themeManager.isChromeLightMode ? .light : .dark

        // Handle focus changes
        if isFocused && !uiView.isFirstResponder {
            DispatchQueue.main.async {
                _ = uiView.becomeFirstResponder()
            }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(paneConnection: paneConnection, connectionManager: connectionManager)
    }

    class Coordinator: NSObject, TerminalViewDelegate {
        let paneConnection: PaneConnection
        let connectionManager: ConnectionManager
        var onTap: (() -> Void)?
        private var hasConnected = false

        weak var terminalView: TerminalView? {
            didSet {
                guard let tv = terminalView else { return }

                // Set up output handler and connect on main actor
                Task { @MainActor [weak self, weak tv] in
                    guard let self = self else { return }
                    self.paneConnection.onOutput = { [weak tv] data in
                        tv?.feed(text: data)
                    }

                    // Connect if we haven't already
                    if !self.hasConnected {
                        self.connectToServer()
                        self.hasConnected = true
                    }
                }
            }
        }

        init(paneConnection: PaneConnection, connectionManager: ConnectionManager) {
            self.paneConnection = paneConnection
            self.connectionManager = connectionManager
            super.init()
        }

        @MainActor
        private func connectToServer() {
            guard let urlString = connectionManager.serverURL,
                  let url = URL(string: urlString) else {
                print("IndependentTerminalView: Failed to get server URL")
                return
            }
            paneConnection.connect(to: url, authToken: connectionManager.serverPassword)
        }

        @objc func handleTap() {
            onTap?()
        }

        func send(source: TerminalView, data: ArraySlice<UInt8>) {
            let string = String(bytes: data, encoding: .utf8) ?? ""
            Task { @MainActor in
                paneConnection.sendInput(string)
            }
        }

        func scrolled(source: TerminalView, position: Double) {}

        func setTerminalTitle(source: TerminalView, title: String) {}

        func sizeChanged(source: TerminalView, newCols: Int, newRows: Int) {
            Task { @MainActor in
                paneConnection.sendResize(cols: newCols, rows: newRows)
            }
        }

        func clipboardCopy(source: TerminalView, content: Data) {
            if let string = String(data: content, encoding: .utf8) {
                UIPasteboard.general.string = string
            }
        }

        func requestOpenLink(source: TerminalView, link: String, params: [String : String]) {
            if let url = URL(string: link) {
                UIApplication.shared.open(url)
            }
        }

        func bell(source: TerminalView) {
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.warning)
        }

        func rangeChanged(source: SwiftTerm.TerminalView, startY: Int, endY: Int) {}

        func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}

        func hostCurrentDocumentUpdate(source: SwiftTerm.TerminalView, documentUrl: URL?) {}
    }
}
