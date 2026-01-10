import SwiftUI

// MARK: - iOS 18+ Toolbar Visibility Extension
extension View {
    @ViewBuilder
    func hideToolbarBackground() -> some View {
        if #available(iOS 18.0, *) {
            self.toolbarBackgroundVisibility(.hidden, for: .navigationBar)
        } else {
            self
        }
    }

    @ViewBuilder
    func glassCircleBackground() -> some View {
        self.background {
            if #available(iOS 26.0, *) {
                Circle().fill(.clear).glassEffect()
            } else {
                Circle().fill(.thinMaterial)
            }
        }
    }

    @ViewBuilder
    func glassPillBackground() -> some View {
        self.background {
            if #available(iOS 26.0, *) {
                Capsule().fill(.clear).glassEffect()
            } else {
                Capsule().fill(.thinMaterial)
            }
        }
    }
}

struct ContentView: View {
    @EnvironmentObject var connectionManager: ConnectionManager
    @EnvironmentObject var themeManager: ThemeManager
    @State private var showingServerSheet = false
    @State private var columnVisibility = NavigationSplitViewVisibility.automatic
    @State private var passwordInput = ""

    // Show password prompt when auth required but not authenticated
    private var needsPasswordPrompt: Bool {
        connectionManager.isConnected &&
        connectionManager.authRequired &&
        !connectionManager.isAuthenticated &&
        !connectionManager.isAuthenticating
    }

    var body: some View {
        Group {
            if connectionManager.isConnected && connectionManager.isAuthenticated {
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
            } else if connectionManager.isConnected && !connectionManager.authRequired {
                // Connected but no auth required
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
                ConnectView(showingServerSheet: $showingServerSheet)
            }
        }
        .sheet(isPresented: $showingServerSheet) {
            ServerSettingsView()
                .presentationBackground(.ultraThinMaterial)
        }
        .alert("Password Required", isPresented: .constant(needsPasswordPrompt)) {
            SecureField("Password", text: $passwordInput)
            Button("Cancel", role: .cancel) {
                connectionManager.disconnect()
                passwordInput = ""
            }
            Button("Connect") {
                connectionManager.authenticate(password: passwordInput)
                passwordInput = ""
            }
        } message: {
            if let error = connectionManager.lastError {
                Text(error)
            } else {
                Text("Enter the server password")
            }
        }
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
                            ? Color.brandOrange.opacity(0.2)
                            : Color.clear
                    )
            }
        }
        .navigationTitle("Sessions")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: { showingNewSession = true }) {
                    Image(systemName: "plus")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.primary.opacity(0.9))
                        .frame(width: 34, height: 34)
                }
                .background {
                    if #available(iOS 26.0, *) {
                        Circle().fill(.clear).glassEffect()
                    } else {
                        Circle().fill(.secondary.opacity(0.15))
                    }
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
                            Text("• \(session.clientCount) clients")
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
            .tint(.brandOrange)
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
    @EnvironmentObject var themeManager: ThemeManager
    @State private var showingSettings = false

    // Icon color adapts to terminal background
    private var iconColor: Color {
        themeManager.terminalOverlayColor
    }

    var body: some View {
        ZStack {
            Color(uiColor: themeManager.currentTheme.backgroundColor).ignoresSafeArea()

            if let currentSession = connectionManager.currentSession {
                TerminalContainerView(session: currentSession)
                    .navigationTitle(currentSession.name)
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .navigationBarTrailing) {
                            HStack(spacing: 10) {
                                // Connected status pill
                                HStack(spacing: 6) {
                                    Circle()
                                        .fill(Color.green)
                                        .frame(width: 8, height: 8)
                                    Text("Connected")
                                        .font(.subheadline.weight(.medium))
                                }
                                .foregroundColor(.green)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 10)
                                .background {
                                    if #available(iOS 26.0, *) {
                                        Capsule().fill(.clear).glassEffect()
                                    } else {
                                        Capsule().fill(iconColor.opacity(0.15))
                                    }
                                }

                                // Settings button (separate)
                                Button(action: { showingSettings = true }) {
                                    Image(systemName: "gearshape.fill")
                                        .font(.system(size: 15, weight: .medium))
                                        .foregroundStyle(iconColor.opacity(0.9))
                                        .frame(width: 38, height: 38)
                                }
                                .background {
                                    if #available(iOS 26.0, *) {
                                        Circle().fill(.clear).glassEffect()
                                    } else {
                                        Circle().fill(iconColor.opacity(0.15))
                                    }
                                }
                            }
                        }
                    }
            } else {
                VStack(spacing: 20) {
                    Image(systemName: "sidebar.left")
                        .font(.system(size: 64))
                        .foregroundStyle(.linearGradient(
                            colors: [.brandAmber, .brandOrange],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ))

                    Text("Select a Session")
                        .font(.title2.weight(.semibold))
                        .foregroundColor(.white)

                    Text("Choose a session from the sidebar")
                        .foregroundColor(.secondary)

                    // Settings button when no session
                    Button(action: { showingSettings = true }) {
                        HStack(spacing: 8) {
                            Image(systemName: "gearshape.fill")
                                .font(.subheadline)
                            Text("Settings")
                                .font(.system(size: 15, weight: .medium))
                        }
                        .foregroundColor(.secondary)
                        .padding(.vertical, 12)
                        .padding(.horizontal, 24)
                    }
                    .background {
                        if #available(iOS 26.0, *) {
                            RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.clear).glassEffect()
                        } else {
                            RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.secondary.opacity(0.12))
                        }
                    }
                    .padding(.top, 16)
                }
            }
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView()
        }
        .hideToolbarBackground()
        .preferredColorScheme(.dark) // Terminal always dark
    }
}

