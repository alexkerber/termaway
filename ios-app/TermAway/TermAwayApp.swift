import SwiftUI

@main
struct TermAwayApp: App {
    @StateObject private var connectionManager = ConnectionManager()
    @StateObject private var shortcutsManager = ShortcutsManager()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(connectionManager)
                .environmentObject(shortcutsManager)
        }
    }
}
