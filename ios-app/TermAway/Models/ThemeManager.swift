import SwiftUI
import Combine

/// A terminal color theme with all necessary colors for rendering
struct TerminalTheme: Identifiable, Codable, Equatable {
    let id: String
    let name: String
    let background: CodableColor
    let foreground: CodableColor
    let cursor: CodableColor
    let ansiColors: [CodableColor] // 16 ANSI colors (0-7 normal, 8-15 bright)

    /// Preview colors for the theme selector
    var previewColors: [Color] {
        [background.color, foreground.color, ansiColors[1].color, ansiColors[2].color, ansiColors[4].color, ansiColors[5].color]
    }
}

/// A color that can be encoded/decoded for UserDefaults storage
struct CodableColor: Codable, Equatable {
    let red: Double
    let green: Double
    let blue: Double
    let alpha: Double

    init(red: Double, green: Double, blue: Double, alpha: Double = 1.0) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    init(_ uiColor: UIColor) {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        uiColor.getRed(&r, green: &g, blue: &b, alpha: &a)
        self.red = Double(r)
        self.green = Double(g)
        self.blue = Double(b)
        self.alpha = Double(a)
    }

    var color: Color {
        Color(red: red, green: green, blue: blue, opacity: alpha)
    }

    var uiColor: UIColor {
        UIColor(red: CGFloat(red), green: CGFloat(green), blue: CGFloat(blue), alpha: CGFloat(alpha))
    }
}

/// Manages terminal themes and persists user preferences
class ThemeManager: ObservableObject {
    static let shared = ThemeManager()

    @Published var currentTheme: TerminalTheme {
        didSet {
            saveCurrentTheme()
        }
    }

    @Published var fontSize: CGFloat {
        didSet {
            UserDefaults.standard.set(fontSize, forKey: "terminalFontSize")
        }
    }

    let builtInThemes: [TerminalTheme]

    private init() {
        self.builtInThemes = ThemeManager.createBuiltInThemes()

        // Load saved font size or default to 14
        self.fontSize = CGFloat(UserDefaults.standard.double(forKey: "terminalFontSize"))
        if self.fontSize < 10 || self.fontSize > 24 {
            self.fontSize = 14
        }

        // Load saved theme or default to first theme
        if let themeId = UserDefaults.standard.string(forKey: "selectedThemeId"),
           let theme = self.builtInThemes.first(where: { $0.id == themeId }) {
            self.currentTheme = theme
        } else {
            self.currentTheme = self.builtInThemes[0]
        }
    }

    private func saveCurrentTheme() {
        UserDefaults.standard.set(currentTheme.id, forKey: "selectedThemeId")
    }

