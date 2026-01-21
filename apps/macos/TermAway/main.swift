import Cocoa
import SwiftUI
import IOKit.pwr_mgt
import ServiceManagement
import UserNotifications
import Combine

// MARK: - Version
let appVersion = "1.1.4"

// MARK: - Update Checker
class UpdateChecker {
    static let shared = UpdateChecker()
    private let repoOwner = "alexkerber"
    private let repoName = "termaway"

    struct GitHubRelease: Codable {
        let tag_name: String
        let html_url: String
        let name: String
        let body: String?
        let assets: [GitHubAsset]
    }

    struct GitHubAsset: Codable {
        let name: String
        let browser_download_url: String
    }

    func checkForUpdates(silent: Bool = false, completion: ((Bool, GitHubRelease?) -> Void)? = nil) {
        let urlString = "https://api.github.com/repos/\(repoOwner)/\(repoName)/releases/latest"
        guard let url = URL(string: urlString) else {
            completion?(false, nil)
            return
        }

        var request = URLRequest(url: url)
        request.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")

        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            guard let self = self,
                  let data = data,
                  error == nil,
                  let release = try? JSONDecoder().decode(GitHubRelease.self, from: data) else {
                DispatchQueue.main.async {
                    if !silent {
                        self?.showNoUpdateAlert()
                    }
                    completion?(false, nil)
                }
                return
            }

            let latestVersion = release.tag_name.replacingOccurrences(of: "v", with: "")
            let hasUpdate = self.isVersion(latestVersion, newerThan: appVersion)

            DispatchQueue.main.async {
                if hasUpdate {
                    self.showUpdateAlert(release: release)
                } else if !silent {
                    self.showNoUpdateAlert()
                }
                completion?(hasUpdate, hasUpdate ? release : nil)
            }
        }.resume()
    }

    private func isVersion(_ new: String, newerThan current: String) -> Bool {
        let newParts = new.split(separator: ".").compactMap { Int($0) }
        let currentParts = current.split(separator: ".").compactMap { Int($0) }

        for i in 0..<max(newParts.count, currentParts.count) {
            let newPart = i < newParts.count ? newParts[i] : 0
            let currentPart = i < currentParts.count ? currentParts[i] : 0

            if newPart > currentPart { return true }
            if newPart < currentPart { return false }
        }
        return false
    }

    private func showUpdateAlert(release: GitHubRelease) {
        let alert = NSAlert()
        alert.messageText = "Update Available"
        alert.informativeText = "TermAway \(release.tag_name) is available. You have v\(appVersion).\n\n\(release.body ?? "")"
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Download")
        alert.addButton(withTitle: "Later")

        if alert.runModal() == .alertFirstButtonReturn {
            // Find macOS zip asset or fall back to release page
            if let asset = release.assets.first(where: { $0.name.contains("macOS") && $0.name.hasSuffix(".zip") }),
               let downloadURL = URL(string: asset.browser_download_url) {
                NSWorkspace.shared.open(downloadURL)
            } else if let releaseURL = URL(string: release.html_url) {
                NSWorkspace.shared.open(releaseURL)
            }
        }
    }

    private func showNoUpdateAlert() {
        let alert = NSAlert()
        alert.messageText = "You're Up to Date"
        alert.informativeText = "TermAway v\(appVersion) is the latest version."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}

// MARK: - Keychain Helper
enum KeychainHelper {
    private static let service = "com.termaway.server"
    private static let account = "serverPassword"

    static func save(password: String) {
        let data = password.data(using: .utf8)!

        // Delete existing item first
        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(deleteQuery as CFDictionary)

        // Add new item
        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data
        ]
        SecItemAdd(addQuery as CFDictionary, nil)
    }

    static func load() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess,
              let data = result as? Data,
              let password = String(data: data, encoding: .utf8) else {
            return nil
        }
        return password
    }

    static func delete() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }
}

// MARK: - Display Mode
enum DisplayMode: String, CaseIterable {
    case menuBarOnly = "Menu Bar Only"
    case dockOnly = "Dock Only"
    case both = "Both"
}

// MARK: - Connected Client Model
struct ConnectedClient: Identifiable {
    let id: Int
    let ip: String
    let connectedAt: Date?
    let session: String?
}

// MARK: - App Delegate
class AppDelegate: NSObject, NSApplicationDelegate, ObservableObject, NSMenuDelegate {
    var statusItem: NSStatusItem?
    var serverProcess: Process?
    var isRunning = false
    var localIP: String = "localhost"
    let port = "3000"
    var preferencesWindow: NSWindow?
    var sleepAssertionID: IOPMAssertionID = 0
    var webSocketSession: URLSession?
    var webSocketTask: URLSessionWebSocketTask?
    var webSocketReconnectAttempts = 0
    var connectedClientCount = 0
    @Published var connectedClients: [ConnectedClient] = []

