import Foundation
import Combine
import SwiftUI

enum AppearanceMode: String, CaseIterable, Codable {
    case system = "System"
    case dark = "Dark"
    case light = "Light"

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .dark: return .dark
        case .light: return .light
        }
    }
}

class ThemeManager: ObservableObject {
    static let shared = ThemeManager()

    @Published var currentTheme: TerminalTheme {
        didSet {
            saveTheme()
        }
    }

    @Published var fontSize: CGFloat {
        didSet {
            UserDefaults.standard.set(fontSize, forKey: "terminalFontSize")
        }
    }

    @Published var appearanceMode: AppearanceMode {
        didSet {
            UserDefaults.standard.set(appearanceMode.rawValue, forKey: "appearanceMode")
        }
    }

    @Published var focusGlowEnabled: Bool {
        didSet {
            UserDefaults.standard.set(focusGlowEnabled, forKey: "focusGlowEnabled")
        }
    }

    @Published var focusGlowColor: Color {
        didSet {
            // Store as hex string
            UserDefaults.standard.set(focusGlowColor.toHex(), forKey: "focusGlowColor")
        }
    }

    private let themeKey = "terminalTheme"

    init() {
        // Load saved theme or use default
        if let data = UserDefaults.standard.data(forKey: themeKey),
           let theme = try? JSONDecoder().decode(TerminalTheme.self, from: data) {
            self.currentTheme = theme
        } else {
            self.currentTheme = .dark
        }

        // Load saved font size
        let savedSize = UserDefaults.standard.double(forKey: "terminalFontSize")
        self.fontSize = savedSize > 0 ? savedSize : 14

        // Load saved appearance mode
        if let savedMode = UserDefaults.standard.string(forKey: "appearanceMode"),
           let mode = AppearanceMode(rawValue: savedMode) {
            self.appearanceMode = mode
        } else {
            self.appearanceMode = .system
        }

        // Load focus glow settings (default: enabled, orange)
        if UserDefaults.standard.object(forKey: "focusGlowEnabled") != nil {
            self.focusGlowEnabled = UserDefaults.standard.bool(forKey: "focusGlowEnabled")
        } else {
            self.focusGlowEnabled = true
        }

        if let hexString = UserDefaults.standard.string(forKey: "focusGlowColor"),
           let color = Color(hex: hexString) {
            self.focusGlowColor = color
        } else {
            self.focusGlowColor = .brandOrange
        }
    }

    private func saveTheme() {
        if let data = try? JSONEncoder().encode(currentTheme) {
            UserDefaults.standard.set(data, forKey: themeKey)
        }
    }

    func setTheme(_ theme: TerminalTheme) {
        currentTheme = theme
    }

    func setFontSize(_ size: CGFloat) {
        fontSize = max(10, min(24, size))
    }

    /// Returns true if the current terminal theme has a light background
    var isCurrentThemeLight: Bool {
        let color = currentTheme.backgroundColor
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        color.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        // Calculate relative luminance
        let luminance = 0.299 * red + 0.587 * green + 0.114 * blue
        return luminance > 0.5
    }

    /// The appropriate icon color for overlays on the terminal (white for dark themes, black for light)
    var terminalOverlayColor: Color {
        isCurrentThemeLight ? .black : .white
    }
}