    private static func createBuiltInThemes() -> [TerminalTheme] {
        [
            // Default Dark
            TerminalTheme(
                id: "default-dark",
                name: "Default Dark",
                background: CodableColor(red: 0.05, green: 0.07, blue: 0.09),
                foreground: CodableColor(red: 0.9, green: 0.93, blue: 0.95),
                cursor: CodableColor(red: 0.9, green: 0.93, blue: 0.95),
                ansiColors: [
                    CodableColor(red: 0.28, green: 0.31, blue: 0.35), // black
                    CodableColor(red: 1.0, green: 0.48, blue: 0.45),  // red
                    CodableColor(red: 0.25, green: 0.73, blue: 0.31), // green
                    CodableColor(red: 0.83, green: 0.60, blue: 0.13), // yellow
                    CodableColor(red: 0.35, green: 0.65, blue: 1.0),  // blue
                    CodableColor(red: 0.74, green: 0.55, blue: 1.0),  // magenta
                    CodableColor(red: 0.22, green: 0.77, blue: 0.81), // cyan
                    CodableColor(red: 0.69, green: 0.73, blue: 0.77), // white
                    CodableColor(red: 0.43, green: 0.46, blue: 0.50), // bright black
                    CodableColor(red: 1.0, green: 0.63, blue: 0.60),  // bright red
                    CodableColor(red: 0.34, green: 0.83, blue: 0.39), // bright green
                    CodableColor(red: 0.89, green: 0.70, blue: 0.26), // bright yellow
                    CodableColor(red: 0.47, green: 0.75, blue: 1.0),  // bright blue
                    CodableColor(red: 0.82, green: 0.66, blue: 1.0),  // bright magenta
                    CodableColor(red: 0.34, green: 0.83, blue: 0.87), // bright cyan
                    CodableColor(red: 0.94, green: 0.96, blue: 0.98), // bright white
                ]
            ),

            // Light
            TerminalTheme(
                id: "light",
                name: "Light",
                background: CodableColor(red: 1.0, green: 1.0, blue: 1.0),
                foreground: CodableColor(red: 0.15, green: 0.15, blue: 0.15),
                cursor: CodableColor(red: 0.15, green: 0.15, blue: 0.15),
                ansiColors: [
                    CodableColor(red: 0.0, green: 0.0, blue: 0.0),    // black
                    CodableColor(red: 0.77, green: 0.11, blue: 0.11), // red
                    CodableColor(red: 0.10, green: 0.52, blue: 0.10), // green
                    CodableColor(red: 0.60, green: 0.47, blue: 0.0),  // yellow
                    CodableColor(red: 0.11, green: 0.37, blue: 0.80), // blue
                    CodableColor(red: 0.55, green: 0.20, blue: 0.60), // magenta
                    CodableColor(red: 0.10, green: 0.52, blue: 0.52), // cyan
                    CodableColor(red: 0.90, green: 0.90, blue: 0.90), // white
                    CodableColor(red: 0.35, green: 0.35, blue: 0.35), // bright black
                    CodableColor(red: 0.90, green: 0.25, blue: 0.25), // bright red
                    CodableColor(red: 0.20, green: 0.65, blue: 0.20), // bright green
                    CodableColor(red: 0.75, green: 0.60, blue: 0.0),  // bright yellow
                    CodableColor(red: 0.20, green: 0.50, blue: 0.95), // bright blue
                    CodableColor(red: 0.70, green: 0.35, blue: 0.75), // bright magenta
                    CodableColor(red: 0.20, green: 0.65, blue: 0.65), // bright cyan
                    CodableColor(red: 1.0, green: 1.0, blue: 1.0),    // bright white
                ]
            ),

            // Solarized Dark
            TerminalTheme(
                id: "solarized-dark",
                name: "Solarized Dark",
                background: CodableColor(red: 0.0, green: 0.169, blue: 0.212),
                foreground: CodableColor(red: 0.514, green: 0.580, blue: 0.588),
                cursor: CodableColor(red: 0.514, green: 0.580, blue: 0.588),
                ansiColors: [
                    CodableColor(red: 0.027, green: 0.212, blue: 0.259),
                    CodableColor(red: 0.863, green: 0.196, blue: 0.184),
                    CodableColor(red: 0.522, green: 0.600, blue: 0.0),
                    CodableColor(red: 0.710, green: 0.537, blue: 0.0),
                    CodableColor(red: 0.149, green: 0.545, blue: 0.824),
                    CodableColor(red: 0.827, green: 0.212, blue: 0.510),
                    CodableColor(red: 0.165, green: 0.631, blue: 0.596),
                    CodableColor(red: 0.933, green: 0.910, blue: 0.835),
                    CodableColor(red: 0.0, green: 0.169, blue: 0.212),
                    CodableColor(red: 0.796, green: 0.294, blue: 0.086),
                    CodableColor(red: 0.345, green: 0.431, blue: 0.459),
                    CodableColor(red: 0.396, green: 0.482, blue: 0.514),
                    CodableColor(red: 0.514, green: 0.580, blue: 0.588),
                    CodableColor(red: 0.424, green: 0.443, blue: 0.769),
                    CodableColor(red: 0.576, green: 0.631, blue: 0.631),
                    CodableColor(red: 0.992, green: 0.965, blue: 0.890),
                ]
            ),

            // Solarized Light
            TerminalTheme(
                id: "solarized-light",
                name: "Solarized Light",
                background: CodableColor(red: 0.992, green: 0.965, blue: 0.890),
                foreground: CodableColor(red: 0.396, green: 0.482, blue: 0.514),
                cursor: CodableColor(red: 0.396, green: 0.482, blue: 0.514),
                ansiColors: [
                    CodableColor(red: 0.933, green: 0.910, blue: 0.835),
                    CodableColor(red: 0.863, green: 0.196, blue: 0.184),
                    CodableColor(red: 0.522, green: 0.600, blue: 0.0),
                    CodableColor(red: 0.710, green: 0.537, blue: 0.0),
                    CodableColor(red: 0.149, green: 0.545, blue: 0.824),
                    CodableColor(red: 0.827, green: 0.212, blue: 0.510),
                    CodableColor(red: 0.165, green: 0.631, blue: 0.596),
                    CodableColor(red: 0.027, green: 0.212, blue: 0.259),
                    CodableColor(red: 0.992, green: 0.965, blue: 0.890),
                    CodableColor(red: 0.796, green: 0.294, blue: 0.086),
                    CodableColor(red: 0.576, green: 0.631, blue: 0.631),
                    CodableColor(red: 0.514, green: 0.580, blue: 0.588),
                    CodableColor(red: 0.396, green: 0.482, blue: 0.514),
                    CodableColor(red: 0.424, green: 0.443, blue: 0.769),
                    CodableColor(red: 0.345, green: 0.431, blue: 0.459),
                    CodableColor(red: 0.0, green: 0.169, blue: 0.212),
                ]
            ),

            // Dracula
            TerminalTheme(
                id: "dracula",
                name: "Dracula",
                background: CodableColor(red: 0.157, green: 0.165, blue: 0.212),
                foreground: CodableColor(red: 0.973, green: 0.973, blue: 0.949),
                cursor: CodableColor(red: 0.973, green: 0.973, blue: 0.949),
                ansiColors: [
                    CodableColor(red: 0.267, green: 0.278, blue: 0.353),
                    CodableColor(red: 1.0, green: 0.333, blue: 0.333),
                    CodableColor(red: 0.314, green: 0.980, blue: 0.482),
                    CodableColor(red: 0.945, green: 0.980, blue: 0.549),
                    CodableColor(red: 0.741, green: 0.576, blue: 0.976),
                    CodableColor(red: 1.0, green: 0.475, blue: 0.776),
                    CodableColor(red: 0.545, green: 0.914, blue: 0.992),
                    CodableColor(red: 0.973, green: 0.973, blue: 0.949),
                    CodableColor(red: 0.388, green: 0.400, blue: 0.482),
                    CodableColor(red: 1.0, green: 0.475, blue: 0.475),
                    CodableColor(red: 0.455, green: 0.992, blue: 0.600),
                    CodableColor(red: 0.969, green: 0.992, blue: 0.667),
                    CodableColor(red: 0.827, green: 0.706, blue: 0.988),
                    CodableColor(red: 1.0, green: 0.600, blue: 0.851),
                    CodableColor(red: 0.667, green: 0.941, blue: 0.996),
                    CodableColor(red: 1.0, green: 1.0, blue: 1.0),
                ]
            ),

            // Nord
            TerminalTheme(
                id: "nord",
                name: "Nord",
                background: CodableColor(red: 0.180, green: 0.204, blue: 0.251),
                foreground: CodableColor(red: 0.925, green: 0.937, blue: 0.957),
                cursor: CodableColor(red: 0.925, green: 0.937, blue: 0.957),
                ansiColors: [
                    CodableColor(red: 0.231, green: 0.259, blue: 0.322),
                    CodableColor(red: 0.749, green: 0.380, blue: 0.416),
                    CodableColor(red: 0.639, green: 0.745, blue: 0.549),
                    CodableColor(red: 0.922, green: 0.796, blue: 0.545),
                    CodableColor(red: 0.506, green: 0.631, blue: 0.757),
                    CodableColor(red: 0.706, green: 0.557, blue: 0.678),
                    CodableColor(red: 0.533, green: 0.753, blue: 0.816),
                    CodableColor(red: 0.925, green: 0.937, blue: 0.957),
                    CodableColor(red: 0.263, green: 0.298, blue: 0.369),
                    CodableColor(red: 0.749, green: 0.380, blue: 0.416),
                    CodableColor(red: 0.639, green: 0.745, blue: 0.549),
                    CodableColor(red: 0.922, green: 0.796, blue: 0.545),
                    CodableColor(red: 0.506, green: 0.631, blue: 0.757),
                    CodableColor(red: 0.706, green: 0.557, blue: 0.678),
                    CodableColor(red: 0.557, green: 0.737, blue: 0.733),
                    CodableColor(red: 0.561, green: 0.737, blue: 0.733),
                ]
            ),
        ]
    }
}