// MARK: - Compact View (iPhone)
struct SessionCompactView: View {
    @EnvironmentObject var connectionManager: ConnectionManager
    @EnvironmentObject var themeManager: ThemeManager
    @State private var showingNewSession = false
    @State private var newSessionName = ""
    @State private var showingSessionList = false
    @State private var showingSettings = false

    // Icon color adapts to terminal background (white for dark themes, black for light)
    private var iconColor: Color {
        themeManager.terminalOverlayColor
    }

    var body: some View {
        ZStack {
            // Terminal background color
            Color(uiColor: themeManager.currentTheme.backgroundColor)
                .ignoresSafeArea()

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

            // Custom top bar overlay: Session Name + | .... | Connected | Gear
            VStack {
                HStack(spacing: 10) {
                    // Session name (plain label, not tappable)
                    Text(connectionManager.currentSession?.name ?? "Terminal")
                        .font(.headline)
                        .foregroundColor(iconColor)

                    // + button in glass circle (new session) - right next to name
                    Button(action: { showingNewSession = true }) {
                        Image(systemName: "plus")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(iconColor.opacity(0.9))
                            .frame(width: 38, height: 38)
                    }
                    .background {
                        if #available(iOS 26.0, *) {
                            Circle().fill(.clear).glassEffect()
                        } else {
                            Circle().fill(iconColor.opacity(0.15))
                        }
                    }

                    Spacer()

                    // Connected status pill (tappable to show sessions)
                    Button(action: { showingSessionList = true }) {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(Color.green)
                                .frame(width: 8, height: 8)
                            Text("Connected")
                                .font(.subheadline.weight(.medium))
                        }
                        .foregroundColor(.green)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                    }
                    .background {
                        if #available(iOS 26.0, *) {
                            Capsule().fill(.clear).glassEffect()
                        } else {
                            Capsule().fill(iconColor.opacity(0.15))
                        }
                    }

                    // Gear icon in glass circle (settings)
                    Button(action: { showingSettings = true }) {
                        Image(systemName: "gearshape.fill")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(iconColor.opacity(0.9))
                            .frame(width: 38, height: 38)
                    }
                    .background {
                        if #available(iOS 26.0, *) {
                            Circle().fill(.clear).glassEffect()
                        } else {
                            Circle().fill(iconColor.opacity(0.15))
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)

                Spacer()
            }
        }
        .navigationBarHidden(true)
        .sheet(isPresented: $showingSessionList) {
            NavigationStack {
                SessionListSheet()
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView()
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
        .onChange(of: connectionManager.sessions) { _, newSessions in
            // Auto-select first session if none selected
            if connectionManager.currentSession == nil, let first = newSessions.first {
                connectionManager.attachToSession(first.name)
            }
        }
        .onAppear {
            // Auto-select first session on appear if none selected
            if connectionManager.currentSession == nil, let first = connectionManager.sessions.first {
                connectionManager.attachToSession(first.name)
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
                    Image(systemName: "plus")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.primary)
                        .frame(width: 32, height: 32)
                }
                .background {
                    if #available(iOS 26.0, *) {
                        Circle().fill(.clear).glassEffect()
                    } else {
                        Circle().fill(.secondary.opacity(0.15))
                    }
                }
            }

            ToolbarItem(placement: .navigationBarLeading) {
                Button(action: { dismiss() }) {
                    Text("Done")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.primary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                }
                .background {
                    if #available(iOS 26.0, *) {
                        Capsule().fill(.clear).glassEffect()
                    } else {
                        Capsule().fill(.secondary.opacity(0.15))
                    }
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
    @EnvironmentObject var connectionManager: ConnectionManager
    @Binding var showingNewSession: Bool
    @State private var pulseScale: CGFloat = 1.0

    var body: some View {
        VStack(spacing: 28) {
            // Icon with glow
            ZStack {
                Image("LogoIcon")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 90, height: 90)
                    .blur(radius: 25)
                    .opacity(0.5)
                    .scaleEffect(pulseScale)

                Image("LogoIcon")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 72, height: 72)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .onAppear {
                withAnimation(.easeInOut(duration: 2).repeatForever(autoreverses: true)) {
                    pulseScale = 1.08
                }
            }

            VStack(spacing: 8) {
                Text("No Active Session")
                    .font(.title2.weight(.semibold))
                    .foregroundColor(.primary)

                Text("Create a new session to get started")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            Button(action: { showingNewSession = true }) {
                HStack(spacing: 10) {
                    Image(systemName: "plus")
                        .font(.body.weight(.semibold))
                    Text("Create Session")
                        .font(.body.weight(.semibold))
                }
                .padding(.horizontal, 32)
                .padding(.vertical, 16)
                .background(Color.brandOrange)
                .foregroundColor(.white)
                .clipShape(Capsule())
                .shadow(color: .brandOrange.opacity(0.4), radius: 12, y: 6)
            }

            // Disconnect option
            Button(action: { connectionManager.disconnect() }) {
                HStack(spacing: 6) {
                    Image(systemName: "xmark.circle")
                        .font(.subheadline)
                    Text("Disconnect")
                        .font(.subheadline.weight(.medium))
                }
                .foregroundColor(.secondary)
            }
            .padding(.top, 8)
        }
    }
}

