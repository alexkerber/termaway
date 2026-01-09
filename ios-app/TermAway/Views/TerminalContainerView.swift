import SwiftUI
import SwiftTerm

struct TerminalContainerView: View {
    @EnvironmentObject var connectionManager: ConnectionManager
    @EnvironmentObject var shortcutsManager: ShortcutsManager
    let session: Session
    @State private var terminalView: TerminalView?
    @State private var showingShortcutsSettings = false

    var body: some View {
        VStack(spacing: 0) {
            TerminalViewRepresentable(
                connectionManager: connectionManager,
                terminalView: $terminalView
            )
            .ignoresSafeArea(.keyboard)

            if terminalView != nil {
                ShortcutsToolbarView(
                    terminalView: $terminalView,
                    showingSettings: $showingShortcutsSettings
                )
            }
        }
        .sheet(isPresented: $showingShortcutsSettings) {
            ShortcutsSettingsView()
        }
    }
}

// MARK: - Shortcuts Toolbar
struct ShortcutsToolbarView: View {
    @EnvironmentObject var shortcutsManager: ShortcutsManager
    @Binding var terminalView: TerminalView?
    @Binding var showingSettings: Bool

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(shortcutsManager.toolbarShortcuts) { shortcut in
                    ToolbarKey(
                        label: shortcut.displayLabel,
                        icon: nil,
                        isActive: shortcutsManager.ctrlModeActive && shortcut.name == "Ctrl"
                    ) {
                        handleShortcut(shortcut)
                    }
                }

                ToolbarDivider()

                // Settings button
                ToolbarKey(label: nil, icon: "gearshape") {
                    showingSettings = true
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
        .background(
            Color(red: 0.08, green: 0.09, blue: 0.11)
                .shadow(color: .black.opacity(0.5), radius: 8, y: -4)
        )
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

struct ToolbarKey: View {
    let label: String?
    let icon: String?
    var isActive: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            action()
        }) {
            Group {
                if let icon = icon {
                    Image(systemName: icon)
                        .font(.system(size: 14, weight: .medium))
                } else if let label = label {
                    Text(label)
                        .font(.system(size: 13, weight: .semibold, design: .monospaced))
                }
            }
            .foregroundColor(isActive ? .black : .white.opacity(0.9))
            .frame(minWidth: 44, minHeight: 36)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(
                        isActive
                            ? LinearGradient(
                                colors: [Color.cyan, Color.blue],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                            : LinearGradient(
                                colors: [
                                    Color(red: 0.22, green: 0.24, blue: 0.28),
                                    Color(red: 0.14, green: 0.16, blue: 0.20)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(
                        isActive ? Color.white.opacity(0.3) : Color.white.opacity(0.1),
                        lineWidth: 1
                    )
            )
            .shadow(color: .black.opacity(0.4), radius: 2, y: 2)
        }
        .buttonStyle(.plain)
    }
}

struct ToolbarDivider: View {
    var body: some View {
        Rectangle()
            .fill(Color.white.opacity(0.15))
            .frame(width: 1, height: 24)
            .padding(.horizontal, 4)
    }
}

struct TerminalViewRepresentable: UIViewRepresentable {
    let connectionManager: ConnectionManager
    @Binding var terminalView: TerminalView?

    func makeUIView(context: Context) -> SwiftTerm.TerminalView {
        let terminalView = TerminalView(frame: .zero)

        // Configure terminal appearance
        terminalView.font = UIFont.monospacedSystemFont(ofSize: 14, weight: .regular)
        terminalView.nativeForegroundColor = UIColor(red: 0.9, green: 0.93, blue: 0.95, alpha: 1.0)
        terminalView.nativeBackgroundColor = UIColor(red: 0.05, green: 0.07, blue: 0.09, alpha: 1.0)

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
