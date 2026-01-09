import Cocoa
import SwiftUI

// MARK: - Display Mode
enum DisplayMode: String, CaseIterable {
    case menuBarOnly = "Menu Bar Only"
    case dockOnly = "Dock Only"
    case both = "Both"
}

// MARK: - App Delegate
class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem?
    var serverProcess: Process?
    var isRunning = false
    var localIP: String = "localhost"
    let port = "3000"
    var preferencesWindow: NSWindow?

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

        // IP Address (copyable)
        if isRunning {
            let urlString = "http://\(localIP):\(port)"
            let ipItem = NSMenuItem(title: urlString, action: #selector(copyURL), keyEquivalent: "c")
            ipItem.toolTip = "Click to copy"
            menu.addItem(ipItem)
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
        serverProcess?.arguments = [script]
        serverProcess?.environment = ProcessInfo.processInfo.environment
        serverProcess?.standardOutput = FileHandle.nullDevice
        serverProcess?.standardError = FileHandle.nullDevice

        do {
            try serverProcess?.run()
            isRunning = true
            updateStatusIcon()
            updateMenu()
        } catch {
            showAlert(message: "Failed to start server: \(error.localizedDescription)")
        }
    }

    func findServerScript() -> String? {
        let bundlePath = Bundle.main.bundlePath

        // When installed in /Applications, look for server relative to app
        let paths = [
            // Dev: macos-app/TermAway.app -> ../server/index.js
            (bundlePath as NSString).deletingLastPathComponent + "/server/index.js",
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
        serverProcess?.terminate()
        serverProcess = nil
        isRunning = false
        updateStatusIcon()
        updateMenu()
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

    @objc func showPreferences() {
        if preferencesWindow == nil {
            let prefsView = PreferencesView(appDelegate: self)
            preferencesWindow = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 300, height: 200),
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

    func applicationWillTerminate(_ notification: Notification) {
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

            Spacer()

            Divider()

            // Copyright
            VStack(spacing: 4) {
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
        }
        .padding(20)
        .frame(width: 280, height: 200)
    }
}

class PreferencesViewModel: ObservableObject {
    let appDelegate: AppDelegate
    @Published var displayMode: DisplayMode

    init(appDelegate: AppDelegate) {
        self.appDelegate = appDelegate
        self.displayMode = appDelegate.displayMode
    }
}

// MARK: - Entry Point
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