    var displayMode: DisplayMode {
        get {
            let raw = UserDefaults.standard.string(forKey: "displayMode") ?? DisplayMode.menuBarOnly.rawValue
            return DisplayMode(rawValue: raw) ?? .menuBarOnly
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: "displayMode")
            applyDisplayMode()
        }
    }

    var preventSleep: Bool {
        get {
            // Default to false - user must opt-in
            return UserDefaults.standard.bool(forKey: "preventSleep")
        }
        set {
            UserDefaults.standard.set(newValue, forKey: "preventSleep")
            // Update assertion state if server is running
            if isRunning {
                if newValue {
                    enableSleepPrevention()
                } else {
                    disableSleepPrevention()
                }
            }
        }
    }

    var requirePassword: Bool {
        get {
            return UserDefaults.standard.bool(forKey: "requirePassword")
        }
        set {
            UserDefaults.standard.set(newValue, forKey: "requirePassword")
        }
    }

    var serverPassword: String {
        get {
            return KeychainHelper.load() ?? ""
        }
        set {
            if newValue.isEmpty {
                KeychainHelper.delete()
            } else {
                KeychainHelper.save(password: newValue)
            }
        }
    }

    var launchAtLogin: Bool {
        get {
            if #available(macOS 13.0, *) {
                return SMAppService.mainApp.status == .enabled
            } else {
                return UserDefaults.standard.bool(forKey: "launchAtLogin")
            }
        }
        set {
            if #available(macOS 13.0, *) {
                do {
                    if newValue {
                        try SMAppService.mainApp.register()
                    } else {
                        try SMAppService.mainApp.unregister()
                    }
                } catch {
                    print("Failed to update login item: \(error)")
                }
            } else {
                UserDefaults.standard.set(newValue, forKey: "launchAtLogin")
            }
        }
    }

    var connectionNotifications: Bool {
        get {
            // Default to true
            if UserDefaults.standard.object(forKey: "connectionNotifications") == nil {
                return true
            }
            return UserDefaults.standard.bool(forKey: "connectionNotifications")
        }
        set {
            UserDefaults.standard.set(newValue, forKey: "connectionNotifications")
        }
    }

    func enableSleepPrevention() {
        guard sleepAssertionID == 0 else { return } // Already active

        let reason = "TermAway server is running" as CFString
        let result = IOPMAssertionCreateWithName(
            kIOPMAssertionTypePreventUserIdleSystemSleep as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            reason,
            &sleepAssertionID
        )

        if result != kIOReturnSuccess {
            print("Failed to create sleep assertion: \(result)")
            sleepAssertionID = 0
        }
    }

    func disableSleepPrevention() {
        guard sleepAssertionID != 0 else { return }

        IOPMAssertionRelease(sleepAssertionID)
        sleepAssertionID = 0
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        localIP = getLocalIP() ?? "localhost"
        applyDisplayMode()
        startServer()
    }

    func applyDisplayMode() {
        let showInDock = displayMode != .menuBarOnly
        let showInMenuBar = displayMode != .dockOnly

        // Handle status item: remove if not needed, create if needed
        if showInMenuBar {
            if statusItem == nil {
                statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
                updateStatusIcon()
                updateMenu()
            }
        } else {
            if let item = statusItem {
                NSStatusBar.system.removeStatusItem(item)
                statusItem = nil
            }
        }

        // Change activation policy
        let newPolicy: NSApplication.ActivationPolicy = showInDock ? .regular : .accessory
        NSApp.setActivationPolicy(newPolicy)

        // Force app to process the change
        if showInDock {
            NSApp.activate(ignoringOtherApps: false)
        }
    }

    // Prevent app from quitting when last window closes (important for menu bar mode)
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }

    func updateStatusIcon() {
        guard let button = statusItem?.button else { return }

        // Load custom icon (Xcode bundles as tiff)
        // Original aspect ratio: 787x465, scaled to 14pt height = ~24x14
        if let icon = NSImage(named: "MenuIcon") {
            icon.size = NSSize(width: 24, height: 14)
            icon.isTemplate = true  // Adapts to light/dark mode
            button.image = icon
        } else {
            // Fallback to SF Symbol
            button.image = NSImage(systemSymbolName: "terminal", accessibilityDescription: "TermAway")
        }
    }

    func updateMenu() {
        guard let statusItem = statusItem else { return }

        let menu = NSMenu()
        menu.delegate = self

        // Status with colored dot
        let statusText = isRunning ? "Server Running" : "Server Stopped"
        let statusMenuItem = NSMenuItem(title: statusText, action: nil, keyEquivalent: "")

        // Add colored circle to status text
        let statusString = NSMutableAttributedString()
        let dotAttachment = NSTextAttachment()
        let dotSize: CGFloat = 8
        let dotImage = NSImage(size: NSSize(width: dotSize, height: dotSize))
        dotImage.lockFocus()
        let dotColor: NSColor = isRunning ? .systemGreen : .systemRed
        dotColor.setFill()
        NSBezierPath(ovalIn: NSRect(x: 0, y: 0, width: dotSize, height: dotSize)).fill()
        dotImage.unlockFocus()
        dotAttachment.image = dotImage

        let dotString = NSAttributedString(attachment: dotAttachment)
        statusString.append(dotString)
        statusString.append(NSAttributedString(string: " " + statusText))
        statusMenuItem.attributedTitle = statusString
        statusMenuItem.isEnabled = false
        menu.addItem(statusMenuItem)

        menu.addItem(NSMenuItem.separator())

        // IP Address (copyable) and connected clients
        if isRunning {
            let urlString = "http://\(localIP):\(port)"
            let ipItem = NSMenuItem(title: urlString, action: #selector(copyURL), keyEquivalent: "c")
            ipItem.toolTip = "Click to copy"
            menu.addItem(ipItem)

            // Connected clients with submenu
            let clientCount = connectedClients.count
            let clientsText = clientCount == 1 ? "1 client connected" : "\(clientCount) clients connected"
            let clientsItem = NSMenuItem(title: clientsText, action: nil, keyEquivalent: "")

            if !connectedClients.isEmpty {
                let clientsSubmenu = NSMenu()
                for client in connectedClients {
                    var title = client.ip
                    if let session = client.session {
                        title += " (\(session))"
                    }
                    let clientMenuItem = NSMenuItem(title: title, action: #selector(promptDisconnectClient(_:)), keyEquivalent: "")
                    clientMenuItem.tag = client.id
                    clientMenuItem.target = self
                    clientsSubmenu.addItem(clientMenuItem)
                }
                clientsItem.submenu = clientsSubmenu
            } else {
                clientsItem.isEnabled = false
            }
            menu.addItem(clientsItem)

            menu.addItem(NSMenuItem.separator())
        }

        // Open in Browser
        let openItem = NSMenuItem(title: "Open Terminal", action: #selector(openBrowser), keyEquivalent: "o")
        openItem.isEnabled = isRunning
        menu.addItem(openItem)

        menu.addItem(NSMenuItem.separator())

        // Start/Stop
        if isRunning {
            menu.addItem(NSMenuItem(title: "Stop Server", action: #selector(stopServer), keyEquivalent: "s"))
        } else {
            menu.addItem(NSMenuItem(title: "Start Server", action: #selector(startServer), keyEquivalent: "s"))
        }

        menu.addItem(NSMenuItem.separator())

        // Preferences
        menu.addItem(NSMenuItem(title: "Preferences", action: #selector(showPreferences), keyEquivalent: ","))
        menu.addItem(NSMenuItem(title: "Check for Updates...", action: #selector(checkForUpdates), keyEquivalent: ""))

        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q"))

        statusItem.menu = menu
    }

    @objc func checkForUpdates() {
        UpdateChecker.shared.checkForUpdates()
    }

    @objc func startServer() {
        guard !isRunning else { return }

        guard let node = findNodePath() else {
            showAlert(message: "Node.js not found. Please install Node.js 22 LTS.")
            return
        }

        let scriptPath = findServerScript()
        guard let script = scriptPath, FileManager.default.fileExists(atPath: script) else {
            showAlert(message: "Server script not found.")
            return
        }

        serverProcess = Process()
        serverProcess?.executableURL = URL(fileURLWithPath: node)

        // Build arguments with optional password
        var args = [script]
        if requirePassword && !serverPassword.isEmpty {
            args.append("--password")
            args.append(serverPassword)
        }
        serverProcess?.arguments = args
        serverProcess?.environment = ProcessInfo.processInfo.environment
        serverProcess?.standardOutput = FileHandle.nullDevice
        serverProcess?.standardError = FileHandle.nullDevice

        do {
            try serverProcess?.run()
            isRunning = true
            if preventSleep {
                enableSleepPrevention()
            }
            updateStatusIcon()
            updateMenu()

            // Request notification permissions and connect to server for notifications
            requestNotificationPermissions()
            // Wait for server to start before connecting
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
                self?.connectToServer()
            }
        } catch {
            showAlert(message: "Failed to start server: \(error.localizedDescription)")
        }
    }

    func findNodePath() -> String? {
        // Check common paths first
        let knownPaths = [
            "/opt/homebrew/opt/node@22/bin/node",
            "/opt/homebrew/bin/node",
            "/usr/local/bin/node"
        ]

        for path in knownPaths {
            if FileManager.default.fileExists(atPath: path) {
                return path
            }
        }

        // Fallback: use 'which node' to find Node.js in PATH
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        process.arguments = ["node"]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let path = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
               !path.isEmpty,
               FileManager.default.fileExists(atPath: path) {
                return path
            }
        } catch {
            // Ignore errors, fall through to return nil
        }

        return nil
    }

    func findServerScript() -> String? {
        let bundlePath = Bundle.main.bundlePath

        // When installed in /Applications, look for server relative to app
        let paths = [
            // Dev: apps/macos/TermAway.app -> ../../../server/index.js (up 3 levels from app bundle)
            (((bundlePath as NSString).deletingLastPathComponent as NSString).deletingLastPathComponent as NSString).deletingLastPathComponent + "/server/index.js",
            // Installed: /Applications/TermAway.app -> ~/Developer/termaway/server/index.js
            NSHomeDirectory() + "/Developer/termaway/server/index.js",
            // Current directory
            FileManager.default.currentDirectoryPath + "/server/index.js"
        ]

        for path in paths {
            if FileManager.default.fileExists(atPath: path) {
                return path
            }
        }
        return nil
    }

    @objc func stopServer() {
        disconnectFromServer()

        if let process = serverProcess {
            process.terminate()
            // Wait for process to exit in background to avoid zombies
            DispatchQueue.global(qos: .utility).async {
                process.waitUntilExit()
            }
        }
        serverProcess = nil
        isRunning = false
        disableSleepPrevention()
        updateStatusIcon()
        updateMenu()
    }

    /// Restart the server (stop then start)
    /// Used when settings that affect the server change (e.g., password)
    func restartServer() {
        guard isRunning else { return }

        print("Restarting server due to settings change...")
        stopServer()

        // Small delay to ensure clean shutdown
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.startServer()
        }
    }

    @objc func openBrowser() {
        let url = URL(string: "http://localhost:\(port)")!
        NSWorkspace.shared.open(url)
    }

    @objc func copyURL() {
        let urlString = "http://\(localIP):\(port)"
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(urlString, forType: .string)
    }

    // MARK: - NSMenuDelegate

    func menuWillOpen(_ menu: NSMenu) {
        // Rebuild menu with current data when it opens
        rebuildMenuItems(menu)
        // Also request fresh data for next time
        if isRunning {
            requestClientList()
        }
    }

    private func rebuildMenuItems(_ menu: NSMenu) {
        menu.removeAllItems()

        // Status with colored dot
        let statusText = isRunning ? "Server Running" : "Server Stopped"
        let statusMenuItem = NSMenuItem(title: statusText, action: nil, keyEquivalent: "")

        let statusString = NSMutableAttributedString()
        let dotAttachment = NSTextAttachment()
        let dotSize: CGFloat = 8
        let dotImage = NSImage(size: NSSize(width: dotSize, height: dotSize))
        dotImage.lockFocus()
        let dotColor: NSColor = isRunning ? .systemGreen : .systemRed
        dotColor.setFill()
        NSBezierPath(ovalIn: NSRect(x: 0, y: 0, width: dotSize, height: dotSize)).fill()
        dotImage.unlockFocus()
        dotAttachment.image = dotImage

        let dotString = NSAttributedString(attachment: dotAttachment)
        statusString.append(dotString)
        statusString.append(NSAttributedString(string: " " + statusText))
        statusMenuItem.attributedTitle = statusString
        statusMenuItem.isEnabled = false
        menu.addItem(statusMenuItem)

        menu.addItem(NSMenuItem.separator())

        if isRunning {
            let urlString = "http://\(localIP):\(port)"
            let ipItem = NSMenuItem(title: urlString, action: #selector(copyURL), keyEquivalent: "c")
            ipItem.toolTip = "Click to copy"
            menu.addItem(ipItem)

            // Connected clients with submenu
            let clientCount = connectedClients.count
            let clientsText = clientCount == 1 ? "1 client connected" : "\(clientCount) clients connected"
            let clientsItem = NSMenuItem(title: clientsText, action: nil, keyEquivalent: "")

            if !connectedClients.isEmpty {
                let clientsSubmenu = NSMenu()
                for client in connectedClients {
                    var title = client.ip
                    if let session = client.session {
                        title += " (\(session))"
                    }
                    let clientMenuItem = NSMenuItem(title: title, action: #selector(promptDisconnectClient(_:)), keyEquivalent: "")
                    clientMenuItem.tag = client.id
                    clientMenuItem.target = self
                    clientsSubmenu.addItem(clientMenuItem)
                }
                clientsItem.submenu = clientsSubmenu
            } else {
                clientsItem.isEnabled = false
            }
            menu.addItem(clientsItem)

            menu.addItem(NSMenuItem.separator())
        }

        let openItem = NSMenuItem(title: "Open Terminal", action: #selector(openBrowser), keyEquivalent: "o")
        openItem.isEnabled = isRunning
        menu.addItem(openItem)

        menu.addItem(NSMenuItem.separator())

        if isRunning {
            menu.addItem(NSMenuItem(title: "Stop Server", action: #selector(stopServer), keyEquivalent: "s"))
        } else {
            menu.addItem(NSMenuItem(title: "Start Server", action: #selector(startServer), keyEquivalent: "s"))
        }

        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Preferences", action: #selector(showPreferences), keyEquivalent: ","))
        menu.addItem(NSMenuItem(title: "Check for Updates...", action: #selector(checkForUpdates), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q"))
    }

    @objc func promptDisconnectClient(_ sender: NSMenuItem) {
        let clientId = sender.tag
        guard let client = connectedClients.first(where: { $0.id == clientId }) else { return }

        let alert = NSAlert()
        alert.messageText = "Disconnect Client?"
        alert.informativeText = "Are you sure you want to disconnect \(client.ip)?"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Disconnect")
        alert.addButton(withTitle: "Cancel")

        if alert.runModal() == .alertFirstButtonReturn {
            kickClient(clientId: clientId)
        }
    }

    @objc func showPreferences() {
        if preferencesWindow == nil {
            let prefsView = PreferencesView(appDelegate: self)
            preferencesWindow = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 400, height: 500),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            preferencesWindow?.title = "General"
            preferencesWindow?.contentView = NSHostingView(rootView: prefsView)
            preferencesWindow?.center()
        }
        preferencesWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc func quit() {
        stopServer()
        NSApp.terminate(nil)
    }

    func showAlert(message: String) {
        let alert = NSAlert()
        alert.messageText = "TermAway"
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.runModal()
    }

    func getLocalIP() -> String? {
        var address: String?
        var ifaddr: UnsafeMutablePointer<ifaddrs>?

        guard getifaddrs(&ifaddr) == 0, let firstAddr = ifaddr else { return nil }

        for ifptr in sequence(first: firstAddr, next: { $0.pointee.ifa_next }) {
            let interface = ifptr.pointee
            let addrFamily = interface.ifa_addr.pointee.sa_family

            if addrFamily == UInt8(AF_INET) {
                let name = String(cString: interface.ifa_name)
                if name == "en0" {
                    var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                    getnameinfo(interface.ifa_addr, socklen_t(interface.ifa_addr.pointee.sa_len),
                               &hostname, socklen_t(hostname.count), nil, 0, NI_NUMERICHOST)
                    address = String(cString: hostname)
                }
            }
        }
        freeifaddrs(ifaddr)
        return address
    }

    // MARK: - Notifications

    func requestNotificationPermissions() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, error in
            if let error = error {
                print("Notification permission error: \(error)")
            }
        }
    }

    func showConnectionNotification(connected: Bool, clientIP: String) {
        guard connectionNotifications else { return }

        let content = UNMutableNotificationContent()
        content.title = connected ? "Client Connected" : "Client Disconnected"
        content.body = "\(clientIP) \(connected ? "connected to" : "disconnected from") TermAway"
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )

        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("Notification error: \(error)")
            }
        }
    }

    // MARK: - WebSocket Connection

    func connectToServer() {
        guard let url = URL(string: "ws://localhost:\(port)") else { return }

        // Reuse or create session
        if webSocketSession == nil {
            webSocketSession = URLSession(configuration: .default)
        }

        webSocketTask = webSocketSession?.webSocketTask(with: url)
        webSocketTask?.resume()

        // Authenticate if needed
        if requirePassword && !serverPassword.isEmpty {
            let authMessage = try? JSONSerialization.data(withJSONObject: ["type": "auth", "password": serverPassword])
            if let data = authMessage, let text = String(data: data, encoding: .utf8) {
                webSocketTask?.send(.string(text)) { _ in }
            }
        }

        // Request client list after a short delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.requestClientList()
        }

        receiveWebSocketMessage()
    }

    func requestClientList() {
        let message = try? JSONSerialization.data(withJSONObject: ["type": "list-clients"])
        if let data = message, let text = String(data: data, encoding: .utf8) {
            webSocketTask?.send(.string(text)) { _ in }
        }
    }

    func kickClient(clientId: Int) {
        let message = try? JSONSerialization.data(withJSONObject: ["type": "kick-client", "clientId": clientId])
        if let data = message, let text = String(data: data, encoding: .utf8) {
            webSocketTask?.send(.string(text)) { [weak self] _ in
                // Refresh client list after kick
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    self?.requestClientList()
                }
            }
        }
    }

    func disconnectFromServer() {
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
        webSocketSession?.invalidateAndCancel()
        webSocketSession = nil
        webSocketReconnectAttempts = 0
        connectedClientCount = 0
    }

    func receiveWebSocketMessage() {
        webSocketTask?.receive { [weak self] result in
            switch result {
            case .success(let message):
                // Reset reconnect attempts on successful message
                self?.webSocketReconnectAttempts = 0

                switch message {
                case .string(let text):
                    self?.handleWebSocketMessage(text)
                case .data(let data):
                    if let text = String(data: data, encoding: .utf8) {
                        self?.handleWebSocketMessage(text)
                    }
                @unknown default:
                    break
                }
                self?.receiveWebSocketMessage()

            case .failure(let error):
                print("WebSocket error: \(error)")
                // Exponential backoff: 2s, 4s, 8s, 16s, max 30s
                guard let self = self else { return }
                let delay = min(30.0, 2.0 * pow(2.0, Double(self.webSocketReconnectAttempts)))
                self.webSocketReconnectAttempts += 1

                DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                    if self?.isRunning == true {
                        self?.connectToServer()
                    }
                }
            }
        }
    }

    func handleWebSocketMessage(_ text: String) {
        guard let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = json["type"] as? String else {
            return
        }

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }

            switch type {
            case "client-connected":
                if let clientIP = json["clientIP"] as? String,
                   let clientCount = json["clientCount"] as? Int {
                    // Don't notify for our own connection
                    if clientIP != "127.0.0.1" && clientIP != "localhost" {
                        self.showConnectionNotification(connected: true, clientIP: clientIP)
                    }
                    self.connectedClientCount = clientCount - 1 // Subtract our own connection
                    self.updateMenu()
                    // Refresh client list
                    self.requestClientList()
                }

            case "client-disconnected":
                if let clientIP = json["clientIP"] as? String,
                   let clientCount = json["clientCount"] as? Int {
                    if clientIP != "127.0.0.1" && clientIP != "localhost" {
                        self.showConnectionNotification(connected: false, clientIP: clientIP)
                    }
                    self.connectedClientCount = max(0, clientCount - 1)
                    self.updateMenu()
                    // Refresh client list
                    self.requestClientList()
                }

            case "clients":
                if let list = json["list"] as? [[String: Any]] {
                    let dateFormatter = ISO8601DateFormatter()
                    self.connectedClients = list.compactMap { clientData -> ConnectedClient? in
                        guard let id = clientData["id"] as? Int,
                              let ip = clientData["ip"] as? String else {
                            return nil
                        }
                        // Skip localhost connections (our own)
                        if ip == "127.0.0.1" || ip == "localhost" {
                            return nil
                        }
                        let connectedAt: Date?
                        if let dateString = clientData["connectedAt"] as? String {
                            connectedAt = dateFormatter.date(from: dateString)
                        } else {
                            connectedAt = nil
                        }
                        let session = clientData["session"] as? String
                        return ConnectedClient(id: id, ip: ip, connectedAt: connectedAt, session: session)
                    }
                    self.connectedClientCount = self.connectedClients.count
                    self.updateMenu()
                }

            case "client-kicked":
                // Client was kicked, list will be refreshed automatically
                break

            default:
                break
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        disconnectFromServer()
        stopServer()
    }

    // Handle dock icon click when in dock mode
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showPreferences()
        return true
    }

    // Dock right-click menu
    func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Open Terminal", action: #selector(openBrowser), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Preferences", action: #selector(showPreferences), keyEquivalent: ""))
        return menu
    }
}

// MARK: - Preferences Tab
enum PreferencesTab: String, CaseIterable {
    case general = "General"
    case server = "Server"
    case about = "About"

    var icon: String {
        switch self {
        case .general: return "gear"
        case .server: return "server.rack"
        case .about: return "info.circle"
        }
    }
}

// MARK: - Tab Button Style
struct TabButtonStyle: View {
    let tab: PreferencesTab
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: tab.icon)
                    .font(.system(size: 20))
                Text(tab.rawValue)
                    .font(.system(size: 11))
            }
            .frame(width: 70, height: 50)
            .foregroundColor(isSelected ? .accentColor : .secondary)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? Color.accentColor.opacity(0.15) : Color.clear)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Section Header
struct SectionHeader: View {
    let title: String

    var body: some View {
        Text(title.uppercased())
            .font(.system(size: 11, weight: .medium))
            .foregroundColor(.secondary)
            .padding(.top, 16)
            .padding(.bottom, 8)
    }
}

// MARK: - Setting Row
struct SettingRow: View {
    let title: String
    let description: String?

    init(_ title: String, description: String? = nil) {
        self.title = title
        self.description = description
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
            if let description = description {
                Text(description)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

// MARK: - Section Divider
struct SectionDivider: View {
    var body: some View {
        Divider()
            .padding(.vertical, 8)
    }
}

// MARK: - Link Button
struct LinkButton: View {
    let title: String
    let icon: String
    let url: String

    var body: some View {
        Link(destination: URL(string: url)!) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .frame(width: 20)
                Text(title)
            }
            .foregroundColor(.accentColor)
        }
    }
}

// MARK: - Preferences View
struct PreferencesView: View {
    @ObservedObject var viewModel: PreferencesViewModel
    @State private var selectedTab: PreferencesTab = .general

    init(appDelegate: AppDelegate) {
        self.viewModel = PreferencesViewModel(appDelegate: appDelegate)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Tab Bar
            HStack(spacing: 0) {
                ForEach(PreferencesTab.allCases, id: \.self) { tab in
                    TabButtonStyle(tab: tab, isSelected: selectedTab == tab) {
                        selectedTab = tab
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 12)

            Divider()

            // Content
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    switch selectedTab {
                    case .general:
                        generalTab
                    case .server:
                        serverTab
                    case .about:
                        aboutTab
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 20)
            }
        }
        .frame(width: 400, height: 500)
        .onAppear {
            updateWindowTitle()
        }
        .onChange(of: selectedTab) { _ in
            updateWindowTitle()
        }
    }

    private func updateWindowTitle() {
        DispatchQueue.main.async {
            NSApp.keyWindow?.title = selectedTab.rawValue
        }
    }

    // MARK: - General Tab
    private var generalTab: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeader(title: "System")

            Toggle(isOn: $viewModel.launchAtLogin) {
                SettingRow("Start at Login", description: "Automatically opens TermAway when you start your Mac.")
            }
            .toggleStyle(.checkbox)
            .onChange(of: viewModel.launchAtLogin) { newValue in
                viewModel.appDelegate.launchAtLogin = newValue
            }

            SectionDivider()

            SectionHeader(title: "Display")

            HStack {
                SettingRow("Display Mode", description: "Choose where TermAway appears.")
                Spacer()
                Picker("", selection: $viewModel.displayMode) {
                    ForEach(DisplayMode.allCases, id: \.self) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .frame(width: 150)
                .onChange(of: viewModel.displayMode) { newValue in
                    viewModel.appDelegate.displayMode = newValue
                }
            }

            SectionDivider()

            SectionHeader(title: "Notifications")

            Toggle(isOn: $viewModel.connectionNotifications) {
                SettingRow("Connection notifications", description: "Get notified when clients connect or disconnect.")
            }
            .toggleStyle(.checkbox)
            .onChange(of: viewModel.connectionNotifications) { newValue in
                viewModel.appDelegate.connectionNotifications = newValue
            }

            SectionDivider()

            SectionHeader(title: "Connected Clients")

            if viewModel.connectedClients.isEmpty {
                HStack {
                    Image(systemName: "person.slash")
                        .foregroundColor(.secondary)
                    Text("No clients connected")
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 8)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(viewModel.connectedClients) { client in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(client.ip)
                                    .font(.system(.body, design: .monospaced))
                                if let session = client.session {
                                    Text("Session: \(session)")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                            Spacer()
                            Button(action: {
                                viewModel.appDelegate.kickClient(clientId: client.id)
                            }) {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.secondary)
                            }
                            .buttonStyle(.plain)
                            .help("Disconnect this client")
                        }
                        .padding(8)
                        .background(Color.secondary.opacity(0.1))
                        .cornerRadius(6)
                    }
                }
            }

            Button(action: {
                viewModel.appDelegate.requestClientList()
            }) {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.link)
            .padding(.top, 8)
        }
    }

    // MARK: - Server Tab
    private var serverTab: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeader(title: "Power")

            Toggle(isOn: $viewModel.preventSleep) {
                SettingRow("Prevent sleep while running", description: "Keeps your Mac awake so you can connect from your iPad anytime.")
            }
            .toggleStyle(.checkbox)
            .onChange(of: viewModel.preventSleep) { newValue in
                viewModel.appDelegate.preventSleep = newValue
            }

            SectionDivider()

            SectionHeader(title: "Security")

            Toggle(isOn: $viewModel.requirePassword) {
                SettingRow("Require password", description: "Clients must authenticate before accessing the terminal.")
            }
            .toggleStyle(.checkbox)
            .onChange(of: viewModel.requirePassword) { newValue in
                viewModel.appDelegate.requirePassword = newValue
                viewModel.appDelegate.restartServer()
            }

            if viewModel.requirePassword {
                HStack {
                    Text("Password")
                    Spacer()
                    SecureField("", text: $viewModel.serverPassword)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 180)
                        .onSubmit {
                            viewModel.appDelegate.serverPassword = viewModel.serverPassword
                            viewModel.appDelegate.restartServer()
                        }
                        .onChange(of: viewModel.serverPassword) { newValue in
                            viewModel.appDelegate.serverPassword = newValue
                        }
                }
                .padding(.top, 12)

                Text("Press Return to apply password change.")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .padding(.top, 4)
            }

            Spacer()

            // Quit button at bottom
            HStack {
                Spacer()
                Button(action: {
                    viewModel.appDelegate.quit()
                }) {
                    Text("Quit TermAway")
                        .foregroundColor(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 6)
                        .background(Color.accentColor)
                        .cornerRadius(6)
                }
                .buttonStyle(.plain)
            }
            .padding(.top, 20)
        }
    }

    // MARK: - About Tab
    @State private var isCheckingForUpdates = false

    private var aboutTab: some View {
        VStack(spacing: 16) {
            Spacer()
                .frame(height: 20)

            // App Icon
            if let appIcon = NSImage(named: NSImage.applicationIconName) {
                Image(nsImage: appIcon)
                    .resizable()
                    .frame(width: 80, height: 80)
            }

            // App Name & Version
            VStack(spacing: 4) {
                Text("TermAway")
                    .font(.system(size: 18, weight: .semibold))

                Text("Version \(appVersion)")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)

                Text("Your Mac terminal, on your iPad.")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .padding(.top, 4)
            }

            // Links
            VStack(spacing: 12) {
                LinkButton(title: "Website", icon: "globe", url: "https://termaway.app")
                LinkButton(title: "GitHub", icon: "chevron.left.forwardslash.chevron.right", url: "https://github.com/alexkerber/termaway")
                LinkButton(title: "Twitter", icon: "at", url: "https://twitter.com/alex_kerber")
            }
            .padding(.top, 16)

            // Check for Updates
            Button(action: {
                isCheckingForUpdates = true
                UpdateChecker.shared.checkForUpdates { _, _ in
                    isCheckingForUpdates = false
                }
            }) {
                if isCheckingForUpdates {
                    ProgressView()
                        .scaleEffect(0.7)
                        .frame(width: 16, height: 16)
                } else {
                    Text("Check for Updates...")
                }
            }
            .disabled(isCheckingForUpdates)
            .padding(.top, 8)

            Spacer()

            // Copyright
            Text("© 2025 Alex Kerber")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .padding(.bottom, 20)
        }
        .frame(maxWidth: .infinity)
    }
}

class PreferencesViewModel: ObservableObject {
    let appDelegate: AppDelegate
    @Published var displayMode: DisplayMode
    @Published var preventSleep: Bool
    @Published var requirePassword: Bool
    @Published var serverPassword: String
    @Published var launchAtLogin: Bool
    @Published var connectionNotifications: Bool
    @Published var connectedClients: [ConnectedClient] = []

    private var cancellables = Set<AnyCancellable>()

    init(appDelegate: AppDelegate) {
        self.appDelegate = appDelegate
        self.displayMode = appDelegate.displayMode
        self.preventSleep = appDelegate.preventSleep
        self.requirePassword = appDelegate.requirePassword
        self.serverPassword = appDelegate.serverPassword
        self.launchAtLogin = appDelegate.launchAtLogin
        self.connectionNotifications = appDelegate.connectionNotifications
        self.connectedClients = appDelegate.connectedClients

        // Observe changes to connectedClients from AppDelegate
        appDelegate.$connectedClients
            .receive(on: DispatchQueue.main)
            .sink { [weak self] clients in
                self?.connectedClients = clients
            }
            .store(in: &cancellables)
    }
}

// MARK: - Entry Point
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
