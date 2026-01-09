import SwiftUI

struct ContentView: View {
    @EnvironmentObject var connectionManager: ConnectionManager
    @State private var showingServerSheet = false
    @State private var columnVisibility = NavigationSplitViewVisibility.automatic

    var body: some View {
        Group {
            if connectionManager.isConnected {
                // Use NavigationSplitView for iPad, regular NavigationStack for iPhone
                if UIDevice.current.userInterfaceIdiom == .pad {
                    NavigationSplitView(columnVisibility: $columnVisibility) {
                        SessionSidebarView()
                    } detail: {
                        TerminalDetailView()
                    }
                } else {
                    NavigationStack {
                        SessionCompactView()
                    }
                }
            } else {
                NavigationStack {
                    ConnectView(showingServerSheet: $showingServerSheet)
                        .toolbar {
                            ToolbarItem(placement: .navigationBarTrailing) {
                                ConnectionStatusView()
                            }
                        }
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbarBackgroundVisibility(.hidden, for: .navigationBar)
                }
            }
        }
        .sheet(isPresented: $showingServerSheet) {
            ServerSettingsView()
                .presentationBackground(.ultraThinMaterial)
        }
        .preferredColorScheme(.dark)
    }
}

// MARK: - Session Sidebar (iPad)
struct SessionSidebarView: View {
    @EnvironmentObject var connectionManager: ConnectionManager
    @State private var showingNewSession = false
    @State private var newSessionName = ""

    var body: some View {
        List {
            ForEach(connectionManager.sessions) { session in
                SessionRowView(session: session)
                    .listRowBackground(
                        connectionManager.currentSession?.name == session.name
                            ? Color.green.opacity(0.2)
                            : Color.clear
                    )
            }
        }
        .navigationTitle("Sessions")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: { showingNewSession = true }) {
                    Image(systemName: "plus.circle.fill")
                        .symbolRenderingMode(.hierarchical)
                        .font(.title3)
                }
            }
        }
        .alert("New Session", isPresented: $showingNewSession) {
            TextField("Session name", text: $newSessionName)
            Button("Cancel", role: .cancel) {
                newSessionName = ""
            }
            Button("Create") {
                if !newSessionName.isEmpty {
                    connectionManager.createSession(newSessionName)
                    connectionManager.attachToSession(newSessionName)
                    newSessionName = ""
                }
            }
        }
        .overlay {
            if connectionManager.sessions.isEmpty {
                NoSessionView(showingNewSession: $showingNewSession)
            }
        }
    }
}

// MARK: - Session Row
struct SessionRowView: View {
    @EnvironmentObject var connectionManager: ConnectionManager
    let session: Session
    @State private var showingRenameAlert = false
    @State private var newName = ""

    var isActive: Bool {
        connectionManager.currentSession?.name == session.name
    }

    var body: some View {
        Button(action: {
            connectionManager.attachToSession(session.name)
        }) {
            HStack(spacing: 12) {
                Image(systemName: "terminal.fill")
                    .font(.title3)
                    .foregroundStyle(
                        isActive
                            ? LinearGradient(colors: [.green, .cyan], startPoint: .topLeading, endPoint: .bottomTrailing)
                            : LinearGradient(colors: [.gray], startPoint: .topLeading, endPoint: .bottomTrailing)
                    )
                    .frame(width: 32)

                VStack(alignment: .leading, spacing: 4) {
                    Text(session.name)
                        .font(.headline)
                        .foregroundColor(.primary)

                    HStack(spacing: 8) {
                        Circle()
                            .fill(session.clientCount > 0 ? Color.green : Color.gray.opacity(0.5))
                            .frame(width: 6, height: 6)

                        Text(session.clientCount > 0 ? "Active" : "Idle")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        if session.clientCount > 1 {
                            Text("- \(session.clientCount) clients")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }

                Spacer()

                if isActive {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                        .font(.title3)
                }
            }
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) {
                connectionManager.killSession(session.name)
            } label: {
                Label("Delete", systemImage: "trash")
            }

            Button {
                newName = session.name
                showingRenameAlert = true
            } label: {
                Label("Rename", systemImage: "pencil")
            }
            .tint(.blue)
        }
        .contextMenu {
            Button(action: {
                connectionManager.attachToSession(session.name)
            }) {
                Label("Attach", systemImage: "arrow.right.circle")
            }

            Button(action: {
                newName = session.name
                showingRenameAlert = true
            }) {
                Label("Rename", systemImage: "pencil")
            }

            Button(role: .destructive, action: {
                connectionManager.killSession(session.name)
            }) {
                Label("Delete", systemImage: "trash")
            }
        }
        .alert("Rename Session", isPresented: $showingRenameAlert) {
            TextField("New name", text: $newName)
            Button("Cancel", role: .cancel) {
                newName = ""
            }
            Button("Rename") {
                if !newName.isEmpty && newName != session.name {
                    connectionManager.renameSession(session.name, newName)
                }
                newName = ""
            }
        }
    }
}

// MARK: - Terminal Detail View (iPad)
struct TerminalDetailView: View {
    @EnvironmentObject var connectionManager: ConnectionManager

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let currentSession = connectionManager.currentSession {
                TerminalContainerView(session: currentSession)
                    .navigationTitle(currentSession.name)
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .navigationBarTrailing) {
                            ConnectionStatusView()
                        }
                    }
            } else {
                VStack(spacing: 20) {
                    Image(systemName: "sidebar.left")
                        .font(.system(size: 64))
                        .foregroundStyle(.linearGradient(
                            colors: [.blue, .cyan],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ))

                    Text("Select a Session")
                        .font(.title2.weight(.semibold))
                        .foregroundColor(.white)

                    Text("Choose a session from the sidebar")
                        .foregroundColor(.secondary)
                }
            }
        }
        .toolbarBackgroundVisibility(.hidden, for: .navigationBar)
    }
}

