import SwiftUI

struct ContentView: View {
    @EnvironmentObject var connectionManager: ConnectionManager
    @State private var showingServerSheet = false
    @State private var showingNewSession = false
    @State private var showingThemeSettings = false
    @State private var newSessionName = ""

    var body: some View {
        NavigationStack {
            ZStack {
                // Liquid Glass background
                Color.black.ignoresSafeArea()

                if connectionManager.isConnected {
                    if let currentSession = connectionManager.currentSession {
                        TerminalContainerView(session: currentSession)
                    } else if connectionManager.sessions.isEmpty {
                        NoSessionView(showingNewSession: $showingNewSession)
                    } else {
                        // Auto-select first session
                        Color.clear.onAppear {
                            if let first = connectionManager.sessions.first {
                                connectionManager.attachToSession(first.name)
                            }
                        }
                    }
                } else {
                    ConnectView(showingServerSheet: $showingServerSheet)
                }
            }
            .toolbarBackgroundVisibility(.hidden, for: .navigationBar)
            .toolbar {
                ToolbarItemGroup(placement: .navigationBarLeading) {
                    if connectionManager.isConnected {
                        SessionTabsView()
                    }
                }

                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    if connectionManager.isConnected {
                        Button(action: { showingNewSession = true }) {
                            Image(systemName: "plus.circle.fill")
                                .symbolRenderingMode(.hierarchical)
                                .font(.title2)
                        }
                        .buttonStyle(.plain)

                        Button(action: { showingThemeSettings = true }) {
                            Image(systemName: "paintpalette.fill")
                                .symbolRenderingMode(.hierarchical)
                                .font(.title2)
                        }
                        .buttonStyle(.plain)
                    }

                    ConnectionStatusView()
                }
            }
            .navigationBarTitleDisplayMode(.inline)
        }
        .sheet(isPresented: $showingServerSheet) {
            ServerSettingsView()
                .presentationBackground(.ultraThinMaterial)
        }
        .sheet(isPresented: $showingThemeSettings) {
            ThemeSettingsView()
                .presentationBackground(.ultraThinMaterial)
        }
        .alert("New Session", isPresented: $showingNewSession) {
            TextField("Session name", text: $newSessionName)
            Button("Cancel", role: .cancel) {
                newSessionName = ""
            }
            Button("Create") {
                if !newSessionName.isEmpty {
                    connectionManager.createSession(newSessionName)
                    newSessionName = ""
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}

struct NoSessionView: View {
    @Binding var showingNewSession: Bool

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "terminal.fill")
                .font(.system(size: 64))
                .foregroundStyle(.linearGradient(
                    colors: [.blue, .cyan],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ))

            Text("No Active Session")
                .font(.title2.weight(.semibold))
                .foregroundColor(.white)

            Text("Create a new session to get started")
                .foregroundColor(.secondary)

            Button(action: { showingNewSession = true }) {
                Label("Create Session", systemImage: "plus")
                    .fontWeight(.semibold)
                    .padding(.horizontal, 28)
                    .padding(.vertical, 14)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.capsule)
            .tint(.blue)
        }
        .padding(32)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24))
    }
}

struct ConnectView: View {
    @EnvironmentObject var connectionManager: ConnectionManager
    @Binding var showingServerSheet: Bool

    var body: some View {
        VStack(spacing: 28) {
            // Animated network icon
            Image(systemName: "network")
                .font(.system(size: 64))
                .foregroundStyle(.linearGradient(
                    colors: [.cyan, .blue],
                    startPoint: .top,
                    endPoint: .bottom
                ))
                .symbolEffect(.pulse, options: .repeating)

            VStack(spacing: 8) {
                Text("Connect to Server")
                    .font(.title2.weight(.semibold))
                    .foregroundColor(.white)

                if let serverURL = connectionManager.serverURL {
                    Text(serverURL.replacingOccurrences(of: "ws://", with: ""))
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 6)
                        .background(.ultraThinMaterial, in: Capsule())
                }
            }

            VStack(spacing: 16) {
                Button(action: {
                    connectionManager.connect()
                }) {
                    HStack(spacing: 10) {
                        if connectionManager.isConnecting {
                            ProgressView()
                                .tint(.white)
                        } else {
                            Image(systemName: "link")
                        }
                        Text(connectionManager.isConnecting ? "Connecting..." : "Connect")
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.capsule)
                .tint(.blue)
                .disabled(connectionManager.isConnecting)

                Button(action: { showingServerSheet = true }) {
                    Label("Server Settings", systemImage: "gear")
                        .font(.subheadline)
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.capsule)
                .tint(.secondary)
            }
            .frame(maxWidth: 300)

            if let error = connectionManager.lastError {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundColor(.red)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(.red.opacity(0.15), in: RoundedRectangle(cornerRadius: 10))
            }
        }
        .padding(36)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 28))
    }
}

struct ConnectionStatusView: View {
    @EnvironmentObject var connectionManager: ConnectionManager

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(connectionManager.isConnected ? Color.green : Color.red)
                .frame(width: 10, height: 10)
                .shadow(color: connectionManager.isConnected ? .green.opacity(0.6) : .red.opacity(0.6), radius: 4)

            Text(connectionManager.isConnected ? "Connected" : "Disconnected")
                .font(.caption.weight(.medium))
                .foregroundColor(connectionManager.isConnected ? .green : .secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial, in: Capsule())
    }
}

struct SessionTabsView: View {
    @EnvironmentObject var connectionManager: ConnectionManager

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(connectionManager.sessions) { session in
                    SessionTabButton(session: session)
                }
            }
        }
    }
}

struct SessionTabButton: View {
    @EnvironmentObject var connectionManager: ConnectionManager
    let session: Session

    var isActive: Bool {
        connectionManager.currentSession?.name == session.name
    }

    var body: some View {
        Button(action: {
            connectionManager.attachToSession(session.name)
        }) {
            HStack(spacing: 8) {
                Image(systemName: "terminal")
                    .font(.caption)

                Text(session.name)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)

                if isActive {
                    Button(action: {
                        connectionManager.killSession(session.name)
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.caption)
                            .symbolRenderingMode(.hierarchical)
                            .foregroundColor(.white.opacity(0.8))
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(
                isActive
                    ? AnyShapeStyle(.linearGradient(colors: [.green, .green.opacity(0.8)], startPoint: .top, endPoint: .bottom))
                    : AnyShapeStyle(.ultraThinMaterial)
            )
            .foregroundColor(isActive ? .white : .primary)
            .clipShape(Capsule())
            .shadow(color: isActive ? .green.opacity(0.3) : .clear, radius: 4)
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    ContentView()
        .environmentObject(ConnectionManager())
}
