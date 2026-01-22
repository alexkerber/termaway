import Foundation
import SwiftUI
import Combine

// MARK: - Pane Model

/// Represents a single terminal pane in a split view
struct TerminalPane: Identifiable, Equatable {
    let id: UUID
    var sessionName: String?  // nil if no session attached

    init(id: UUID = UUID(), sessionName: String? = nil) {
        self.id = id
        self.sessionName = sessionName
    }
}

// MARK: - Split Layout

/// Defines how panes are arranged
enum SplitLayout: String, Codable, CaseIterable {
    case single          // One pane (no split)
    case horizontal      // Two panes side by side
    case vertical        // Two panes stacked
    case tripleVertical  // Three panes stacked
    case grid            // Four panes (2x2)

    var paneCount: Int {
        switch self {
        case .single: return 1
        case .horizontal, .vertical: return 2
        case .tripleVertical: return 3
        case .grid: return 4
        }
    }

    var icon: String {
        switch self {
        case .single: return "rectangle"
        case .horizontal: return "rectangle.split.2x1"
        case .vertical: return "rectangle.split.1x2"
        case .tripleVertical: return "3.square"
        case .grid: return "rectangle.split.2x2"
        }
    }

    var displayName: String {
        switch self {
        case .single: return "Single"
        case .horizontal: return "Horizontal"
        case .vertical: return "Vertical"
        case .tripleVertical: return "Vertical × 3"
        case .grid: return "Grid"
        }
    }
}

// MARK: - Split Pane Manager

/// Manages the layout and state of terminal panes for iPad split view.
/// Each pane can display a DIFFERENT session. Layout is stored globally.
@MainActor
class SplitPaneManager: ObservableObject {
    @Published var layout: SplitLayout = .single
    @Published var panes: [TerminalPane] = [TerminalPane()]
    @Published var focusedPaneId: UUID?

    /// Get the session name of the focused pane
    var focusedSessionName: String? {
        focusedPane?.sessionName
    }

    /// Current session name (for layout storage purposes)
    private var currentSessionName: String?

    /// Flag to prevent saves during session transitions
    private var isTransitioningSession = false

    private let layoutsKey = "sessionLayouts"
    private let paneSessionsKey = "sessionPaneSessions"

    /// Callback to create ephemeral sessions when restoring a layout
    var onNeedCreatePaneSessions: (([String]) -> Void)?

    init() {
        // Start with single pane, layout will be set when session is selected
        if let firstPane = panes.first {
            focusedPaneId = firstPane.id
        }
    }

    // MARK: - Session Layout Management

    /// Called when switching to a session - restores saved layout if any
    func setCurrentSession(_ sessionName: String) {
        // Only process if actually switching sessions
        guard currentSessionName != sessionName else {
            print("SplitPaneManager: Same session '\(sessionName)', skipping")
            return
        }

        print("SplitPaneManager: Switching from '\(currentSessionName ?? "nil")' to '\(sessionName)'")

        // Set flag to prevent spurious saves during transition
        isTransitioningSession = true

        // Save current layout before switching (if we have a current session)
        if currentSessionName != nil {
            saveCurrentLayout()
            savePaneSessions(force: true)  // Force save before transition
        }

        currentSessionName = sessionName

        // Load saved layout for this session
        let savedLayout = loadLayout(for: sessionName)
        var savedPaneSessions = loadPaneSessions(for: sessionName)

        // Validate saved data: pane[0] should match sessionName or be empty
        if !savedPaneSessions.isEmpty {
            let firstPaneSession = savedPaneSessions[0]
            if !firstPaneSession.isEmpty && firstPaneSession != sessionName {
                print("SplitPaneManager: WARNING - Corrupted data! First pane '\(firstPaneSession)' != session '\(sessionName)', fixing")
                savedPaneSessions[0] = sessionName
                // Save the corrected data
                var allPaneSessions = loadAllPaneSessions()
                allPaneSessions[sessionName] = savedPaneSessions
                UserDefaults.standard.set(allPaneSessions, forKey: paneSessionsKey)
            }
        }

        if savedLayout != .single && savedPaneSessions.count == savedLayout.paneCount {
            // Restore saved layout with its pane sessions in a single atomic update
            print("SplitPaneManager: Restoring \(savedLayout) layout with \(savedPaneSessions.count) panes")

            // Build panes with sessions already assigned (avoids intermediate SwiftUI states)
            var newPanes: [TerminalPane] = []
            for paneSessionName in savedPaneSessions {
                var pane = TerminalPane()
                pane.sessionName = paneSessionName.isEmpty ? nil : paneSessionName
                newPanes.append(pane)
            }

            // Single atomic update to panes and layout
            panes = newPanes
            focusedPaneId = panes.first?.id
            layout = savedLayout

            // Request creation of ephemeral sessions (they may have been killed)
            let ephemeralSessions = savedPaneSessions.dropFirst().filter { !$0.isEmpty }
            if !ephemeralSessions.isEmpty {
                onNeedCreatePaneSessions?(Array(ephemeralSessions))
            }

            print("SplitPaneManager: Restored '\(sessionName)' with \(savedLayout) layout")
        } else {
            // No saved layout or single pane - use single layout
            if layout != .single {
                applyLayout(.single)
            }
            // Directly set pane session without triggering save (we'll save at end)
            if let index = panes.firstIndex(where: { $0.id == focusedPaneId }) {
                panes[index].sessionName = sessionName
            }
            print("SplitPaneManager: Assigned '\(sessionName)' to focused pane (single layout)")
        }

        // End transition and save final state
        isTransitioningSession = false
        savePaneSessions(force: true)
    }

