import SwiftUI
import SwiftTerm

/// A view that displays multiple terminal panes in a split layout (iPad only)
/// Each pane can display a DIFFERENT session.
struct SplitTerminalView: View {
    @EnvironmentObject var connectionManager: ConnectionManager
    @EnvironmentObject var themeManager: ThemeManager
    @EnvironmentObject var splitPaneManager: SplitPaneManager

    var body: some View {
        GeometryReader { geo in
            switch splitPaneManager.layout {
            case .single:
                // Single pane - use the pane's session
                if let firstPane = splitPaneManager.panes.first,
                   let sessionName = firstPane.sessionName {
                    TerminalContainerView(session: Session(name: sessionName))
                } else {
                    emptyPaneView()
                }

            case .horizontal:
                HStack(spacing: 12) {
                    ForEach(splitPaneManager.panes.prefix(2)) { pane in
                        paneView(pane: pane)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 54)
                .padding(.bottom, 16)

            case .vertical:
                VStack(spacing: 12) {
                    ForEach(splitPaneManager.panes.prefix(2)) { pane in
                        paneView(pane: pane)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 54)
                .padding(.bottom, 16)

            case .tripleVertical:
                VStack(spacing: 10) {
                    ForEach(splitPaneManager.panes.prefix(3)) { pane in
                        paneView(pane: pane)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 54)
                .padding(.bottom, 16)

            case .grid:
                VStack(spacing: 12) {
                    HStack(spacing: 12) {
                        ForEach(splitPaneManager.panes.prefix(2)) { pane in
                            paneView(pane: pane)
                        }
                    }
                    HStack(spacing: 12) {
                        ForEach(splitPaneManager.panes.dropFirst(2).prefix(2)) { pane in
                            paneView(pane: pane)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 54)
                .padding(.bottom, 16)
            }
        }
        .background(Color(uiColor: themeManager.currentTheme.backgroundColor))
    }

    @ViewBuilder
    private func paneView(pane: TerminalPane) -> some View {
        let isFocused = splitPaneManager.focusedPaneId == pane.id

        ZStack {
            // Background for the pane
            Color(uiColor: themeManager.currentTheme.backgroundColor)

            if let sessionName = pane.sessionName {
                // Pane has a session - show terminal
                PaneTerminalView(
                    sessionName: sessionName,
                    isFocused: isFocused,
                    onTap: {
                        splitPaneManager.focus(paneId: pane.id)
                        // Update active session for input routing
                        connectionManager.setActiveSession(sessionName)
                    }
                )
                .padding(8)
            } else {
                // No session assigned - show prompt to select one
                emptyPaneContent()
            }

            // Focus indicator border (only when glow is disabled, or unfocused)
            RoundedRectangle(cornerRadius: 8)
                .stroke(
                    isFocused && !themeManager.focusGlowEnabled ? themeManager.focusGlowColor : Color.white.opacity(0.15),
                    lineWidth: isFocused && !themeManager.focusGlowEnabled ? 2 : 1
                )
                .allowsHitTesting(false)
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
        // Glow effect for focused pane (only when glow is enabled)
        .shadow(color: isFocused && themeManager.focusGlowEnabled ? themeManager.focusGlowColor.opacity(0.5) : .clear, radius: 8)
        .shadow(color: isFocused && themeManager.focusGlowEnabled ? themeManager.focusGlowColor.opacity(0.3) : .clear, radius: 16)
        // Note: Tap handling is done by the terminal's UITapGestureRecognizer
        // which calls onTap and also handles becomeFirstResponder
    }

    @ViewBuilder
    private func emptyPaneView() -> some View {
        VStack {
            ProgressView()
                .progressViewStyle(CircularProgressViewStyle(tint: .secondary))
            Text("Starting...")
                .font(.caption)
                .foregroundColor(.secondary.opacity(0.7))
        }
    }

    @ViewBuilder
    private func emptyPaneContent() -> some View {
        VStack {
            ProgressView()
                .progressViewStyle(CircularProgressViewStyle(tint: .secondary))
            Text("Starting...")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
}

/// A terminal view for a specific pane that connects to its own session
struct PaneTerminalView: View {
    @EnvironmentObject var connectionManager: ConnectionManager
    @EnvironmentObject var themeManager: ThemeManager
    let sessionName: String
    let isFocused: Bool
    var onTap: (() -> Void)?

    @State private var terminalView: TerminalView?

    var body: some View {
        PaneTerminalViewRepresentable(
            connectionManager: connectionManager,
            themeManager: themeManager,
            sessionName: sessionName,
            isFocused: isFocused,
            terminalView: $terminalView,
            onTap: onTap
        )
    }
}

struct PaneTerminalViewRepresentable: UIViewRepresentable {
    let connectionManager: ConnectionManager
    @ObservedObject var themeManager: ThemeManager
    let sessionName: String
    let isFocused: Bool
    @Binding var terminalView: TerminalView?
    var onTap: (() -> Void)?

    func makeUIView(context: Context) -> SwiftTerm.TerminalView {
        let terminalView = TerminalView(frame: .zero)

        // Configure terminal appearance from theme
        let theme = themeManager.currentTheme
        terminalView.font = UIFont.monospacedSystemFont(ofSize: themeManager.fontSize, weight: .regular)
        terminalView.nativeForegroundColor = theme.foregroundColor
        terminalView.nativeBackgroundColor = theme.backgroundColor

        // Hide iOS keyboard accessory bar
        terminalView.inputAccessoryView = nil

        // Set up the terminal delegate
        terminalView.terminalDelegate = context.coordinator
        context.coordinator.terminalView = terminalView
        context.coordinator.onTap = onTap
        context.coordinator.sessionName = sessionName

        // Register output handler now that terminalView is set
        context.coordinator.setupOutputHandler()

        // Add tap gesture to detect focus changes
        let tapGesture = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap))
        tapGesture.cancelsTouchesInView = false  // Let terminal still receive the tap
        terminalView.addGestureRecognizer(tapGesture)

        // Store reference
        DispatchQueue.main.async {
            self.terminalView = terminalView
        }

        // If this pane is focused when created, become first responder after view is ready
        if isFocused {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak terminalView] in
                guard let tv = terminalView, tv.window != nil else { return }
                if !tv.isFirstResponder {
                    _ = tv.becomeFirstResponder()
                }
            }
        }

        return terminalView
    }

    func updateUIView(_ uiView: SwiftTerm.TerminalView, context: Context) {
        // Update coordinator references
        context.coordinator.connectionManager = connectionManager
        context.coordinator.sessionName = sessionName

        // Update theme if changed
        let theme = themeManager.currentTheme
        uiView.font = UIFont.monospacedSystemFont(ofSize: themeManager.fontSize, weight: .regular)
        uiView.nativeForegroundColor = theme.foregroundColor
        uiView.nativeBackgroundColor = theme.backgroundColor

        // Handle focus changes - become first responder if focused
        // Use a brief delay to ensure view hierarchy is stable after SwiftUI updates
        if isFocused && !uiView.isFirstResponder {
            // Only try if view is in a window (ready for first responder)
            if uiView.window != nil {
                print("PaneTerminal[\(sessionName)]: updateUIView - isFocused, scheduling becomeFirstResponder")
                // Small delay to let SwiftUI finish any pending layout updates
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak uiView, sessionName] in
                    guard let tv = uiView, tv.window != nil else { return }
                    if !tv.isFirstResponder {
                        let success = tv.becomeFirstResponder()
                        print("PaneTerminal[\(sessionName)]: updateUIView delayed - becomeFirstResponder = \(success)")
                    }
                }
            }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(connectionManager: connectionManager, sessionName: sessionName)
    }

    class Coordinator: NSObject, TerminalViewDelegate {
        var connectionManager: ConnectionManager
        var sessionName: String
        var onTap: (() -> Void)?

        /// Last known terminal size from sizeChanged callback
        private var lastCols: Int = 80
        private var lastRows: Int = 24

        /// ID for this coordinator's terminal output handler
        private var outputHandlerId: UUID?

        @objc func handleTap() {
            onTap?()
            // Forcefully become first responder on tap
            guard let tv = terminalView else {
                print("PaneTerminal[\(sessionName)]: handleTap - terminalView is nil!")
                return
            }

            if tv.isFirstResponder {
                print("PaneTerminal[\(sessionName)]: handleTap - already first responder")
                return
            }

            print("PaneTerminal[\(sessionName)]: handleTap - attempting becomeFirstResponder")
            let success = tv.becomeFirstResponder()
            print("PaneTerminal[\(sessionName)]: handleTap - becomeFirstResponder = \(success)")

            // If immediate attempt failed, try again after a brief delay
            if !success {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak tv] in
                    guard let tv = tv, !tv.isFirstResponder else { return }
                    let retrySuccess = tv.becomeFirstResponder()
                    print("PaneTerminal[\(self.sessionName)]: handleTap retry - becomeFirstResponder = \(retrySuccess)")
                }
            }
        }

        weak var terminalView: TerminalView?

        init(connectionManager: ConnectionManager, sessionName: String) {
            self.connectionManager = connectionManager
            self.sessionName = sessionName
            super.init()
            // Handler registration moved to setupOutputHandler() called from makeUIView
        }

        /// Called from makeUIView after terminalView is set
        func setupOutputHandler() {
            guard let tv = terminalView else {
                print("PaneTerminal[\(sessionName)]: ERROR - terminalView is nil in setupOutputHandler")
                return
            }
            let session = sessionName
            let cm = connectionManager
            print("PaneTerminal[\(session)]: registering output handler")
            Task { @MainActor in
                self.outputHandlerId = cm.registerOutputHandler(for: session) { [weak tv] data in
                    print("PaneTerminal[\(session)]: received \(data.count) chars, feeding to terminal")
                    tv?.feed(text: data)
                }
            }
        }

        deinit {
            let cm = connectionManager
            let handlerId = outputHandlerId
            let session = sessionName
            Task { @MainActor in
                if let id = handlerId {
                    cm.unregisterOutputHandler(for: session, id: id)
                }
            }
        }

        private func scrollToBottom() {
            guard let tv = terminalView else { return }
            let bottomOffset = CGPoint(x: 0, y: max(tv.contentSize.height - tv.bounds.height, 0))
            tv.setContentOffset(bottomOffset, animated: false)
        }

        func send(source: TerminalView, data: ArraySlice<UInt8>) {
            let string = String(bytes: data, encoding: .utf8) ?? ""
            let session = sessionName
            Task { @MainActor in
                // Send input to THIS pane's session
                connectionManager.sendInput(string, to: session)
            }
        }

        func scrolled(source: TerminalView, position: Double) {}

        func setTerminalTitle(source: TerminalView, title: String) {}

        func sizeChanged(source: TerminalView, newCols: Int, newRows: Int) {
            lastCols = newCols
            lastRows = newRows
            let session = sessionName
            Task { @MainActor in
                connectionManager.sendResize(cols: newCols, rows: newRows, for: session)
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
