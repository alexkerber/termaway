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
}

@main
struct TermAwayApp: App {
    @StateObject private var connectionManager = ConnectionManager()
    @StateObject private var shortcutsManager = ShortcutsManager()
    @StateObject private var themeManager = ThemeManager()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(connectionManager)
                .environmentObject(shortcutsManager)
                .environmentObject(themeManager)
                .preferredColorScheme(themeManager.appearanceMode.colorScheme)
        }
    }
}
