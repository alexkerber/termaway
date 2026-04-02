import SwiftUI

// MARK: - Keyboard Shortcut Actions

/// Actions that keyboard shortcuts can trigger, communicated via environment.
/// Views observe these to respond to hardware keyboard shortcuts on iPad.
@MainActor
class KeyboardShortcutState: ObservableObject {
    @Published var createSessionRequested = false
    @Published var killSessionRequested = false
    @Published var openSettingsRequested = false
    @Published var clearTerminalRequested = false
    @Published var cycleSplitLayoutRequested = false
    @Published var focusNextPaneRequested = false
    @Published var focusPreviousPaneRequested = false
    @Published var switchToSessionIndex: Int? = nil
    @Published var findInTerminalRequested = false
}

// MARK: - App Commands

/// Hardware keyboard shortcuts for iPad power users.
/// These appear in the Cmd-hold keyboard shortcut overlay.
struct KeyboardShortcutCommands: Commands {
    @ObservedObject var connectionManager: ConnectionManager
    @ObservedObject var shortcutState: KeyboardShortcutState

    var body: some Commands {
        // Replace the default "New" command group
        CommandGroup(replacing: .newItem) {
            Button("New Window") {
                shortcutState.createSessionRequested = true
            }
            .keyboardShortcut("t", modifiers: .command)
            .disabled(!connectionManager.isConnected || !connectionManager.isAuthenticated)
        }

        // Session commands
        CommandGroup(after: .newItem) {
            Button("Close Window") {
                shortcutState.killSessionRequested = true
            }
            .keyboardShortcut("w", modifiers: .command)
            .disabled(connectionManager.currentSession == nil)

            Divider()

            // Cmd+1 through Cmd+9: Switch to session by index
            ForEach(1...9, id: \.self) { index in
                Button("Switch to Window \(index)") {
                    shortcutState.switchToSessionIndex = index
                }
                .keyboardShortcut(KeyEquivalent(Character("\(index)")), modifiers: .command)
                .disabled(index > connectionManager.sessions.count)
            }
        }

        // Utility commands
        CommandGroup(after: .pasteboard) {
            Button("Clear Terminal") {
                shortcutState.clearTerminalRequested = true
            }
            .keyboardShortcut("k", modifiers: .command)
            .disabled(connectionManager.currentSession == nil)

            Button("Find in Terminal") {
                shortcutState.findInTerminalRequested = true
            }
            .keyboardShortcut("f", modifiers: .command)
            .disabled(connectionManager.currentSession == nil)
        }

        // Settings / Preferences
        CommandGroup(replacing: .appSettings) {
            Button("Settings...") {
                shortcutState.openSettingsRequested = true
            }
            .keyboardShortcut(",", modifiers: .command)
        }

        // Split pane commands (iPad)
        CommandMenu("Panes") {
            Button("Cycle Layout") {
                shortcutState.cycleSplitLayoutRequested = true
            }
            .keyboardShortcut("\\", modifiers: .command)

            Divider()

            Button("Focus Next Pane") {
                shortcutState.focusNextPaneRequested = true
            }
            .keyboardShortcut("]", modifiers: .command)

            Button("Focus Previous Pane") {
                shortcutState.focusPreviousPaneRequested = true
            }
            .keyboardShortcut("[", modifiers: .command)
        }
    }
}

// MARK: - Shortcut Handler Modifier

/// Modifier that listens for keyboard shortcut state changes and executes actions.
/// Attach this to the main content view that has access to all managers.
struct KeyboardShortcutHandler: ViewModifier {
    @ObservedObject var shortcutState: KeyboardShortcutState
    @EnvironmentObject var connectionManager: ConnectionManager
    @EnvironmentObject var splitPaneManager: SplitPaneManager

    @Binding var showingNewSession: Bool
    @Binding var showingSettings: Bool
    @Binding var showingKillConfirmation: Bool