// MARK: - Connect View
struct ConnectView: View {
    @EnvironmentObject var connectionManager: ConnectionManager
    @Environment(\.colorScheme) var colorScheme
    @Binding var showingServerSheet: Bool
    @State private var animateGradient = false
    @State private var pulseScale: CGFloat = 1.0

    var body: some View {
        ZStack {
            // Adaptive background
            Color(uiColor: .systemBackground)
                .ignoresSafeArea()

            // Animated background blobs
            GeometryReader { geo in
                ZStack {
                    Circle()
                        .fill(Color.brandOrange.opacity(colorScheme == .dark ? 0.25 : 0.15))
                        .frame(width: 250, height: 250)
                        .blur(radius: 80)
                        .offset(x: animateGradient ? 60 : -60, y: animateGradient ? -40 : 40)

                    Circle()
                        .fill(Color.brandAmber.opacity(colorScheme == .dark ? 0.2 : 0.12))
                        .frame(width: 200, height: 200)
                        .blur(radius: 70)
                        .offset(x: animateGradient ? -70 : 70, y: animateGradient ? 60 : -60)

                    Circle()
                        .fill(Color.brandCream.opacity(colorScheme == .dark ? 0.15 : 0.1))
                        .frame(width: 220, height: 220)
                        .blur(radius: 75)
                        .offset(x: animateGradient ? 40 : -40, y: animateGradient ? 100 : -30)
                }
                .frame(width: geo.size.width, height: geo.size.height)
            }
            .onAppear {
                withAnimation(.easeInOut(duration: 5).repeatForever(autoreverses: true)) {
                    animateGradient = true
                }
            }

            // Main content
            VStack(spacing: 40) {
                Spacer()

                // App icon with glow
                ZStack {
                    // Glow effect
                    Image("LogoIcon")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 120, height: 120)
                        .blur(radius: 30)
                        .opacity(0.5)
                        .scaleEffect(pulseScale)

                    Image("LogoIcon")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 100, height: 100)
                        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                        .shadow(color: .brandOrange.opacity(0.3), radius: 20, y: 8)
                }
                .onAppear {
                    withAnimation(.easeInOut(duration: 2.5).repeatForever(autoreverses: true)) {
                        pulseScale = 1.1
                    }
                }

                VStack(spacing: 12) {
                    Text("TermAway")
                        .font(.system(size: 36, weight: .bold))
                        .foregroundColor(.primary)

                    Text("Your Mac terminal, on your iPad")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.secondary)
                }

