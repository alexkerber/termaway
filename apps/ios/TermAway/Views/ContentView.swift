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
                        TerminalDetailView(columnVisibility: $columnVisibility)
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
                        TerminalDetailView(columnVisibility: $columnVisibility)
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
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                HStack(spacing: 10) {
                    Button {
                        showingNewSession = true
                    } label: {
                        Image(systemName: "plus")
                    }

                    Text("Sessions")
                        .font(.headline)
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

// MARK: - Session Row
struct SessionRowView: View {
    @EnvironmentObject var connectionManager: ConnectionManager
    let session: Session
    @State private var showingRenameAlert = false
    @State private var showingDeleteConfirmation = false
    @State private var newName = ""

    var isActive: Bool {
        connectionManager.currentSession?.name == session.name
    }

    var body: some View {
        Button(action: {
            // Only attach if not already active
            if !isActive {
                connectionManager.attachToSession(session.name)
            }
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
            Button {
                showingDeleteConfirmation = true
            } label: {
                Image(systemName: "trash.fill")
            }
            .tint(.red)

            Button {
                newName = session.name
                showingRenameAlert = true
            } label: {
                Image(systemName: "pencil.line")
            }
            .tint(.brandOrange)
        }
        .contextMenu {
            Button(action: {
                if !isActive {
                    connectionManager.attachToSession(session.name)
                }
            }) {
                Label("Attach", systemImage: "arrow.right.circle")
            }
            .disabled(isActive)

            Button(action: {
                newName = session.name
                showingRenameAlert = true
            }) {
                Label("Rename", systemImage: "pencil")
            }

            Button(role: .destructive, action: {
                showingDeleteConfirmation = true
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
        .alert("Delete Session?", isPresented: $showingDeleteConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                connectionManager.killSession(session.name)
            }
        } message: {
            Text("This will terminate \"\(session.name)\" and cannot be undone.")
        }
    }
}

// MARK: - Terminal Detail View (iPad)
struct TerminalDetailView: View {
    @EnvironmentObject var connectionManager: ConnectionManager
    @EnvironmentObject var themeManager: ThemeManager
    @Binding var columnVisibility: NavigationSplitViewVisibility
    @State private var showingSettings = false
    @State private var showingNewSession = false
    @State private var showingSessionList = false
    @State private var newSessionName = ""

    // Icon color adapts to terminal background
    private var iconColor: Color {
        themeManager.terminalOverlayColor
    }

    // Dynamic sheet height based on session count
    private var sessionSheetDetents: Set<PresentationDetent> {
        let count = connectionManager.sessions.count
        let baseHeight: CGFloat = 150
        let rowHeight: CGFloat = 80
        let calculatedHeight = baseHeight + (CGFloat(count) * rowHeight)
        let maxHeight: CGFloat = 650
        return [.height(min(calculatedHeight, maxHeight)), .large]
    }

    var body: some View {
        ZStack {
            Color(uiColor: themeManager.currentTheme.backgroundColor).ignoresSafeArea()

            if let currentSession = connectionManager.currentSession {
                TerminalContainerView(session: currentSession)
                    .id(currentSession.name) // Force new view instance per session
                    .navigationBarHidden(true)

                // Custom top bar overlay (same as iPhone) - only when session active
                VStack {
                    HStack(spacing: 10) {
                        // + button in glass circle (new session)
                        GlassCircleButton(
                            icon: "plus",
                            color: iconColor,
                            action: { showingNewSession = true }
                        )

                        // Session name (tappable to show session list)
                        Button(action: { showingSessionList = true }) {
                            Text(currentSession.name)
                                .font(.headline)
                                .foregroundColor(iconColor)
                                .lineLimit(1)
                                .truncationMode(.tail)
                        }
                        .buttonStyle(.plain)
                        .frame(maxWidth: 150, alignment: .leading)

                        Spacer()

                        // Connected status pill (tappable to show sessions)
                        ConnectionStatusPill(action: { showingSessionList = true })

                        // Gear icon in glass circle (settings)
                        GlassCircleButton(
                            icon: "gearshape.fill",
                            color: iconColor,
                            action: { showingSettings = true }
                        )
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)

                    Spacer()
                }
            } else if connectionManager.sessions.isEmpty {
                NoSessionView(showingNewSession: $showingNewSession)
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button(action: { showingSettings = true }) {
                                Image(systemName: "gearshape.fill")
                            }
                        }
                    }
            } else {
                // Auto-select first session
                Color.clear.onAppear {
                    if let first = connectionManager.sessions.first {
                        connectionManager.attachToSession(first.name)
                    }
                }
            }
        }
        .sheet(isPresented: $showingSessionList) {
            SessionListSheet()
                .presentationDetents(sessionSheetDetents)
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
            if connectionManager.currentSession == nil, let first = newSessions.first {
                connectionManager.attachToSession(first.name)
            }
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

    // Dynamic sheet height based on session count
    private var sessionSheetDetents: Set<PresentationDetent> {
        let count = connectionManager.sessions.count
        // Header ~70, section header ~50, each row ~80, bottom padding ~30
        let baseHeight: CGFloat = 150
        let rowHeight: CGFloat = 80
        let calculatedHeight = baseHeight + (CGFloat(count) * rowHeight)

        // Always fit all sessions without scrolling (up to ~6 sessions)
        // Beyond that, cap at 650 and allow expanding to large
        let maxHeight: CGFloat = 650
        return [.height(min(calculatedHeight, maxHeight)), .large]
    }

    var body: some View {
        ZStack {
            // Terminal background color
            Color(uiColor: themeManager.currentTheme.backgroundColor)
                .ignoresSafeArea()

            if let currentSession = connectionManager.currentSession {
                TerminalContainerView(session: currentSession)
                    .id(currentSession.name) // Force new view instance per session

                // Custom top bar overlay (only when session active)
                VStack {
                    HStack(spacing: 10) {
                        // + button in glass circle (new session)
                        GlassCircleButton(
                            icon: "plus",
                            color: iconColor,
                            action: { showingNewSession = true }
                        )

                        // Session name (tappable to show session list)
                        Button(action: { showingSessionList = true }) {
                            Text(currentSession.name)
                                .font(.headline)
                                .foregroundColor(iconColor)
                                .lineLimit(1)
                                .truncationMode(.tail)
                        }
                        .buttonStyle(.plain)
                        .frame(maxWidth: 150, alignment: .leading)

                        Spacer()

                        // Connected status pill (tappable to show sessions)
                        ConnectionStatusPill(action: { showingSessionList = true })

                        // Gear icon in glass circle (settings)
                        GlassCircleButton(
                            icon: "gearshape.fill",
                            color: iconColor,
                            action: { showingSettings = true }
                        )
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)

                    Spacer()
                }
            } else if connectionManager.sessions.isEmpty {
                NoSessionView(showingNewSession: $showingNewSession)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .overlay(alignment: .topTrailing) {
                        // Settings button for iPhone - using GlassCircleButton
                        GlassCircleButton(
                            icon: "gearshape.fill",
                            size: 44,
                            color: iconColor,
                            action: { showingSettings = true }
                        )
                    }
                    .padding(.trailing, 16)
                    .padding(.top, 8)
            } else {
                // Auto-select first session
                Color.clear.onAppear {
                    if let first = connectionManager.sessions.first {
                        connectionManager.attachToSession(first.name)
                    }
                }
            }
        }
        .navigationBarHidden(true)
        .sheet(isPresented: $showingSessionList) {
            SessionListSheet()
                .presentationDetents(sessionSheetDetents)
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
        VStack(spacing: 0) {
            // Custom glass header
            HStack {
                GlassCircleButton(
                    icon: "xmark",
                    size: 36,
                    iconSize: 14,
                    action: { dismiss() }
                )

                Spacer()

                Text("Sessions")
                    .font(.headline)

                Spacer()

                GlassCircleButton(
                    icon: "plus",
                    size: 36,
                    iconSize: 16,
                    action: { showingNewSession = true }
                )
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 12)

            // Sessions list
            List {
                Section {
                    ForEach(connectionManager.sessions) { session in
                        SessionRowView(session: session)
                            .onTapGesture {
                                if connectionManager.currentSession?.name != session.name {
                                    connectionManager.attachToSession(session.name)
                                }
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
            .listStyle(.insetGrouped)
        }
        .onChange(of: connectionManager.sessions) { _, newSessions in
            // Auto-dismiss when no sessions left
            if newSessions.isEmpty {
                dismiss()
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

// MARK: - Setup Step Row
struct SetupStepRow: View {
    let number: Int
    let text: String

    var body: some View {
        HStack(spacing: 14) {
            Text("\(number)")
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(.white)
                .frame(width: 26, height: 26)
                .background(Color.brandAmber)
                .clipShape(Circle())

            Text(text)
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(.secondary)
        }
    }
}

// MARK: - No Session View
struct NoSessionView: View {
    @EnvironmentObject var connectionManager: ConnectionManager
    @EnvironmentObject var themeManager: ThemeManager
    @Binding var showingNewSession: Bool

    var body: some View {
        VStack {
            Spacer()
            welcomeContent
            Spacer()
            bottomContent
        }
    }

    private var welcomeContent: some View {
        VStack(spacing: 24) {
            // App icon
            Image("LogoIcon")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 80, height: 80)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .shadow(color: .brandOrange.opacity(0.3), radius: 20, y: 8)

            VStack(spacing: 8) {
                Text("TermAway")
                    .font(.system(size: 32, weight: .bold))
                    .foregroundColor(.primary)

                Text("Your Mac terminal — on your \(UIDevice.current.userInterfaceIdiom == .pad ? "iPad" : "iPhone")")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.secondary)
            }

            // Setup steps
            VStack(alignment: .leading, spacing: 16) {
                SetupStepRow(number: 1, text: "Create a new session")
                SetupStepRow(number: 2, text: "Start typing commands")
                SetupStepRow(number: 3, text: "Access from any device")
            }
            .padding(.top, 16)

            // Create Session button
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
            .padding(.top, 8)
        }
    }

    private var bottomContent: some View {
        Button(action: { connectionManager.disconnect() }) {
            HStack(spacing: 6) {
                Image(systemName: "xmark.circle")
                    .font(.subheadline)
                Text("Disconnect")
                    .font(.subheadline.weight(.medium))
            }
            .foregroundColor(.secondary)
        }
        .padding(.bottom, 30)
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
            VStack(spacing: 20) {
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

                    Text("Your Mac terminal — on your \(UIDevice.current.userInterfaceIdiom == .pad ? "iPad" : "iPhone")")
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

                // Connect button with error overlay below
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
                .overlay(alignment: .top) {
                    // Error floats below button without affecting layout
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
                        .offset(y: 76) // Position below button
                        .transition(.opacity.combined(with: .move(edge: .top)))
                        .animation(.easeInOut(duration: 0.2), value: error)
                    }
                }

                Spacer()

                // Settings button at bottom
                GlassSettingsButton(action: { showingServerSheet = true })

                // Version number
                Text("v\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")")
                    .font(.caption)
                    .foregroundColor(.secondary.opacity(0.6))
                    .padding(.top, 12)
                    .padding(.bottom, 30)
            }
        }
    }
}

// MARK: - Connection Status (Dynamic - uses EnvironmentObject)
struct ConnectionStatusView: View {
    @EnvironmentObject var connectionManager: ConnectionManager

    var body: some View {
        ConnectionStatusPill(isConnected: connectionManager.isConnected)
    }
}

#Preview {
    ContentView()
        .environmentObject(ConnectionManager())
}