// MARK: - Compact View (iPhone)
struct SessionCompactView: View {
    @EnvironmentObject var connectionManager: ConnectionManager
    @State private var showingNewSession = false
    @State private var newSessionName = ""
    @State private var showingSessionList = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

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
        }
        .navigationTitle(connectionManager.currentSession?.name ?? "Terminal")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackgroundVisibility(.hidden, for: .navigationBar)
        .toolbar {
            ToolbarItemGroup(placement: .navigationBarLeading) {
                if connectionManager.sessions.count > 1 {
                    Button(action: { showingSessionList = true }) {
                        HStack(spacing: 6) {
                            Image(systemName: "square.stack.3d.up")
                                .font(.body.weight(.semibold))
                            Text("\(connectionManager.sessions.count)")
                                .font(.caption.weight(.bold))
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(.ultraThinMaterial, in: Capsule())
                    }
                }
            }

            ToolbarItemGroup(placement: .navigationBarTrailing) {
                Button(action: { showingNewSession = true }) {
                    Image(systemName: "plus.circle.fill")
                        .symbolRenderingMode(.hierarchical)
                        .font(.title3)
                }
                .buttonStyle(.plain)

                ConnectionStatusView()
            }
        }
        .sheet(isPresented: $showingSessionList) {
            NavigationStack {
                SessionListSheet()
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .alert("New Session", isPresented: $showingNewSession) {
            TextField("Session name", text: $newSessionName)
            Button("Cancel", role: .cancel) {
                newSessionName = ""
            }
            Button("Create") {
                if !newSessionName.isEmpty {
                    connectionManager.createSession(newSessionName)
                    connectionManager.attachToSession(newSessionName)
                    newSessionName = ""
                }
            }
        }
    }
}

// MARK: - Session List Sheet (iPhone)
struct SessionListSheet: View {
    @EnvironmentObject var connectionManager: ConnectionManager
    @Environment(\.dismiss) var dismiss
    @State private var showingNewSession = false
    @State private var newSessionName = ""

    var body: some View {
        List {
            Section {
                ForEach(connectionManager.sessions) { session in
                    SessionRowView(session: session)
                        .onTapGesture {
                            connectionManager.attachToSession(session.name)
                            dismiss()
                        }
                }
            } header: {
                HStack {
                    Text("Active Sessions")
                    Spacer()
                    Text("\(connectionManager.sessions.count)")
                        .foregroundColor(.secondary)
                }
            }
        }
        .navigationTitle("Sessions")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: { showingNewSession = true }) {
                    Image(systemName: "plus.circle.fill")
                        .symbolRenderingMode(.hierarchical)
                }
            }

            ToolbarItem(placement: .navigationBarLeading) {
                Button("Done") {
                    dismiss()
                }
            }
        }
        .alert("New Session", isPresented: $showingNewSession) {
            TextField("Session name", text: $newSessionName)
            Button("Cancel", role: .cancel) {
                newSessionName = ""
            }
            Button("Create") {
                if !newSessionName.isEmpty {
                    connectionManager.createSession(newSessionName)
                    connectionManager.attachToSession(newSessionName)
                    newSessionName = ""
                }
            }
        }
    }
}

// MARK: - No Session View
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

// MARK: - Connect View
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

// MARK: - Connection Status
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

#Preview {
    ContentView()
        .environmentObject(ConnectionManager())
}
