import SwiftUI
import SwiftTerm

// MARK: - iOS 26 Glass Effect Extension
extension View {
    @ViewBuilder
    func withGlassEffect() -> some View {
        if #available(iOS 26.0, *) {
            self.glassEffect()
        } else {
            self.background(.ultraThinMaterial)
        }
    }

    @ViewBuilder
    func withGlassEffect(in shape: some Shape) -> some View {
        if #available(iOS 26.0, *) {
            self.glassEffect()
        } else {
            self.background(.ultraThinMaterial, in: shape)
        }
    }

    @ViewBuilder
    func if_iOS26GlassEffect() -> some View {
        if #available(iOS 26.0, *) {
            self.background(.clear).glassEffect().clipShape(Capsule())
        } else {
            self
        }
    }
}

struct TerminalContainerView: View {
    @EnvironmentObject var connectionManager: ConnectionManager
    @EnvironmentObject var shortcutsManager: ShortcutsManager
    @EnvironmentObject var themeManager: ThemeManager
    let session: Session
    @State private var terminalView: TerminalView?

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .bottom) {
                // Terminal with top padding for the app bar, bottom for safe area
                TerminalViewRepresentable(
                    connectionManager: connectionManager,
                    themeManager: themeManager,
                    terminalView: $terminalView
                )
                .padding(.top, 50)
                .padding(.horizontal, 8)
                .padding(.bottom, geo.safeAreaInsets.bottom)

                // Floating toolbar - handles its own keyboard positioning
                if terminalView != nil {
                    ShortcutsToolbarView(
                        terminalView: $terminalView,
                        bottomSafeArea: geo.safeAreaInsets.bottom
                    )
                }
            }
        }
        .ignoresSafeArea(edges: .bottom)
        .onAppear {
            // Re-attach to ensure we get the scrollback buffer
            // This handles the case where auto-attach happened before terminal was ready
            connectionManager.attachToSession(session.name)
        }
    }
}

// MARK: - Shortcuts Toolbar
struct ShortcutsToolbarView: View {
    @EnvironmentObject var shortcutsManager: ShortcutsManager
    @EnvironmentObject var themeManager: ThemeManager
    @Binding var terminalView: TerminalView?
    var bottomSafeArea: CGFloat = 0

    @State private var isToolbarVisible = true
    @State private var isKeyboardVisible = false
    @State private var keyboardHeight: CGFloat = 0

    // Icon color adapts to terminal background
    private var iconColor: SwiftUI.Color {
        themeManager.terminalOverlayColor
    }

    var body: some View {
        VStack {
            Spacer()
            Group {
                if isKeyboardVisible {
                    // Keyboard visible: full width pill, no toggle
                    shortcutsPill(fullWidth: true)
                        .padding(.horizontal, 16)
                } else {
                    // Keyboard hidden: toggle + pill
                    HStack(alignment: .center, spacing: 8) {
                        toggleButton

                        if isToolbarVisible {
                            shortcutsPill(fullWidth: false)
                                .transition(.asymmetric(
                                    insertion: .scale(scale: 0.9, anchor: .leading).combined(with: .opacity),
                                    removal: .scale(scale: 0.9, anchor: .leading).combined(with: .opacity)
                                ))
                        }
                    }
                    .padding(.horizontal, 16)
                }
            }
            .padding(.bottom, isKeyboardVisible ? (keyboardHeight + 8) : (bottomSafeArea + 20))
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: isToolbarVisible)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: isKeyboardVisible)
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { notification in
            if let keyboardFrame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect {
                keyboardHeight = keyboardFrame.height
            }
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                isKeyboardVisible = true
                isToolbarVisible = true
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                isKeyboardVisible = false
                keyboardHeight = 0
            }
        }
    }

    @ViewBuilder
    private var toggleButton: some View {
        Button(action: {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                isToolbarVisible.toggle()
            }
        }) {
            Image(systemName: isToolbarVisible ? "chevron.down" : "chevron.up")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(iconColor.opacity(0.85))
                .frame(width: 40, height: 40)
        }
        .background {
            if #available(iOS 26.0, *) {
                Circle().fill(.clear).glassEffect()
            } else {
                Circle().fill(iconColor.opacity(0.15))
            }
        }
    }

    @ViewBuilder
    private func shortcutsPill(fullWidth: Bool) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 2) {
                ForEach(shortcutsManager.toolbarShortcuts) { shortcut in
                    ShortcutKey(
                        shortcut: shortcut,
                        isActive: shortcutsManager.ctrlModeActive && shortcut.name == "Ctrl",
                        iconColor: iconColor
                    ) {
                        handleShortcut(shortcut)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
        }
        .frame(maxWidth: fullWidth ? .infinity : nil)
        .background {
            if #available(iOS 26.0, *) {
                Capsule().fill(.clear).glassEffect()
            } else {
                Capsule().fill(iconColor.opacity(0.15))
            }
        }
        .clipShape(Capsule())
    }

    private func handleShortcut(_ shortcut: Shortcut) {
        // Handle Ctrl modifier toggle
        if shortcut.name == "Ctrl" {
            shortcutsManager.ctrlModeActive.toggle()
            return
        }

        var command = shortcut.command

        // Apply Ctrl modifier if active
        if shortcutsManager.ctrlModeActive && command.count == 1 {
            if let char = command.lowercased().first,
               let asciiValue = char.asciiValue,
               asciiValue >= 97 && asciiValue <= 122 {
                // Convert to control character (a=1, b=2, etc.)
                let ctrlChar = Character(UnicodeScalar(asciiValue - 96))
                command = String(ctrlChar)
            }
            shortcutsManager.ctrlModeActive = false
        }

        sendKey(command)
    }

    private func sendKey(_ key: String) {
        if let data = key.data(using: .utf8) {
            let bytes = Array(data)
            terminalView?.send(bytes)
        }
    }
}

