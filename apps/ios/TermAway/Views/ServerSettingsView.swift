import SwiftUI

struct ServerSettingsView: View {
    @EnvironmentObject var connectionManager: ConnectionManager
    @Environment(\.dismiss) var dismiss

    @State private var serverURL: String = ""
    @State private var password: String = ""
    @State private var showingScanner = false
    @State private var clipboardSync: Bool = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        Image(systemName: "link")
                            .foregroundColor(.secondary)
                            .frame(width: 28)

                        TextField("ws://192.168.1.100:3000", text: $serverURL)
                            .keyboardType(.URL)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    }
                } header: {
                    Text("Server Connection")
                } footer: {
                    Text("Enter the WebSocket URL of your TermAway server")
                }

                Section {
                    HStack {
                        Image(systemName: "lock")
                            .foregroundColor(.secondary)
                            .frame(width: 28)

                        SecureField("Password (optional)", text: $password)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    }
                } header: {
                    Text("Authentication")
                } footer: {
                    Text("Enter the password if your server requires authentication")
                }

                Section {
                    Toggle(isOn: $clipboardSync) {
                        Text("Clipboard Sync")
                    }
                } header: {
                    Text("Features")
                } footer: {
                    Text("Sync clipboard between this device and the server")
                }

                Section {
                    DiscoveredServersView(serverURL: $serverURL)
                } header: {
                    Text("Discovered Servers")
                } footer: {
                    Text("Servers advertising via Bonjour will appear automatically")
                }

                Section {
                    Button(action: saveAndConnect) {
                        HStack {
                            Spacer()
                            Text("Connect")
                                .fontWeight(.semibold)
                            Spacer()
                        }
                        .padding(.vertical, 4)
                    }
                    .disabled(serverURL.isEmpty)
                }
            }
            .navigationTitle("Server Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark")
                            .font(.body.weight(.medium))
                            .foregroundColor(.secondary)
                    }
                }
            }
            .onAppear {
                serverURL = connectionManager.serverURL ?? ""
                password = connectionManager.serverPassword ?? ""
                clipboardSync = connectionManager.clipboardSyncEnabled
            }
        }
    }

    private func saveAndConnect() {
        var url = serverURL.trimmingCharacters(in: .whitespacesAndNewlines)

        // Add ws:// prefix if missing
        if !url.hasPrefix("ws://") && !url.hasPrefix("wss://") {
            url = "ws://\(url)"
        }

        connectionManager.setServerURL(url)
        connectionManager.serverPassword = password.isEmpty ? nil : password
        connectionManager.clipboardSyncEnabled = clipboardSync
        connectionManager.connect()
        dismiss()
    }
}

struct DiscoveredServersView: View {
    @Binding var serverURL: String
    @StateObject private var bonjourBrowser = BonjourBrowser()

    var body: some View {
        if bonjourBrowser.discoveredServers.isEmpty {
            HStack {
                ProgressView()
                    .scaleEffect(0.8)
                Text("Searching...")
                    .foregroundColor(.secondary)
            }
        } else {
            ForEach(bonjourBrowser.discoveredServers) { server in
                Button(action: {
                    serverURL = server.url
                }) {
                    HStack {
                        VStack(alignment: .leading) {
                            Text(server.name)
                                .foregroundColor(.primary)
                            Text(server.url)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        if serverURL == server.url {
                            Image(systemName: "checkmark")
                                .foregroundColor(.blue)
                        }
                    }
                }
            }
        }
    }
}

// Bonjour browser for discovering servers
class BonjourBrowser: NSObject, ObservableObject, NetServiceBrowserDelegate, NetServiceDelegate {
    @Published var discoveredServers: [DiscoveredServer] = []

    private var browser: NetServiceBrowser?
    private var services: [NetService] = []

    struct DiscoveredServer: Identifiable {
        let id = UUID()
        let name: String
        let url: String
    }

    override init() {
        super.init()
        startBrowsing()
    }

    func startBrowsing() {
        browser = NetServiceBrowser()
        browser?.delegate = self
        browser?.searchForServices(ofType: "_http._tcp.", inDomain: "local.")
    }

    func netServiceBrowser(_ browser: NetServiceBrowser, didFind service: NetService, moreComing: Bool) {
        // Look for our TermAway services
        if service.name.contains("TermAway") {
            services.append(service)
            service.delegate = self
            service.resolve(withTimeout: 5.0)
        }
    }

    func netServiceDidResolveAddress(_ sender: NetService) {
        let port = sender.port

        // Try to get IP address from resolved addresses
        var ipAddress: String?
        if let addresses = sender.addresses {
            for addressData in addresses {
                var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                addressData.withUnsafeBytes { ptr in
                    let sockaddrPtr = ptr.baseAddress!.assumingMemoryBound(to: sockaddr.self)
                    let len = socklen_t(addressData.count)
                    if getnameinfo(sockaddrPtr, len, &hostname, socklen_t(hostname.count), nil, 0, NI_NUMERICHOST) == 0 {
                        let addr = String(cString: hostname)
                        // Prefer IPv4 addresses (no colons)
                        if !addr.contains(":") && ipAddress == nil {
                            ipAddress = addr
                        }
                    }
                }
            }
        }

        // Fall back to hostname if no IP found, clean it up
        let host: String
        if let ip = ipAddress {
            host = ip
        } else if let hostName = sender.hostName {
            // Remove trailing dot and clean up domain suffixes
            host = hostName
                .trimmingCharacters(in: CharacterSet(charactersIn: "."))
                .replacingOccurrences(of: ".local", with: ".local")
        } else {
            return
        }

        let url = "ws://\(host):\(port)"

        DispatchQueue.main.async {
            if !self.discoveredServers.contains(where: { $0.url == url }) {
                self.discoveredServers.append(DiscoveredServer(name: sender.name, url: url))
            }
        }
    }

    func netServiceBrowser(_ browser: NetServiceBrowser, didRemove service: NetService, moreComing: Bool) {
        services.removeAll { $0 == service }
        DispatchQueue.main.async {
            self.discoveredServers.removeAll { $0.name == service.name }
        }
    }
}

#Preview {
    ServerSettingsView()
        .environmentObject(ConnectionManager())
}