    /// Save current layout for the current session
    func saveCurrentLayout() {
        guard let sessionName = currentSessionName else { return }
        saveLayout(for: sessionName)
    }

    // MARK: - Persistence

    private func saveLayout(for sessionName: String) {
        var layouts = loadAllLayouts()
        layouts[sessionName] = layout.rawValue
        UserDefaults.standard.set(layouts, forKey: layoutsKey)
    }

    private func loadLayout(for sessionName: String) -> SplitLayout {
        let layouts = loadAllLayouts()
        guard let rawValue = layouts[sessionName],
              let savedLayout = SplitLayout(rawValue: rawValue) else {
            return .single
        }
        return savedLayout
    }

    private func loadAllLayouts() -> [String: String] {
        UserDefaults.standard.dictionary(forKey: layoutsKey) as? [String: String] ?? [:]
    }

    /// Save pane session names for the current session
    func savePaneSessions(force: Bool = false) {
        guard let sessionName = currentSessionName else { return }

        // Skip saves during session transitions unless forced
        if isTransitioningSession && !force {
            print("SplitPaneManager: Skipping save during transition")
            return
        }

        let sessionNames = panes.map { $0.sessionName ?? "" }

        // Validate: first pane should match currentSessionName or be empty
        // This prevents saving corrupted data from SwiftUI race conditions
        if !sessionNames.isEmpty {
            let firstPaneSession = sessionNames[0]
            if !firstPaneSession.isEmpty && firstPaneSession != sessionName && !firstPaneSession.hasPrefix(sessionName + "-") {
                // First pane has a session from a different window - don't save this corrupted state
                print("SplitPaneManager: BLOCKED corrupt save! First pane '\(firstPaneSession)' doesn't match session '\(sessionName)'")
                return
            }
        }

        var allPaneSessions = loadAllPaneSessions()
        allPaneSessions[sessionName] = sessionNames
        UserDefaults.standard.set(allPaneSessions, forKey: paneSessionsKey)
        print("SplitPaneManager: Saved panes for '\(sessionName)': \(sessionNames)")
    }

    private func loadPaneSessions(for sessionName: String) -> [String] {
        let allPaneSessions = loadAllPaneSessions()
        return allPaneSessions[sessionName] ?? []
    }

    private func loadAllPaneSessions() -> [String: [String]] {
        UserDefaults.standard.dictionary(forKey: paneSessionsKey) as? [String: [String]] ?? [:]
    }

    /// Clear saved layout data for a session (call when session is killed/exits)
    func clearSavedLayout(for sessionName: String) {
        print("SplitPaneManager: Clearing saved layout for '\(sessionName)'")

        // Remove layout
        var layouts = loadAllLayouts()
        layouts.removeValue(forKey: sessionName)
        UserDefaults.standard.set(layouts, forKey: layoutsKey)

        // Remove pane sessions
        var paneSessions = loadAllPaneSessions()
        paneSessions.removeValue(forKey: sessionName)
        UserDefaults.standard.set(paneSessions, forKey: paneSessionsKey)
    }

    /// Apply a layout (update panes and layout property)
    private func applyLayout(_ newLayout: SplitLayout) {
        let neededPanes = newLayout.paneCount

        // Reset panes for the new layout
        var newPanes: [TerminalPane] = []
        for _ in 0..<neededPanes {
            newPanes.append(TerminalPane())
        }
        panes = newPanes
        focusedPaneId = panes.first?.id
        layout = newLayout
    }

