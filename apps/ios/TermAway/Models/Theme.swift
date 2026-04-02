import SwiftUI
import UIKit

struct TerminalTheme: Identifiable, Codable, Equatable {
    let id: String
    let name: String
    let foreground: CodableColor
    let background: CodableColor
    let cursor: CodableColor
    let fontSize: CGFloat

    var foregroundColor: UIColor { foreground.uiColor }
    var backgroundColor: UIColor { background.uiColor }
    var cursorColor: UIColor { cursor.uiColor }

    static let dark = TerminalTheme(
        id: "dark",
        name: "Dark",
        foreground: CodableColor(red: 0.9, green: 0.93, blue: 0.95),
        background: CodableColor(red: 0.05, green: 0.07, blue: 0.09),
        cursor: CodableColor(red: 0.35, green: 0.65, blue: 1.0),
        fontSize: 14
    )

    static let light = TerminalTheme(
        id: "light",
        name: "Light",
        foreground: CodableColor(red: 0.15, green: 0.16, blue: 0.18),
        background: CodableColor(red: 1.0, green: 1.0, blue: 1.0),
        cursor: CodableColor(red: 0.04, green: 0.41, blue: 0.85),
        fontSize: 14
    )

    static let solarizedDark = TerminalTheme(
        id: "solarized-dark",
        name: "Solarized Dark",
        foreground: CodableColor(red: 0.51, green: 0.58, blue: 0.59),
        background: CodableColor(red: 0.0, green: 0.17, blue: 0.21),
        cursor: CodableColor(red: 0.15, green: 0.55, blue: 0.82),
        fontSize: 14
    )

    static let solarizedLight = TerminalTheme(
        id: "solarized-light",
        name: "Solarized Light",
        foreground: CodableColor(red: 0.4, green: 0.48, blue: 0.51),
        background: CodableColor(red: 0.99, green: 0.96, blue: 0.89),
        cursor: CodableColor(red: 0.15, green: 0.55, blue: 0.82),
        fontSize: 14
    )

    static let monokai = TerminalTheme(
        id: "monokai",
        name: "Monokai",
        foreground: CodableColor(red: 0.97, green: 0.97, blue: 0.95),
        background: CodableColor(red: 0.15, green: 0.16, blue: 0.13),
        cursor: CodableColor(red: 0.65, green: 0.89, blue: 0.18),
        fontSize: 14
    )

    static let dracula = TerminalTheme(
        id: "dracula",
        name: "Dracula",
        foreground: CodableColor(red: 0.97, green: 0.97, blue: 0.95),
        background: CodableColor(red: 0.16, green: 0.16, blue: 0.21),
        cursor: CodableColor(red: 0.74, green: 0.58, blue: 0.98),
        fontSize: 14
    )

    static let nord = TerminalTheme(
        id: "nord",
        name: "Nord",
        foreground: CodableColor(red: 0.85, green: 0.87, blue: 0.91),
        background: CodableColor(red: 0.18, green: 0.20, blue: 0.25),
        cursor: CodableColor(red: 0.53, green: 0.75, blue: 0.82),
        fontSize: 14
    )

    // Catppuccin Mocha — #CDD6F4 fg, #1E1E2E bg, #F5E0DC cursor (rosewater)
    static let catppuccinMocha = TerminalTheme(
        id: "catppuccin-mocha",
        name: "Catppuccin Mocha",
        foreground: CodableColor(red: 0.80, green: 0.84, blue: 0.96),
        background: CodableColor(red: 0.12, green: 0.12, blue: 0.18),
        cursor: CodableColor(red: 0.96, green: 0.88, blue: 0.86),
        fontSize: 14
    )

    // Catppuccin Latte — #4C4F69 fg, #EFF1F5 bg, #DC8A78 cursor (rosewater)
    static let catppuccinLatte = TerminalTheme(
        id: "catppuccin-latte",
        name: "Catppuccin Latte",
        foreground: CodableColor(red: 0.30, green: 0.31, blue: 0.41),
        background: CodableColor(red: 0.94, green: 0.95, blue: 0.96),
        cursor: CodableColor(red: 0.86, green: 0.54, blue: 0.47),
        fontSize: 14
    )

