import Cocoa
import Network

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem!
    var serverProcess: Process?
    var isRunning = false
    var localIP: String = "localhost"
    let port = "3000"

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Hide dock icon
        NSApp.setActivationPolicy(.accessory)

        // Get local IP
        localIP = getLocalIP() ?? "localhost"

        // Create status bar item
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "terminal", accessibilityDescription: "Claude Remote")
        }

        updateMenu()

        // Auto-start server
        startServer()
    }

    func updateMenu() {
        let menu = NSMenu()

        // Status
        let statusMenuItem = NSMenuItem(title: isRunning ? "● Server Running" : "○ Server Stopped", action: nil, keyEquivalent: "")
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
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q"))

        statusItem.menu = menu
    }

    @objc func startServer() {
        guard !isRunning else { return }

        // Try to find node
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
            print("Node.js not found")
            return
        }

        // Find server script - check relative to app bundle first, then current dir
        let bundlePath = Bundle.main.bundlePath
        var scriptPath = (bundlePath as NSString).deletingLastPathComponent
        scriptPath = (scriptPath as NSString).deletingLastPathComponent
        scriptPath = (scriptPath as NSString).deletingLastPathComponent
        scriptPath = (scriptPath as NSString).appendingPathComponent("server/index.js")

        if !FileManager.default.fileExists(atPath: scriptPath) {
            // Try parent of macos-app folder
            scriptPath = (bundlePath as NSString).deletingLastPathComponent
            scriptPath = (scriptPath as NSString).deletingLastPathComponent
            scriptPath = (scriptPath as NSString).appendingPathComponent("server/index.js")
        }

        if !FileManager.default.fileExists(atPath: scriptPath) {
            // Try current working directory
            scriptPath = FileManager.default.currentDirectoryPath + "/server/index.js"
        }

        guard FileManager.default.fileExists(atPath: scriptPath) else {
            print("Server script not found: \(scriptPath)")
            return
        }

        serverProcess = Process()
        serverProcess?.executableURL = URL(fileURLWithPath: node)
        serverProcess?.arguments = [scriptPath]
        serverProcess?.environment = ProcessInfo.processInfo.environment

        // Redirect output
        serverProcess?.standardOutput = FileHandle.nullDevice
        serverProcess?.standardError = FileHandle.nullDevice

        do {
            try serverProcess?.run()
            isRunning = true
            updateMenu()
            updateStatusIcon()
        } catch {
            print("Failed to start server: \(error)")
        }
    }

    @objc func stopServer() {
        serverProcess?.terminate()
        serverProcess = nil
        isRunning = false
        updateMenu()
        updateStatusIcon()
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

    @objc func quit() {
        stopServer()
        NSApp.terminate(nil)
    }

    func updateStatusIcon() {
        if let button = statusItem.button {
            let symbolName = isRunning ? "terminal.fill" : "terminal"
            button.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: "Claude Remote")
        }
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
}

// Entry point
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