                // Server URL badge
                if let serverURL = connectionManager.serverURL {
                    HStack(spacing: 8) {
                        Circle()
                            .fill(connectionManager.isConnecting ? .yellow : .secondary.opacity(0.5))
                            .frame(width: 8, height: 8)

                        Text(serverURL.replacingOccurrences(of: "ws://", with: "").replacingOccurrences(of: "wss://", with: ""))
                            .font(.system(.footnote, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal, 18)
                    .padding(.vertical, 12)
                    .background(.secondary.opacity(0.1), in: Capsule())
                }

                Spacer()

                // Connect button
                Button(action: { connectionManager.connect() }) {
                    HStack(spacing: 12) {
                        if connectionManager.isConnecting {
                            ProgressView()
                                .tint(.white)
                        }
                        Text(connectionManager.isConnecting ? "Connecting..." : "Connect")
                            .font(.system(size: 17, weight: .semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 24)
                    .padding(.vertical, 18)
                    .background(Color.brandOrange)
                    .foregroundColor(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .shadow(color: .brandOrange.opacity(0.3), radius: 12, y: 6)
                }
                .disabled(connectionManager.isConnecting)
                .frame(maxWidth: 300)
                .padding(.horizontal, 24)

                // Error message
                if let error = connectionManager.lastError {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.red)
                        Text(error)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.red)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 14)
                    .background(.red.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
                    .padding(.horizontal, 24)
                }

                Spacer()

                // Settings button at bottom
                Button(action: { showingServerSheet = true }) {
                    HStack(spacing: 8) {
                        Image(systemName: "gearshape.fill")
                            .font(.subheadline)
                        Text("Settings")
                            .font(.system(size: 15, weight: .medium))
                    }
                    .foregroundColor(.secondary)
                    .padding(.vertical, 14)
                    .padding(.horizontal, 28)
                }
                .background {
                    if #available(iOS 26.0, *) {
                        RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.clear).glassEffect()
                    } else {
                        RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.secondary.opacity(0.12))
                    }
                }
                .padding(.bottom, 40)
            }
        }
    }
}

// MARK: - Connection Status
struct ConnectionStatusView: View {
    @EnvironmentObject var connectionManager: ConnectionManager

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(connectionManager.isConnected ? Color.green : Color.red)
                .frame(width: 8, height: 8)

            Text(connectionManager.isConnected ? "Connected" : "Disconnected")
                .font(.subheadline.weight(.medium))
        }
        .foregroundColor(connectionManager.isConnected ? .green : .red)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .glassPillBackground()
    }
}

#Preview {
    ContentView()
        .environmentObject(ConnectionManager())
}