    // Gruvbox Dark — #EBDBB2 fg, #282828 bg, #D79921 cursor (yellow)
    static let gruvboxDark = TerminalTheme(
        id: "gruvbox-dark",
        name: "Gruvbox Dark",
        foreground: CodableColor(red: 0.92, green: 0.86, blue: 0.70),
        background: CodableColor(red: 0.16, green: 0.16, blue: 0.16),
        cursor: CodableColor(red: 0.84, green: 0.60, blue: 0.13),
        fontSize: 14
    )

    // Gruvbox Light — #3C3836 fg, #FBF1C7 bg, #D79921 cursor (yellow)
    static let gruvboxLight = TerminalTheme(
        id: "gruvbox-light",
        name: "Gruvbox Light",
        foreground: CodableColor(red: 0.24, green: 0.22, blue: 0.21),
        background: CodableColor(red: 0.98, green: 0.95, blue: 0.78),
        cursor: CodableColor(red: 0.84, green: 0.60, blue: 0.13),
        fontSize: 14
    )

    // Tokyo Night — #A9B1D6 fg, #1A1B26 bg, #C0CAF5 cursor
    static let tokyoNight = TerminalTheme(
        id: "tokyo-night",
        name: "Tokyo Night",
        foreground: CodableColor(red: 0.66, green: 0.69, blue: 0.84),
        background: CodableColor(red: 0.10, green: 0.11, blue: 0.15),
        cursor: CodableColor(red: 0.75, green: 0.79, blue: 0.96),
        fontSize: 14
    )

    // Tokyo Night Storm — #A9B1D6 fg, #24283B bg, #C0CAF5 cursor
    static let tokyoNightStorm = TerminalTheme(
        id: "tokyo-night-storm",
        name: "Tokyo Night Storm",
        foreground: CodableColor(red: 0.66, green: 0.69, blue: 0.84),
        background: CodableColor(red: 0.14, green: 0.16, blue: 0.23),
        cursor: CodableColor(red: 0.75, green: 0.79, blue: 0.96),
        fontSize: 14
    )

    // One Dark — #ABB2BF fg, #282C34 bg, #528BFF cursor
    static let oneDark = TerminalTheme(
        id: "one-dark",
        name: "One Dark",
        foreground: CodableColor(red: 0.67, green: 0.70, blue: 0.75),
        background: CodableColor(red: 0.16, green: 0.17, blue: 0.20),
        cursor: CodableColor(red: 0.32, green: 0.55, blue: 1.0),
        fontSize: 14
    )

    // Rosé Pine — #E0DEF4 fg, #191724 bg, #EBBCBA cursor (rose)
    static let rosePine = TerminalTheme(
        id: "rose-pine",
        name: "Rosé Pine",
        foreground: CodableColor(red: 0.88, green: 0.87, blue: 0.96),
        background: CodableColor(red: 0.10, green: 0.09, blue: 0.14),
        cursor: CodableColor(red: 0.92, green: 0.74, blue: 0.73),
        fontSize: 14
    )

    // Rosé Pine Moon — #E0DEF4 fg, #232136 bg, #EA9A97 cursor (rose)
    static let rosePineMoon = TerminalTheme(
        id: "rose-pine-moon",
        name: "Rosé Pine Moon",
        foreground: CodableColor(red: 0.88, green: 0.87, blue: 0.96),
        background: CodableColor(red: 0.14, green: 0.13, blue: 0.21),
        cursor: CodableColor(red: 0.92, green: 0.60, blue: 0.59),
        fontSize: 14
    )

    // Everforest Dark — #D3C6AA fg, #2D353B bg, #A7C080 cursor (green)
    static let everforestDark = TerminalTheme(
        id: "everforest-dark",
        name: "Everforest Dark",
        foreground: CodableColor(red: 0.83, green: 0.78, blue: 0.67),
        background: CodableColor(red: 0.18, green: 0.21, blue: 0.23),
        cursor: CodableColor(red: 0.65, green: 0.75, blue: 0.50),
        fontSize: 14
    )

    // Kanagawa — #DCD7BA fg, #1F1F28 bg, #C8C093 cursor
    static let kanagawa = TerminalTheme(
        id: "kanagawa",
        name: "Kanagawa",
        foreground: CodableColor(red: 0.86, green: 0.84, blue: 0.73),
        background: CodableColor(red: 0.12, green: 0.12, blue: 0.16),
        cursor: CodableColor(red: 0.78, green: 0.75, blue: 0.58),
        fontSize: 14
    )

