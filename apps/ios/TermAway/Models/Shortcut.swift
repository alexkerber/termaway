import Foundation

struct Shortcut: Identifiable, Codable, Equatable {
    var id: UUID
    var name: String
    var command: String
    var displayLabel: String
    var showInToolbar: Bool

    init(id: UUID = UUID(), name: String, command: String, displayLabel: String, showInToolbar: Bool = true) {
        self.id = id
        self.name = name
        self.command = command
        self.displayLabel = displayLabel
        self.showInToolbar = showInToolbar
    }

    /// Control character helper
    static func controlChar(_ char: Character) -> String {
        let ascii = char.asciiValue ?? 0
        let controlCode = ascii - 64  // 'A' = 65, Ctrl+A = 1
        return String(UnicodeScalar(controlCode))
    }

    /// Default shortcuts for terminal use (ordered by most used first)
    static var defaults: [Shortcut] {
        [
            Shortcut(name: "Tab", command: "\t", displayLabel: "Tab"),
            Shortcut(name: "Right Arrow", command: "\u{1B}[C", displayLabel: "\u{2192}"),
            Shortcut(name: "Left Arrow", command: "\u{1B}[D", displayLabel: "\u{2190}"),
            Shortcut(name: "Up Arrow", command: "\u{1B}[A", displayLabel: "\u{2191}"),
            Shortcut(name: "Down Arrow", command: "\u{1B}[B", displayLabel: "\u{2193}"),
            Shortcut(name: "Ctrl+C", command: controlChar("C"), displayLabel: "^C"),
            Shortcut(name: "Ctrl+R", command: controlChar("R"), displayLabel: "^R"),
            Shortcut(name: "Ctrl+L", command: controlChar("L"), displayLabel: "^L"),
            Shortcut(name: "Ctrl+D", command: controlChar("D"), displayLabel: "^D"),
            Shortcut(name: "Ctrl+Z", command: controlChar("Z"), displayLabel: "^Z"),
            Shortcut(name: "Escape", command: "\u{1B}", displayLabel: "Esc"),
            Shortcut(name: "Ctrl", command: "", displayLabel: "Ctrl"),
        ]
    }
}
