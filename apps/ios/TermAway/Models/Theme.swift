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

    static let presets: [TerminalTheme] = [
        .dark, .light, .solarizedDark, .solarizedLight, .monokai, .dracula, .nord
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
