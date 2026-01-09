import SwiftUI

struct ServerSettingsView: View {
    @EnvironmentObject var connectionManager: ConnectionManager
    @Environment(\.dismiss) var dismiss

    @State private var serverURL: String = ""
    @State private var showingScanner = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        Image(systemName: "link")
                            .foregroundColor(.blue)
                            .frame(width: 28)

                        TextField("ws://192.168.1.100:3000", text: $serverURL)
                            .keyboardType(.URL)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    }
                } header: {
                    Label("Server Connection", systemImage: "server.rack")
                } footer: {
                    Text("Enter the WebSocket URL of your TermAway server")
                }

                Section {
                    DiscoveredServersView(serverURL: $serverURL)
                } header: {
                    Label("Discovered Servers", systemImage: "bonjour")
                } footer: {
                    Text("Servers advertising via Bonjour will appear automatically")
                }

                Section {
                    Button(action: saveAndConnect) {
                        HStack {
                            Spacer()
                            Label("Save & Connect", systemImage: "link.circle.fill")
                                .fontWeight(.semibold)
                            Spacer()
                        }
                        .padding(.vertical, 4)
                    }
                    .disabled(serverURL.isEmpty)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.black.opacity(0.8))
            .navigationTitle("Server Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .onAppear {
                serverURL = connectionManager.serverURL ?? ""
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
        guard let hostName = sender.hostName else { return }

        let port = sender.port
        let url = "ws://\(hostName.replacingOccurrences(of: ".local.", with: ".local")):\(port)"

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