    // Ayu Dark — #BFBDB6 fg, #0D1017 bg, #E6B450 cursor (accent)
    static let ayuDark = TerminalTheme(
        id: "ayu-dark",
        name: "Ayu Dark",
        foreground: CodableColor(red: 0.75, green: 0.74, blue: 0.71),
        background: CodableColor(red: 0.05, green: 0.06, blue: 0.09),
        cursor: CodableColor(red: 0.90, green: 0.71, blue: 0.31),
        fontSize: 14
    )

    // Ayu Light — #5C6166 fg, #FAFAFA bg, #FF9940 cursor (accent)
    static let ayuLight = TerminalTheme(
        id: "ayu-light",
        name: "Ayu Light",
        foreground: CodableColor(red: 0.36, green: 0.38, blue: 0.40),
        background: CodableColor(red: 0.98, green: 0.98, blue: 0.98),
        cursor: CodableColor(red: 1.0, green: 0.60, blue: 0.25),
        fontSize: 14
    )

    // Palenight — #A6ACCD fg, #292D3E bg, #FFCB6B cursor (yellow)
    static let palenight = TerminalTheme(
        id: "palenight",
        name: "Palenight",
        foreground: CodableColor(red: 0.65, green: 0.67, blue: 0.80),
        background: CodableColor(red: 0.16, green: 0.18, blue: 0.24),
        cursor: CodableColor(red: 1.0, green: 0.80, blue: 0.42),
        fontSize: 14
    )

    // Synthwave '84 — #FFFFFF fg, #262335 bg, #FF7EDB cursor (pink)
    static let synthwave84 = TerminalTheme(
        id: "synthwave-84",
        name: "Synthwave '84",
        foreground: CodableColor(red: 1.0, green: 1.0, blue: 1.0),
        background: CodableColor(red: 0.15, green: 0.14, blue: 0.21),
        cursor: CodableColor(red: 1.0, green: 0.49, blue: 0.86),
        fontSize: 14
    )

    // Cyberpunk — #FCEE09 fg, #000B1E bg, #FF2079 cursor (neon pink)
    static let cyberpunk = TerminalTheme(
        id: "cyberpunk",
        name: "Cyberpunk",
        foreground: CodableColor(red: 0.99, green: 0.93, blue: 0.04),
        background: CodableColor(red: 0.0, green: 0.04, blue: 0.12),
        cursor: CodableColor(red: 1.0, green: 0.13, blue: 0.47),
        fontSize: 14
    )

    // Retro Green — classic green phosphor on black
    static let retroGreen = TerminalTheme(
        id: "retro-green",
        name: "Retro Green",
        foreground: CodableColor(red: 0.20, green: 1.0, blue: 0.20),
        background: CodableColor(red: 0.0, green: 0.0, blue: 0.0),
        cursor: CodableColor(red: 0.20, green: 1.0, blue: 0.20),
        fontSize: 14
    )

    // Retro Amber — classic amber phosphor on black
    static let retroAmber = TerminalTheme(
        id: "retro-amber",
        name: "Retro Amber",
        foreground: CodableColor(red: 1.0, green: 0.75, blue: 0.0),
        background: CodableColor(red: 0.0, green: 0.0, blue: 0.0),
        cursor: CodableColor(red: 1.0, green: 0.75, blue: 0.0),
        fontSize: 14
    )

    static let presets: [TerminalTheme] = [
        .dark, .light, .solarizedDark, .solarizedLight, .monokai, .dracula, .nord,
        .catppuccinMocha, .catppuccinLatte,
        .gruvboxDark, .gruvboxLight,
        .tokyoNight, .tokyoNightStorm,
        .oneDark,
        .rosePine, .rosePineMoon,
        .everforestDark,
        .kanagawa,
        .ayuDark, .ayuLight,
        .palenight,
        .synthwave84,
        .cyberpunk,
        .retroGreen, .retroAmber
    ]
}

struct CodableColor: Codable, Equatable {
    let red: CGFloat
    let green: CGFloat
    let blue: CGFloat
    let alpha: CGFloat

    init(red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat = 1.0) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    init(uiColor: UIColor) {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        uiColor.getRed(&r, green: &g, blue: &b, alpha: &a)
        self.red = r
        self.green = g
        self.blue = b
        self.alpha = a
    }

    var uiColor: UIColor {
        UIColor(red: red, green: green, blue: blue, alpha: alpha)
    }

    var color: Color {
        Color(uiColor: uiColor)
    }
}
