import Cocoa
import SwiftUI
import IOKit.pwr_mgt
import ServiceManagement
import UserNotifications
import Combine

// MARK: - Version
let appVersion = "1.1.0"

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
    var webSocketTask: URLSessionWebSocketTask?
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
            return UserDefaults.standard.string(forKey: "serverPassword") ?? ""
        }
        set {
            UserDefaults.standard.set(newValue, forKey: "serverPassword")
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
        switch displayMode {
        case .menuBarOnly:
            NSApp.setActivationPolicy(.accessory)
            setupStatusItem()
        case .dockOnly:
            NSApp.setActivationPolicy(.regular)
            removeStatusItem()
        case .both:
            NSApp.setActivationPolicy(.regular)
            setupStatusItem()
        }
    }

    func setupStatusItem() {
        if statusItem == nil {
            statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        }
        updateStatusIcon()
        updateMenu()
    }

    func updateStatusIcon() {
        guard let button = statusItem?.button else { return }

        // Load custom icon
        if let iconPath = Bundle.main.path(forResource: "MenuIcon", ofType: "png"),
           let icon = NSImage(contentsOfFile: iconPath) {
            icon.size = NSSize(width: 18, height: 18)
            icon.isTemplate = true  // Adapts to light/dark mode
            button.image = icon
        } else {
            // Fallback to SF Symbol
            button.image = NSImage(systemSymbolName: "terminal", accessibilityDescription: "TermAway")
        }
    }

    func removeStatusItem() {
        if let item = statusItem {
            NSStatusBar.system.removeStatusItem(item)
            statusItem = nil
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
            let clientsText = connectedClientCount == 1 ? "1 client connected" : "\(connectedClientCount) clients connected"
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

        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q"))

        statusItem.menu = menu
    }

    @objc func startServer() {
        guard !isRunning else { return }

        let nodePaths = [
            "/opt/homebrew/opt/node@22/bin/node",
            "/opt/homebrew/bin/node",
            "/usr/local/bin/node"
        ]

        var nodePath: String?
        for path in nodePaths {
            if FileManager.default.fileExists(atPath: path) {
                nodePath = path
                break
            }
        }

        guard let node = nodePath else {
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
        serverProcess?.terminate()
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
            let clientsText = connectedClients.isEmpty ? "\(connectedClientCount) clients connected" : "\(connectedClients.count) clients connected"
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
                contentRect: NSRect(x: 0, y: 0, width: 380, height: 650),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            preferencesWindow?.title = "Preferences"
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

        let session = URLSession(configuration: .default)
        webSocketTask = session.webSocketTask(with: url)
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
        connectedClientCount = 0
    }

    func receiveWebSocketMessage() {
        webSocketTask?.receive { [weak self] result in
            switch result {
            case .success(let message):
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
                // Try to reconnect after a delay
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
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
        if displayMode == .dockOnly {
            showPreferences()
        }
        return true
    }
}

// MARK: - Preferences View
struct PreferencesView: View {
    @ObservedObject var viewModel: PreferencesViewModel

    init(appDelegate: AppDelegate) {
        self.viewModel = PreferencesViewModel(appDelegate: appDelegate)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Display Mode")
                    .font(.headline)

                Picker("", selection: $viewModel.displayMode) {
                    ForEach(DisplayMode.allCases, id: \.self) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.radioGroup)
                .onChange(of: viewModel.displayMode) { newValue in
                    viewModel.appDelegate.displayMode = newValue
                }

                Divider()

                Text("Server")
                    .font(.headline)

                Toggle("Prevent sleep while server is running", isOn: $viewModel.preventSleep)
                    .onChange(of: viewModel.preventSleep) { newValue in
                        viewModel.appDelegate.preventSleep = newValue
                    }

                Text("Keeps your Mac awake so you can connect from your iPad anytime.")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Divider()

                Text("Security")
                    .font(.headline)

                Toggle("Require password", isOn: $viewModel.requirePassword)
                    .onChange(of: viewModel.requirePassword) { newValue in
                        viewModel.appDelegate.requirePassword = newValue
                        viewModel.appDelegate.restartServer()
                    }

                if viewModel.requirePassword {
                    TextField("Password", text: $viewModel.serverPassword)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit {
                            viewModel.appDelegate.serverPassword = viewModel.serverPassword
                            viewModel.appDelegate.restartServer()
                        }
                        .onChange(of: viewModel.serverPassword) { newValue in
                            viewModel.appDelegate.serverPassword = newValue
                        }

                    Text("Press Return to apply password change.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Divider()

                Text("Startup")
                    .font(.headline)

                Toggle("Launch at login", isOn: $viewModel.launchAtLogin)
                    .onChange(of: viewModel.launchAtLogin) { newValue in
                        viewModel.appDelegate.launchAtLogin = newValue
                    }

                Text("Automatically start TermAway when you log in.")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Divider()

                Text("Notifications")
                    .font(.headline)

                Toggle("Show connection notifications", isOn: $viewModel.connectionNotifications)
                    .onChange(of: viewModel.connectionNotifications) { newValue in
                        viewModel.appDelegate.connectionNotifications = newValue
                    }

                Text("Get notified when clients connect or disconnect.")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Divider()

                Text("Connected Clients")
                    .font(.headline)

                if viewModel.connectedClients.isEmpty {
                    HStack {
                        Image(systemName: "person.slash")
                            .foregroundColor(.secondary)
                        Text("No clients connected")
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 4)
                } else {
                    VStack(alignment: .leading, spacing: 8) {
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
                                    if let connectedAt = client.connectedAt {
                                        Text("Connected \(connectedAt, style: .relative) ago")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                }
                                Spacer()
                                Button(action: {
                                    viewModel.appDelegate.kickClient(clientId: client.id)
                                }) {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundColor(.red)
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

                Divider()

                // Version & Copyright
                VStack(spacing: 4) {
                    Text("TermAway v\(appVersion)")
                        .font(.caption)
                        .fontWeight(.medium)

                    Text("Created by Alex Kerber")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Link("alexkerber.com", destination: URL(string: "https://alexkerber.com")!)
                        .font(.caption)

                    Text("© 2026 All rights reserved")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 8)
            }
            .padding(20)
        }
        .frame(width: 360, height: 630)
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