    func body(content: Content) -> some View {
        content
            .onChange(of: shortcutState.createSessionRequested) { _, newValue in
                if newValue {
                    shortcutState.createSessionRequested = false
                    showingNewSession = true
                }
            }
            .onChange(of: shortcutState.killSessionRequested) { _, newValue in
                if newValue {
                    shortcutState.killSessionRequested = false
                    guard connectionManager.currentSession != nil else { return }
                    showingKillConfirmation = true
                }
            }
            .onChange(of: shortcutState.openSettingsRequested) { _, newValue in
                if newValue {
                    shortcutState.openSettingsRequested = false
                    showingSettings = true
                }
            }
            .onChange(of: shortcutState.clearTerminalRequested) { _, newValue in
                if newValue {
                    shortcutState.clearTerminalRequested = false
                    // Send "clear" + Enter to the active session
                    if let sessionName = connectionManager.activeSessionName ?? connectionManager.currentSession?.name {
                        connectionManager.sendInput("clear\n", to: sessionName)
                    }
                }
            }
            .onChange(of: shortcutState.findInTerminalRequested) { _, newValue in
                if newValue {
                    shortcutState.findInTerminalRequested = false
                    // Cmd+F: Toggle terminal search bar
                    NotificationCenter.default.post(name: .toggleTerminalSearch, object: nil)
                }
            }
            .onChange(of: shortcutState.cycleSplitLayoutRequested) { _, newValue in
                if newValue {
                    shortcutState.cycleSplitLayoutRequested = false
                    let nextLayout = splitPaneManager.cycleLayout()
                    cycleSplitLayout(to: nextLayout)
                }
            }
            .onChange(of: shortcutState.focusNextPaneRequested) { _, newValue in
                if newValue {
                    shortcutState.focusNextPaneRequested = false
                    splitPaneManager.focusNextPane()
                    // Update active session for input routing
                    if let sessionName = splitPaneManager.focusedSessionName {
                        connectionManager.setActiveSession(sessionName)
                    }
                }
            }
            .onChange(of: shortcutState.focusPreviousPaneRequested) { _, newValue in
                if newValue {
                    shortcutState.focusPreviousPaneRequested = false
                    splitPaneManager.focusPreviousPane()
                    if let sessionName = splitPaneManager.focusedSessionName {
                        connectionManager.setActiveSession(sessionName)
                    }
                }
            }
            .onChange(of: shortcutState.switchToSessionIndex) { _, newValue in
                if let index = newValue {
                    shortcutState.switchToSessionIndex = nil
                    let sessions = connectionManager.sessions
                    guard index >= 1, index <= sessions.count else { return }
                    let session = sessions[index - 1]
                    connectionManager.attachToSession(session.name)
                    if UIDevice.current.userInterfaceIdiom == .pad {
                        splitPaneManager.attachSessionToFocused(session.name)
                        connectionManager.setActiveSession(session.name)
                    }
                }
            }
    }

    /// Cycle to the given layout, creating pane sessions as needed (mirrors SplitPaneMenuButton logic)
    private func cycleSplitLayout(to newLayout: SplitLayout) {
        let currentPaneCount = splitPaneManager.panes.count
        let neededPaneCount = newLayout.paneCount
        let newPanesNeeded = max(0, neededPaneCount - currentPaneCount)

        let baseSessionName = splitPaneManager.focusedSessionName
            ?? connectionManager.currentSession?.name ?? "Window"

        var newSessionNames: [String] = []
        for i in 0..<newPanesNeeded {
            let paneNumber = currentPaneCount + i + 1
            let newName = "\(baseSessionName)-\(paneNumber)"
            newSessionNames.append(newName)
            connectionManager.createPaneSession(newName)
        }

        splitPaneManager.changeLayout(to: newLayout)

        let newPanes = Array(splitPaneManager.panes.suffix(newPanesNeeded))
        for (index, pane) in newPanes.enumerated() {
            if index < newSessionNames.count {
                splitPaneManager.attachSession(newSessionNames[index], to: pane.id)
            }
        }
    }
}

extension View {
    func keyboardShortcutHandler(
        shortcutState: KeyboardShortcutState,
        showingNewSession: Binding<Bool>,
        showingSettings: Binding<Bool>,
        showingKillConfirmation: Binding<Bool>
    ) -> some View {
        modifier(KeyboardShortcutHandler(
            shortcutState: shortcutState,
            showingNewSession: showingNewSession,
            showingSettings: showingSettings,
            showingKillConfirmation: showingKillConfirmation
        ))
    }
}
