import SwiftUI

// MARK: - Brand Colors
extension Color {
    // Primary accent - orange
    static let brandOrange = Color(red: 255/255, green: 107/255, blue: 53/255)  // #FF6B35
    // Secondary accent - amber
    static let brandAmber = Color(red: 255/255, green: 182/255, blue: 39/255)   // #FFB627
    // Light accent - cream
    static let brandCream = Color(red: 254/255, green: 243/255, blue: 226/255)  // #FEF3E2
    // Dark accent - off-black
    static let brandDark = Color(red: 45/255, green: 41/255, blue: 38/255)      // #2D2926

    // MARK: - Hex Conversion

    init?(hex: String) {
        var hexSanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        hexSanitized = hexSanitized.replacingOccurrences(of: "#", with: "")

        var rgb: UInt64 = 0
        guard Scanner(string: hexSanitized).scanHexInt64(&rgb) else { return nil }

        let r, g, b: Double
        if hexSanitized.count == 6 {
            r = Double((rgb & 0xFF0000) >> 16) / 255.0
            g = Double((rgb & 0x00FF00) >> 8) / 255.0
            b = Double(rgb & 0x0000FF) / 255.0
        } else {
            return nil
        }

        self.init(red: r, green: g, blue: b)
    }

    func toHex() -> String {
        let uiColor = UIColor(self)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        uiColor.getRed(&r, green: &g, blue: &b, alpha: &a)
        return String(format: "#%02X%02X%02X", Int(r * 255), Int(g * 255), Int(b * 255))
    }
}

@main
struct TermAwayApp: App {
    @StateObject private var connectionManager = ConnectionManager()
    @StateObject private var shortcutsManager = ShortcutsManager()
    @StateObject private var themeManager = ThemeManager()
    @StateObject private var splitPaneManager = SplitPaneManager()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(connectionManager)
                .environmentObject(shortcutsManager)
                .environmentObject(themeManager)
                .environmentObject(splitPaneManager)
                .preferredColorScheme(themeManager.appearanceMode.colorScheme)
                .onAppear {
                    connectionManager.requestNotificationPermissions()
                    // Clear saved layout when session is removed (killed or exited)
                    connectionManager.onSessionRemoved = { [weak splitPaneManager] sessionName in
                        splitPaneManager?.clearSavedLayout(for: sessionName)
                    }
                }
        }
    }
}