    // MARK: - Pane Management

    /// Get the currently focused pane
    var focusedPane: TerminalPane? {
        panes.first { $0.id == focusedPaneId }
    }

    /// Focus a specific pane
    func focus(paneId: UUID) {
        focusedPaneId = paneId
    }

    /// Attach a session to a pane
    func attachSession(_ sessionName: String, to paneId: UUID) {
        guard let currentSession = currentSessionName else { return }

        // Validate: the session being attached should belong to current window's family
        // (either the main session name or an ephemeral like "Name-2", "Name-3")
        let isMainSession = sessionName == currentSession
        let isEphemeralSession = sessionName.hasPrefix(currentSession + "-")

        if !isMainSession && !isEphemeralSession {
            // This is a session from a different window - likely a SwiftUI race condition
            print("SplitPaneManager: BLOCKED attaching '\(sessionName)' - doesn't belong to current window '\(currentSession)'")
            return
        }

        if let index = panes.firstIndex(where: { $0.id == paneId }) {
            panes[index].sessionName = sessionName
            savePaneSessions()
        }
    }

    /// Attach session to focused pane
    func attachSessionToFocused(_ sessionName: String) {
        if let paneId = focusedPaneId {
            attachSession(sessionName, to: paneId)
        }
    }

    /// Get pane by ID
    func pane(id: UUID) -> TerminalPane? {
        panes.first { $0.id == id }
    }

    // MARK: - Layout Changes

    /// Split horizontally (add pane to the right)
    func splitHorizontal() {
        guard layout == .single else {
            if layout == .vertical {
                changeLayout(to: .grid)
            }
            return
        }
        changeLayout(to: .horizontal)
    }

    /// Split vertically (add pane below)
    func splitVertical() {
        guard layout == .single else {
            if layout == .horizontal {
                changeLayout(to: .grid)
            }
            return
        }
        changeLayout(to: .vertical)
    }

    /// Change to a specific layout
    func changeLayout(to newLayout: SplitLayout) {
        let neededPanes = newLayout.paneCount

        // Add panes if needed - NEW panes start EMPTY so user can select different sessions
        while panes.count < neededPanes {
            let newPane = TerminalPane()  // No session - user picks from sidebar
            panes.append(newPane)
        }

        // Remove excess panes (from the end)
        if panes.count > neededPanes {
            panes = Array(panes.prefix(neededPanes))
        }

        // Ensure focus is on a valid pane
        if focusedPaneId == nil || !panes.contains(where: { $0.id == focusedPaneId }) {
            focusedPaneId = panes.first?.id
        }

        layout = newLayout
        saveCurrentLayout()
        savePaneSessions()
    }

    /// Close a specific pane
    func closePane(id: UUID) {
        guard panes.count > 1 else { return }

        // Remove the pane
        panes.removeAll { $0.id == id }

        // Update layout based on remaining panes
        switch panes.count {
        case 1:
            layout = .single
        case 2:
            // From grid or tripleVertical, go to vertical
            if layout == .grid || layout == .tripleVertical {
                layout = .vertical
            }
        case 3:
            // From grid, go to tripleVertical
            if layout == .grid {
                layout = .tripleVertical
            }
        default:
            break
        }

        // Update focus if needed
        if focusedPaneId == id {
            focusedPaneId = panes.first?.id
        }
    }

    /// Close the focused pane
    func closeFocusedPane() {
        if let paneId = focusedPaneId {
            closePane(id: paneId)
        }
    }

    /// Reset to single pane
    func resetToSingle() {
        let keepId = focusedPaneId ?? panes.first?.id

        if let keepId = keepId, let keptPane = panes.first(where: { $0.id == keepId }) {
            panes = [keptPane]
        } else {
            panes = [TerminalPane()]
        }

        layout = .single
        focusedPaneId = panes.first?.id
    }

    // MARK: - Session Queries

    /// Get all unique session names across panes
    var activeSessions: Set<String> {
        Set(panes.compactMap { $0.sessionName })
    }

    /// Check if a session is displayed in any pane
    func isSessionDisplayed(_ sessionName: String) -> Bool {
        panes.contains { $0.sessionName == sessionName }
    }

    /// Get panes displaying a specific session
    func panes(for sessionName: String) -> [TerminalPane] {
        panes.filter { $0.sessionName == sessionName }
    }
}