// MARK: - Shortcut Key View (32x32 iOS 26 style)
struct ShortcutKey: View {
    let shortcut: Shortcut
    var isActive: Bool = false
    var iconColor: SwiftUI.Color = .white
    let action: () -> Void

    // Map shortcut names to SF Symbols
    private var sfSymbol: String? {
        switch shortcut.name {
        case "Tab": return "arrow.right.to.line"
        case "Escape": return "escape"
        case "Ctrl": return "control"
        case "Up Arrow": return "arrow.up"
        case "Down Arrow": return "arrow.down"
        case "Left Arrow": return "arrow.left"
        case "Right Arrow": return "arrow.right"
        default: return nil
        }
    }

    // Short label for text display
    private var shortLabel: String {
        switch shortcut.name {
        case "Ctrl+C": return "^C"
        case "Ctrl+D": return "^D"
        case "Ctrl+Z": return "^Z"
        default: return shortcut.displayLabel
        }
    }

    var body: some View {
        Button(action: {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            action()
        }) {
            Group {
                if let symbol = sfSymbol {
                    Image(systemName: symbol)
                        .font(.system(size: 15, weight: .medium))
                } else {
                    Text(shortLabel)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                }
            }
            .foregroundStyle(isActive ? Color.brandOrange : iconColor.opacity(0.85))
            .frame(width: 32, height: 32)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct TerminalViewRepresentable: UIViewRepresentable {
    let connectionManager: ConnectionManager
    @ObservedObject var themeManager: ThemeManager
    @Binding var terminalView: TerminalView?

    func makeUIView(context: Context) -> SwiftTerm.TerminalView {
        let terminalView = TerminalView(frame: .zero)

        // Configure terminal appearance from theme
        let theme = themeManager.currentTheme
        terminalView.font = UIFont.monospacedSystemFont(ofSize: themeManager.fontSize, weight: .regular)
        terminalView.nativeForegroundColor = theme.foregroundColor
        terminalView.nativeBackgroundColor = theme.backgroundColor

        // Hide iOS keyboard accessory bar - we have our own toolbar
        terminalView.inputAccessoryView = nil

        // Set up the terminal delegate
        terminalView.terminalDelegate = context.coordinator
        context.coordinator.terminalView = terminalView

        // Become first responder to show keyboard
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            _ = terminalView.becomeFirstResponder()
        }

        // Store reference for toolbar
        DispatchQueue.main.async {
            self.terminalView = terminalView
        }

        return terminalView
    }

    func updateUIView(_ uiView: SwiftTerm.TerminalView, context: Context) {
        // Update coordinator's connection manager reference
        context.coordinator.connectionManager = connectionManager

        // Update theme if changed
        let theme = themeManager.currentTheme
        uiView.font = UIFont.monospacedSystemFont(ofSize: themeManager.fontSize, weight: .regular)
        uiView.nativeForegroundColor = theme.foregroundColor
        uiView.nativeBackgroundColor = theme.backgroundColor
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(connectionManager: connectionManager)
    }

    class Coordinator: NSObject, TerminalViewDelegate {
        var connectionManager: ConnectionManager
        weak var terminalView: TerminalView?
        private var outputObserver: NSObjectProtocol?

        init(connectionManager: ConnectionManager) {
            self.connectionManager = connectionManager
            super.init()

            // Set up output handler
            Task { @MainActor in
                connectionManager.onTerminalOutput = { [weak self] data in
                    self?.terminalView?.feed(text: data)
                }
            }
        }

        deinit {
            if let observer = outputObserver {
                NotificationCenter.default.removeObserver(observer)
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

extension Notification.Name {
    static let terminalOutput = Notification.Name("terminalOutput")
}
