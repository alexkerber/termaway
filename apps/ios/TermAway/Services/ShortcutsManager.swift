import Foundation
import Combine

@MainActor
class ShortcutsManager: ObservableObject {
    @Published var shortcuts: [Shortcut] = []
    @Published var ctrlModeActive: Bool = false

    private let shortcutsKey = "savedShortcuts"

    // Toolbar visibility setting
    var showToolbar: Bool {
        get {
            // Default to true if not set
            if UserDefaults.standard.object(forKey: "showShortcutsToolbar") == nil {
                return true
            }
            return UserDefaults.standard.bool(forKey: "showShortcutsToolbar")
        }
        set {
            UserDefaults.standard.set(newValue, forKey: "showShortcutsToolbar")
            objectWillChange.send()
        }
    }

    init() {
        loadShortcuts()
    }

    // MARK: - Persistence

    private func loadShortcuts() {
        if let data = UserDefaults.standard.data(forKey: shortcutsKey),
           let decoded = try? JSONDecoder().decode([Shortcut].self, from: data) {
            shortcuts = decoded
        } else {
            // First launch - use defaults
            shortcuts = Shortcut.defaults
            saveShortcuts()
        }
    }

    private func saveShortcuts() {
        if let encoded = try? JSONEncoder().encode(shortcuts) {
            UserDefaults.standard.set(encoded, forKey: shortcutsKey)
        }
    }

    // MARK: - CRUD Operations

    func addShortcut(_ shortcut: Shortcut) {
        shortcuts.append(shortcut)
        saveShortcuts()
    }

    func updateShortcut(_ shortcut: Shortcut) {
        if let index = shortcuts.firstIndex(where: { $0.id == shortcut.id }) {
            shortcuts[index] = shortcut
            saveShortcuts()
        }
    }

    func deleteShortcut(at offsets: IndexSet) {
        shortcuts.remove(atOffsets: offsets)
        saveShortcuts()
    }

    func deleteShortcut(_ shortcut: Shortcut) {
        shortcuts.removeAll { $0.id == shortcut.id }
        saveShortcuts()
    }

    func moveShortcut(from source: IndexSet, to destination: Int) {
        shortcuts.move(fromOffsets: source, toOffset: destination)
        saveShortcuts()
    }

    func resetToDefaults() {
        shortcuts = Shortcut.defaults
        saveShortcuts()
    }

    // MARK: - Toolbar Shortcuts

    var toolbarShortcuts: [Shortcut] {
        shortcuts.filter { $0.showInToolbar }
    }

    // MARK: - Command Execution

    func getCommand(for shortcut: Shortcut) -> String? {
        // Handle Ctrl modifier
        if shortcut.name == "Ctrl" {
            ctrlModeActive.toggle()
            return nil
        }

        // If Ctrl mode is active, wrap the command
        if ctrlModeActive {
            ctrlModeActive = false
            // If shortcut.command is a single character, convert to control character
            if shortcut.command.count == 1, let char = shortcut.command.uppercased().first {
                return Shortcut.controlChar(char)
            }
        }

        return shortcut.command
    }
}
