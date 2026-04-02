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

// MARK: - Multi-Window Constants

/// NSUserActivity type used to track which session a window is displaying.
/// Each iPadOS window stores this activity so the system can restore it.
let termAwaySessionActivityType = "app.termaway.session"

// MARK: - Shared State (Single Instance Across All Scenes)

/// These managers are shared across all iPadOS windows.
/// ConnectionManager maintains one WebSocket connection; each window attaches
/// to whichever session it needs independently.
///
/// Wrapped in a @MainActor enum to satisfy actor isolation for the ObservableObject inits.
@MainActor
enum SharedState {
    static let connectionManager = ConnectionManager()
    static let shortcutsManager = ShortcutsManager()
    static let themeManager = ThemeManager()
    static let biometricManager = BiometricManager()
    static let keyboardShortcutState = KeyboardShortcutState()
}

@main
struct TermAwayApp: App {
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            SceneRootView()
                .environmentObject(SharedState.connectionManager)
                .environmentObject(SharedState.shortcutsManager)
                .environmentObject(SharedState.themeManager)
                .environmentObject(SharedState.biometricManager)
                .environmentObject(SharedState.keyboardShortcutState)
                .tint(.brandOrange)
                .onAppear {
                    SharedState.connectionManager.requestNotificationPermissions()
                }
        }
        .commands {
            KeyboardShortcutCommands(
                connectionManager: SharedState.connectionManager,
                shortcutState: SharedState.keyboardShortcutState
            )
        }
        .onChange(of: scenePhase) { _, newPhase in
            switch newPhase {
            case .background, .inactive:
                SharedState.biometricManager.lockApp()
            case .active:
                SharedState.biometricManager.authenticate()
            @unknown default:
                break
            }
        }
    }
}

// MARK: - Per-Scene Root View

/// Each iPadOS window gets its own SceneRootView with an independent
/// SplitPaneManager and session binding. The WebSocket connection is shared
/// so all windows talk to the same server without extra connections.
struct SceneRootView: View {
    @EnvironmentObject var connectionManager: ConnectionManager
    @EnvironmentObject var themeManager: ThemeManager

    /// Each window gets its own SplitPaneManager for independent pane layouts
    @StateObject private var splitPaneManager = SplitPaneManager()

    /// The session name this particular window is tracking.
    /// Persisted via NSUserActivity for window restoration.
    @State private var windowSessionName: String?

    /// Registration ID for session-removed callback
    @State private var sessionRemovedCallbackId: UUID?

    var body: some View {
        ContentView(windowSessionName: $windowSessionName)
            .environmentObject(splitPaneManager)
            .preferredColorScheme(themeManager.appearanceMode.colorScheme)
            .onAppear {
                // Wire up the callback for clearing saved layouts when sessions are removed
                sessionRemovedCallbackId = connectionManager.registerSessionRemovedCallback { [weak splitPaneManager] sessionName in
                    splitPaneManager?.clearSavedLayout(for: sessionName)
                }
            }
            .onDisappear {
                if let id = sessionRemovedCallbackId {
                    connectionManager.unregisterSessionRemovedCallback(id)
                }
            }
            // Restore session when the system re-creates this window
            .onContinueUserActivity(termAwaySessionActivityType) { activity in
                if let sessionName = activity.userInfo?["sessionName"] as? String {
                    windowSessionName = sessionName
                    if connectionManager.isConnected && connectionManager.isAuthenticated {
                        connectionManager.attachToSession(sessionName)
                    }
                }
            }
            // Advertise current session so iPadOS can restore this window
            .userActivity(termAwaySessionActivityType) { activity in
                let name = windowSessionName ?? connectionManager.currentSession?.name
                activity.isEligibleForHandoff = false
                activity.needsSave = true
                if let name = name {
                    activity.userInfo = ["sessionName": name]
                    activity.title = "TermAway — \(name)"
                }
            }
    }
}

// MARK: - Open in New Window Helper

/// Request iPadOS to open a new window showing the given session.
/// Uses UIKit scene APIs which are available on iPad.
func openSessionInNewWindow(_ sessionName: String) {
    let activity = NSUserActivity(activityType: termAwaySessionActivityType)
    activity.userInfo = ["sessionName": sessionName]
    activity.title = "TermAway — \(sessionName)"

    let options = UIScene.ActivationRequestOptions()
    options.requestingScene = UIApplication.shared.connectedScenes
        .compactMap { $0 as? UIWindowScene }
        .first

    UIApplication.shared.requestSceneSessionActivation(
        nil,  // nil = create a new scene session
        userActivity: activity,
        options: options,
        errorHandler: { error in
            print("Failed to open new window: \(error.localizedDescription)")
        }
    )
}
