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

// MARK: - Shared Helpers

/// Calculate sheet detents based on session count
func sessionSheetDetents(for count: Int) -> Set<PresentationDetent> {
    let baseHeight: CGFloat = 150
    let rowHeight: CGFloat = 80
    let calculatedHeight = baseHeight + (CGFloat(count) * rowHeight)
    let maxHeight: CGFloat = 650
    return [.height(min(calculatedHeight, maxHeight)), .large]
}

struct ContentView: View {
    @EnvironmentObject var connectionManager: ConnectionManager
    @EnvironmentObject var themeManager: ThemeManager
    @EnvironmentObject var biometricManager: BiometricManager
    /// Per-window session binding for multi-window support on iPadOS.
    /// Each window independently tracks which session it displays.
    @Binding var windowSessionName: String?
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
        ZStack {
        Group {
            // Show sessions when connected AND (authenticated OR no auth required)
            if connectionManager.isConnected && (connectionManager.isAuthenticated || !connectionManager.authRequired) {
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
            } else {
                ConnectView(showingServerSheet: $showingServerSheet)
            }
        }
        .sheet(isPresented: $showingServerSheet) {
            ServerSettingsView()
                .presentationBackground(.regularMaterial)
                .presentationCornerRadius(20)
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

        // Biometric lock overlay
        if biometricManager.isLocked {
            LockScreenOverlay()
                .environmentObject(biometricManager)
                .transition(.opacity)
        }
        } // ZStack
    }
}

// MARK: - Lock Screen Overlay
struct LockScreenOverlay: View {
    @EnvironmentObject var biometricManager: BiometricManager

    var body: some View {
        ZStack {
            // Blurred background covering everything
            Rectangle()
                .fill(.ultraThinMaterial)
                .ignoresSafeArea()

            VStack(spacing: 24) {
                Image(systemName: "faceid")
                    .font(.system(size: 48))
                    .foregroundColor(.brandOrange)

                Text("TermAway is Locked")
                    .font(.title2.weight(.semibold))
                    .foregroundColor(.primary)

                Button(action: { biometricManager.authenticate() }) {
                    Text("Unlock with \(biometricManager.biometricTypeName)")
                        .font(.body.weight(.semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 32)
                        .padding(.vertical, 14)
                        .background(Color.brandOrange)
                        .clipShape(Capsule())
                }
            }
        }
    }
}

// MARK: - Session Sidebar (iPad)
struct SessionSidebarView: View {
    @EnvironmentObject var connectionManager: ConnectionManager
    @EnvironmentObject var splitPaneManager: SplitPaneManager
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

                    Text("Windows")
                        .font(.headline)
                }
            }
        }
        .alert("New Window", isPresented: $showingNewSession) {
            TextField("Window name", text: $newSessionName)
            Button("Cancel", role: .cancel) {
                newSessionName = ""
            }
            Button("Create") {
                if !newSessionName.isEmpty {
                    // Clear any stale layout from a previous session with this name
                    splitPaneManager.clearSavedLayout(for: newSessionName)
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
    @EnvironmentObject var splitPaneManager: SplitPaneManager
    let session: Session
    var isEditMode: Bool = false
    @State private var showingRenameAlert = false
    @State private var showingDeleteConfirmation = false
    @State private var newName = ""

    private var isIPad: Bool {
        UIDevice.current.userInterfaceIdiom == .pad
    }

    /// Check if this is the currently viewed window
    var isActive: Bool {
        connectionManager.currentSession?.name == session.name
    }

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(session.name)
                    .font(.headline)
                    .foregroundColor(.primary)

                HStack(spacing: 8) {
                    Image(systemName: "circle.fill")
                        .font(.system(size: 6))
                        .foregroundStyle(session.clientCount > 0 ? Color.green : Color.gray.opacity(0.5))
                        .symbolEffect(.pulse, isActive: session.clientCount > 0)

                    Text(session.clientCount > 0 ? "Active" : "Idle")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    if session.clientCount > 1 {
                        Text("• \(session.clientCount) clients")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .contentTransition(.numericText())
                    }
                }
            }

            Spacer()

            if isActive && !isEditMode {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.brandOrange)
                    .font(.title3)
            }
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .onTapGesture {
            // Only attach if not already active and not in edit mode
            if !isActive && !isEditMode {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                // Attach to the session on the server
                connectionManager.attachToSession(session.name)

                // On iPad, assign session to the focused pane
                if isIPad {
                    splitPaneManager.attachSessionToFocused(session.name)
                    connectionManager.setActiveSession(session.name)
                }
            }
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            if !isEditMode {
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
        }
        .contextMenu {
            if !isEditMode {
                Button(action: {
                    if !isActive {
                        connectionManager.attachToSession(session.name)
                        if isIPad {
                            splitPaneManager.attachSessionToFocused(session.name)
                            connectionManager.setActiveSession(session.name)
                        }
                    }
                }) {
                    Label("Attach", systemImage: "arrow.right.circle")
                }
                .disabled(isActive)

                // Open in New Window (iPad only — multi-window / Stage Manager)
                if isIPad {
                    Button(action: {
                        openSessionInNewWindow(session.name)
                    }) {
                        Label("Open in New Window", systemImage: "macwindow.badge.plus")
                    }
                }

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
        }
        .alert("Rename Window", isPresented: $showingRenameAlert) {
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
        .alert("Delete Window?", isPresented: $showingDeleteConfirmation) {
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
    @EnvironmentObject var splitPaneManager: SplitPaneManager
    @EnvironmentObject var keyboardShortcutState: KeyboardShortcutState
    @Binding var columnVisibility: NavigationSplitViewVisibility
    @State private var showingSettings = false
    @State private var showingNewSession = false
    @State private var showingSessionList = false
    @State private var showingSplitMenu = false
    @State private var showingKillConfirmation = false
    @State private var newSessionName = ""
    @State private var showSearch = false
    @StateObject private var searchManager = TerminalSearchManager()

    // Icon color adapts to appearance mode
    private var iconColor: Color {
        themeManager.chromeIconColor
    }

    var body: some View {
        ZStack {
            Color(uiColor: themeManager.currentTheme.backgroundColor).ignoresSafeArea()

            if connectionManager.currentSession != nil {
                // Use SplitTerminalView for split pane support
                SplitTerminalView()
                    .id(splitPaneManager.focusedSessionName ?? "default")
                    .navigationBarHidden(true)

                // Custom top bar overlay - only when session active
                VStack(spacing: 0) {
                    HStack(spacing: 10) {
                        if showSearch {
                            // Inline search field — replaces toolbar buttons
                            InlineSearchField(
                                searchManager: searchManager,
                                iconColor: iconColor,
                                onDismiss: {
                                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                        showSearch = false
                                        searchManager.reset()
                                    }
                                    NotificationCenter.default.post(name: .dismissTerminalSearch, object: nil)
                                }
                            )
                            .transition(.scale(scale: 0.3, anchor: .trailing).combined(with: .opacity))
                        } else {
                            // + button in glass circle (new session)
                            GlassCircleButton(
                                icon: "plus",
                                color: iconColor,
                                lightMode: themeManager.isChromeLightMode,
                                action: { showingNewSession = true }
                            )

                            // Session name (tappable to show session list)
                            Button(action: { showingSessionList = true }) {
                                Text(splitPaneManager.focusedSessionName ?? connectionManager.currentSession?.name ?? "")
                                    .font(.headline)
                                    .foregroundColor(iconColor)
                                    .lineLimit(1)
                                    .truncationMode(.tail)
                            }
                            .buttonStyle(.plain)
                            .frame(maxWidth: 150, alignment: .leading)

                            Spacer()

                            // Search button
                            GlassCircleButton(
                                icon: "magnifyingglass",
                                color: iconColor,
                                lightMode: themeManager.isChromeLightMode,
                                action: {
                                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                        showSearch = true
                                    }
                                    let sessionName = splitPaneManager.focusedSessionName ?? connectionManager.currentSession?.name ?? ""
                                    let buffer = connectionManager.getSessionOutputBuffer(for: sessionName)
                                    searchManager.updateSearchableText(from: buffer)
                                }
                            )

                            // Split pane button (iPad only)
                            SplitPaneMenuButton(iconColor: iconColor, lightMode: themeManager.isChromeLightMode)

                            // Connected status pill (tappable to show sessions)
                            ConnectionStatusPill(lightMode: themeManager.isChromeLightMode, action: { showingSessionList = true })

                            // Gear icon in glass circle (settings)
                            GlassCircleButton(
                                icon: "gearshape.fill",
                                color: iconColor,
                                lightMode: themeManager.isChromeLightMode,
                                action: { showingSettings = true }
                            )
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background {
                        if themeManager.isChromeLightMode {
                            Rectangle()
                                .fill(.ultraThinMaterial)
                                .ignoresSafeArea(edges: .top)
                        }
                    }
                    .animation(.spring(response: 0.35, dampingFraction: 0.8), value: showSearch)

                    Spacer()
                }
                .onReceive(NotificationCenter.default.publisher(for: .toggleTerminalSearch)) { _ in
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                        if showSearch {
                            showSearch = false
                            searchManager.reset()
                            NotificationCenter.default.post(name: .dismissTerminalSearch, object: nil)
                        } else {
                            showSearch = true
                            let sessionName = splitPaneManager.focusedSessionName ?? connectionManager.currentSession?.name ?? ""
                            let buffer = connectionManager.getSessionOutputBuffer(for: sessionName)
                            searchManager.updateSearchableText(from: buffer)
                        }
                    }
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
                .presentationDetents(sessionSheetDetents(for: connectionManager.sessions.count))
                .presentationDragIndicator(.visible)
                .presentationBackground(.regularMaterial)
                .presentationCornerRadius(20)
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView()
        }
        .alert("New Window", isPresented: $showingNewSession) {
            TextField("Window name", text: $newSessionName)
            Button("Cancel", role: .cancel) {
                newSessionName = ""
            }
            Button("Create") {
                if !newSessionName.isEmpty {
                    // Clear any stale layout from a previous session with this name
                    splitPaneManager.clearSavedLayout(for: newSessionName)
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
        .onChange(of: connectionManager.currentSession?.name) { oldValue, newValue in
            // Load the layout for this session (persisted per-session)
            print("ContentView: Session changed from '\(oldValue ?? "nil")' to '\(newValue ?? "nil")'")
            if let sessionName = newValue {
                splitPaneManager.setCurrentSession(sessionName)
            }
        }
        .onAppear {
            // Set up callback for creating ephemeral sessions when restoring layouts
            // Ephemeral sessions are auto-killed when switching windows, so we recreate them
            splitPaneManager.onNeedCreatePaneSessions = { sessionNames in
                print("SplitPaneManager: Recreating ephemeral sessions: \(sessionNames)")
                for name in sessionNames {
                    connectionManager.createPaneSession(name)
                }
            }
        }
        .alert("Close Window?", isPresented: $showingKillConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Close", role: .destructive) {
                if let name = connectionManager.currentSession?.name {
                    connectionManager.killSession(name)
                }
            }
        } message: {
            if let name = connectionManager.currentSession?.name {
                Text("This will terminate \"\(name)\" and cannot be undone.")
            }
        }
        .keyboardShortcutHandler(
            shortcutState: keyboardShortcutState,
            showingNewSession: $showingNewSession,
            showingSettings: $showingSettings,
            showingKillConfirmation: $showingKillConfirmation
        )
        .hideToolbarBackground()
        .preferredColorScheme(themeManager.appearanceMode.colorScheme)
    }
}

// MARK: - Split Pane Menu Button
struct SplitPaneMenuButton: View {
    @EnvironmentObject var connectionManager: ConnectionManager
    @EnvironmentObject var splitPaneManager: SplitPaneManager
    let iconColor: Color
    var lightMode: Bool = false

    var body: some View {
        Menu {
            // Layout options
            Section("Layout") {
                ForEach(SplitLayout.allCases, id: \.self) { layout in
                    Button(action: { changeToLayout(layout) }) {
                        Label(
                            layout.displayName,
                            systemImage: layout.icon
                        )
                    }
                    .disabled(splitPaneManager.layout == layout)
                }
            }

            // Close pane option (only if multiple panes)
            if splitPaneManager.panes.count > 1 {
                Section {
                    Button(role: .destructive, action: { splitPaneManager.closeFocusedPane() }) {
                        Label("Close Focused Pane", systemImage: "xmark.rectangle")
                    }

                    Button(action: { splitPaneManager.resetToSingle() }) {
                        Label("Merge All Panes", systemImage: "rectangle")
                    }
                }
            }
        } label: {
            GlassCircleButton(
                icon: splitPaneManager.layout.icon,
                color: iconColor,
                lightMode: lightMode,
                action: { }
            )
            .allowsHitTesting(false)
        }
    }

    /// Change layout and auto-create sessions for new panes
    private func changeToLayout(_ layout: SplitLayout) {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        let currentPaneCount = splitPaneManager.panes.count
        let neededPaneCount = layout.paneCount
        let newPanesNeeded = max(0, neededPaneCount - currentPaneCount)

        // Get base session name for generating new session names
        let baseSessionName = splitPaneManager.focusedSessionName ?? connectionManager.currentSession?.name ?? "Window"

        // Create new sessions for additional panes (using dash instead of parens for server compatibility)
        var newSessionNames: [String] = []
        for i in 0..<newPanesNeeded {
            let paneNumber = currentPaneCount + i + 1
            let newName = "\(baseSessionName)-\(paneNumber)"
            newSessionNames.append(newName)
            // Create session but mark it as a pane session (don't switch to it)
            connectionManager.createPaneSession(newName)
        }

        // Change the layout (creates empty panes)
        splitPaneManager.changeLayout(to: layout)

        // Assign the new sessions to the new panes
        let newPanes = Array(splitPaneManager.panes.suffix(newPanesNeeded))
        for (index, pane) in newPanes.enumerated() {
            if index < newSessionNames.count {
                splitPaneManager.attachSession(newSessionNames[index], to: pane.id)
            }
        }
    }
}

// MARK: - Compact View (iPhone)
struct SessionCompactView: View {
    @EnvironmentObject var connectionManager: ConnectionManager
    @EnvironmentObject var themeManager: ThemeManager
    @EnvironmentObject var splitPaneManager: SplitPaneManager
    @EnvironmentObject var keyboardShortcutState: KeyboardShortcutState
    @State private var showingNewSession = false
    @State private var newSessionName = ""
    @State private var showingSessionList = false
    @State private var showingSettings = false
    @State private var showingKillConfirmation = false
    @State private var showSearch = false
    @StateObject private var searchManager = TerminalSearchManager()

    // Icon color adapts to appearance mode
    private var iconColor: Color {
        themeManager.chromeIconColor
    }

    var body: some View {
        ZStack {
            // Terminal background color
            Color(uiColor: themeManager.currentTheme.backgroundColor)
                .ignoresSafeArea()

            if let currentSession = connectionManager.currentSession {
                TerminalContainerView(session: currentSession)
                    .id(currentSession.name) // Force new view instance per session
                    .transition(.opacity.animation(.easeInOut(duration: 0.2)))

                // Custom top bar overlay (only when session active)
                VStack {
                    HStack(spacing: 10) {
                        if showSearch {
                            // Inline search field — replaces toolbar buttons
                            InlineSearchField(
                                searchManager: searchManager,
                                iconColor: iconColor,
                                onDismiss: {
                                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                        showSearch = false
                                        searchManager.reset()
                                    }
                                    NotificationCenter.default.post(name: .dismissTerminalSearch, object: nil)
                                }
                            )
                            .transition(.scale(scale: 0.3, anchor: .trailing).combined(with: .opacity))
                        } else {
                            // + button in glass circle (new session)
                            GlassCircleButton(
                                icon: "plus",
                                color: iconColor,
                                lightMode: themeManager.isChromeLightMode,
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

                            // Search button
                            GlassCircleButton(
                                icon: "magnifyingglass",
                                color: iconColor,
                                lightMode: themeManager.isChromeLightMode,
                                action: {
                                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                        showSearch = true
                                    }
                                    let buffer = connectionManager.getSessionOutputBuffer(for: currentSession.name)
                                    searchManager.updateSearchableText(from: buffer)
                                }
                            )

                            // Connected status pill (tappable to show sessions)
                            ConnectionStatusPill(lightMode: themeManager.isChromeLightMode, action: { showingSessionList = true })

                            // Gear icon in glass circle (settings)
                            GlassCircleButton(
                                icon: "gearshape.fill",
                                color: iconColor,
                                lightMode: themeManager.isChromeLightMode,
                                action: { showingSettings = true }
                            )
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background {
                        if themeManager.isChromeLightMode {
                            Rectangle()
                                .fill(.ultraThinMaterial)
                                .ignoresSafeArea(edges: .top)
                        }
                    }
                    .animation(.spring(response: 0.35, dampingFraction: 0.8), value: showSearch)

                    Spacer()
                }
                .onReceive(NotificationCenter.default.publisher(for: .toggleTerminalSearch)) { _ in
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                        if showSearch {
                            showSearch = false
                            searchManager.reset()
                            NotificationCenter.default.post(name: .dismissTerminalSearch, object: nil)
                        } else {
                            showSearch = true
                            if let session = connectionManager.currentSession {
                                let buffer = connectionManager.getSessionOutputBuffer(for: session.name)
                                searchManager.updateSearchableText(from: buffer)
                            }
                        }
                    }
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
                            lightMode: themeManager.isChromeLightMode,
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
                .presentationDetents(sessionSheetDetents(for: connectionManager.sessions.count))
                .presentationDragIndicator(.visible)
                .presentationBackground(.regularMaterial)
                .presentationCornerRadius(20)
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView()
        }
        .alert("New Window", isPresented: $showingNewSession) {
            TextField("Window name", text: $newSessionName)
            Button("Cancel", role: .cancel) {
                newSessionName = ""
            }
            Button("Create") {
                if !newSessionName.isEmpty {
                    // Clear any stale layout from a previous session with this name
                    splitPaneManager.clearSavedLayout(for: newSessionName)
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
        .alert("Close Window?", isPresented: $showingKillConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Close", role: .destructive) {
                if let name = connectionManager.currentSession?.name {
                    connectionManager.killSession(name)
                }
            }
        } message: {
            if let name = connectionManager.currentSession?.name {
                Text("This will terminate \"\(name)\" and cannot be undone.")
            }
        }
        .keyboardShortcutHandler(
            shortcutState: keyboardShortcutState,
            showingNewSession: $showingNewSession,
            showingSettings: $showingSettings,
            showingKillConfirmation: $showingKillConfirmation
        )
    }
}

// MARK: - Session List Sheet
struct SessionListSheet: View {
    @EnvironmentObject var connectionManager: ConnectionManager
    @EnvironmentObject var splitPaneManager: SplitPaneManager
    @EnvironmentObject var themeManager: ThemeManager
    @Environment(\.dismiss) var dismiss
    @State private var showingNewSession = false
    @State private var newSessionName = ""
    @State private var isEditMode = false
    @State private var selectedSessions: Set<String> = []
    @State private var showingDeleteConfirmation = false

    private var allSelected: Bool {
        !connectionManager.sessions.isEmpty &&
        selectedSessions.count == connectionManager.sessions.count
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                if isEditMode {
                    Button {
                        withAnimation {
                            isEditMode = false
                            selectedSessions.removeAll()
                        }
                    } label: {
                        Text("Done")
                            .font(.body.weight(.semibold))
                            .foregroundColor(.brandOrange)
                    }
                } else {
                    Button { dismiss() } label: {
                        Text("Close")
                            .font(.body.weight(.medium))
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()

                VStack(spacing: 2) {
                    Text("Sessions")
                        .font(.headline)
                    if !connectionManager.sessions.isEmpty {
                        Text("\(connectionManager.sessions.count) active")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .contentTransition(.numericText())
                    }
                }

                Spacer()

                if isEditMode {
                    Button {
                        if allSelected {
                            selectedSessions.removeAll()
                        } else {
                            selectedSessions = Set(connectionManager.sessions.map { $0.name })
                        }
                    } label: {
                        Text(allSelected ? "Deselect" : "Select All")
                            .font(.body.weight(.medium))
                            .foregroundColor(.brandOrange)
                    }
                } else {
                    if connectionManager.sessions.count > 1 {
                        Button {
                            withAnimation { isEditMode = true }
                        } label: {
                            Text("Select")
                                .font(.body.weight(.medium))
                                .foregroundColor(.brandOrange)
                        }
                    } else {
                        // Invisible placeholder to keep title centered
                        Text("Close")
                            .font(.body.weight(.medium))
                            .hidden()
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 24)
            .padding(.bottom, 8)

            // Content
            if connectionManager.sessions.isEmpty {
                // Empty state
                Spacer()
                VStack(spacing: 16) {
                    Image(systemName: "terminal")
                        .font(.system(size: 40))
                        .foregroundColor(.secondary.opacity(0.5))

                    Text("No sessions yet")
                        .font(.title3.weight(.medium))
                        .foregroundColor(.secondary)

                    Text("Create a session to get started")
                        .font(.subheadline)
                        .foregroundColor(.secondary.opacity(0.7))

                    Button(action: { showingNewSession = true }) {
                        HStack(spacing: 8) {
                            Image(systemName: "plus")
                                .font(.body.weight(.semibold))
                            Text("New Session")
                                .font(.body.weight(.semibold))
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 28)
                        .padding(.vertical, 12)
                        .background(Color.brandOrange)
                        .clipShape(Capsule())
                    }
                    .padding(.top, 4)
                }
                Spacer()
            } else {
                // Sessions list with bottom action area
                ZStack(alignment: .bottom) {
                    List {
                        ForEach(connectionManager.sessions) { session in
                            HStack(spacing: 12) {
                                if isEditMode {
                                    Button {
                                        toggleSelection(session.name)
                                    } label: {
                                        Image(systemName: selectedSessions.contains(session.name)
                                              ? "checkmark.circle.fill"
                                              : "circle")
                                            .foregroundColor(selectedSessions.contains(session.name)
                                                            ? .brandOrange
                                                            : .secondary)
                                            .font(.title2)
                                    }
                                    .buttonStyle(.plain)
                                }

                                SessionRowView(session: session, isEditMode: isEditMode)
                            }
                            .listRowBackground(
                                connectionManager.currentSession?.name == session.name
                                    ? Color.brandOrange.opacity(0.1)
                                    : Color.clear
                            )
                            .contentShape(Rectangle())
                            .onTapGesture {
                                if isEditMode {
                                    toggleSelection(session.name)
                                }
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                    .scrollContentBackground(.hidden)
                    .contentMargins(.bottom, 80, for: .scrollContent)

                    // Bottom action area
                    VStack(spacing: 0) {
                        Divider()

                        if isEditMode && !selectedSessions.isEmpty {
                            Button {
                                showingDeleteConfirmation = true
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: "trash.fill")
                                    Text("Delete \(selectedSessions.count) Session\(selectedSessions.count == 1 ? "" : "s")")
                                }
                                .font(.body.weight(.semibold))
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(Color.red)
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            }
                            .padding(.horizontal, 20)
                            .padding(.vertical, 12)
                        } else {
                            Button(action: { showingNewSession = true }) {
                                HStack(spacing: 8) {
                                    Image(systemName: "plus")
                                        .font(.body.weight(.semibold))
                                    Text("New Session")
                                        .font(.body.weight(.semibold))
                                }
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(Color.brandOrange)
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            }
                            .padding(.horizontal, 20)
                            .padding(.vertical, 12)
                        }
                    }
                    .background(.regularMaterial)
                }
            }
        }
        .preferredColorScheme(themeManager.appearanceMode.colorScheme)
        .onChange(of: connectionManager.sessions) { _, newSessions in
            if newSessions.isEmpty && isEditMode {
                isEditMode = false
                selectedSessions.removeAll()
            }
            selectedSessions = selectedSessions.filter { name in
                newSessions.contains { $0.name == name }
            }
            if newSessions.count <= 1 {
                isEditMode = false
            }
        }
        .onChange(of: connectionManager.currentSession?.name) { _, _ in
            if !isEditMode {
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
                    splitPaneManager.clearSavedLayout(for: newSessionName)
                    connectionManager.createSession(newSessionName)
                    connectionManager.attachToSession(newSessionName)
                    newSessionName = ""
                }
            }
        }
        .alert("Delete Sessions", isPresented: $showingDeleteConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Delete \(selectedSessions.count)", role: .destructive) {
                deleteSelectedSessions()
            }
        } message: {
            Text("Are you sure you want to delete \(selectedSessions.count) session\(selectedSessions.count == 1 ? "" : "s")? This cannot be undone.")
        }
    }

    private func toggleSelection(_ name: String) {
        if selectedSessions.contains(name) {
            selectedSessions.remove(name)
        } else {
            selectedSessions.insert(name)
        }
    }

    private func deleteSelectedSessions() {
        for name in selectedSessions {
            connectionManager.killSession(name)
        }
        selectedSessions.removeAll()
        isEditMode = false
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
                    Text("Create Window")
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
    @State private var serverURL: String = ""
    @State private var password: String = ""
    @State private var appearAnimation = false
    @FocusState private var focusedField: ConnectField?

    private enum ConnectField {
        case url, password
    }

    private var canConnect: Bool {
        !serverURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        ZStack {
            Color(uiColor: .systemBackground)
                .ignoresSafeArea()

            // Animated background blobs
            GeometryReader { geo in
                ZStack {
                    Circle()
                        .fill(Color.brandOrange.opacity(colorScheme == .dark ? 0.2 : 0.12))
                        .frame(width: 500, height: 500)
                        .blur(radius: 130)
                        .position(
                            x: geo.size.width * (animateGradient ? 0.25 : 0.08),
                            y: geo.size.height * (animateGradient ? 0.25 : 0.08)
                        )

                    Circle()
                        .fill(Color.brandAmber.opacity(colorScheme == .dark ? 0.15 : 0.1))
                        .frame(width: 400, height: 400)
                        .blur(radius: 110)
                        .position(
                            x: geo.size.width * (animateGradient ? 0.8 : 0.92),
                            y: geo.size.height * (animateGradient ? 0.8 : 0.65)
                        )
                }
            }
            .ignoresSafeArea()
            .onAppear {
                withAnimation(.easeInOut(duration: 12).repeatForever(autoreverses: true)) {
                    animateGradient = true
                }
            }

            ScrollView {
                VStack(spacing: 0) {
                    Spacer()
                        .frame(height: UIDevice.current.userInterfaceIdiom == .pad ? 80 : 50)

                    // Header
                    VStack(spacing: 16) {
                        Image("LogoIcon")
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 80, height: 80)
                            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                            .shadow(color: .brandOrange.opacity(0.25), radius: 16, y: 6)
                            .scaleEffect(appearAnimation ? 1.0 : 0.8)
                            .opacity(appearAnimation ? 1.0 : 0.0)

                        VStack(spacing: 6) {
                            Text("TermAway")
                                .font(.system(size: 32, weight: .bold, design: .default))
                                .foregroundColor(.primary)

                            Text("Your Mac terminal — on your \(UIDevice.current.userInterfaceIdiom == .pad ? "iPad" : "iPhone")")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        .opacity(appearAnimation ? 1.0 : 0.0)
                        .offset(y: appearAnimation ? 0 : 8)
                    }
                    .padding(.bottom, 36)

                    // Connection form
                    VStack(spacing: 16) {
                        // Server URL
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Server")
                                .font(.subheadline.weight(.medium))
                                .foregroundColor(.secondary)

                            HStack(spacing: 12) {
                                Image(systemName: "link")
                                    .foregroundColor(.secondary)
                                    .frame(width: 20)

                                TextField("192.168.1.100:3000", text: $serverURL)
                                    .keyboardType(.URL)
                                    .textInputAutocapitalization(.never)
                                    .autocorrectionDisabled()
                                    .focused($focusedField, equals: .url)
                                    .submitLabel(.next)
                                    .onSubmit { focusedField = .password }
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 14)
                            .background {
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(Color(uiColor: .secondarySystemBackground))
                            }
                            .overlay {
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .stroke(focusedField == .url ? Color.brandOrange.opacity(0.5) : .clear, lineWidth: 1.5)
                            }
                            .animation(.easeInOut(duration: 0.15), value: focusedField)
                        }

                        // Password
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Password")
                                .font(.subheadline.weight(.medium))
                                .foregroundColor(.secondary)

                            HStack(spacing: 12) {
                                Image(systemName: "lock")
                                    .foregroundColor(.secondary)
                                    .frame(width: 20)

                                SecureField("Optional", text: $password)
                                    .textInputAutocapitalization(.never)
                                    .autocorrectionDisabled()
                                    .focused($focusedField, equals: .password)
                                    .submitLabel(.go)
                                    .onSubmit { if canConnect { connect() } }
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 14)
                            .background {
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(Color(uiColor: .secondarySystemBackground))
                            }
                            .overlay {
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .stroke(focusedField == .password ? Color.brandOrange.opacity(0.5) : .clear, lineWidth: 1.5)
                            }
                            .animation(.easeInOut(duration: 0.15), value: focusedField)
                        }

                        // Error message
                        if let error = connectionManager.lastError {
                            HStack(spacing: 8) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .font(.footnote)
                                Text(error)
                                    .font(.footnote.weight(.medium))
                            }
                            .foregroundColor(.red)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 4)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                        }

                        // Connect button
                        Button(action: connect) {
                            HStack(spacing: 10) {
                                if connectionManager.isConnecting {
                                    ProgressView()
                                        .tint(.white)
                                        .scaleEffect(0.9)
                                        .transition(.opacity)
                                }
                                Text(connectionManager.isConnecting ? "Connecting..." : "Connect")
                                    .font(.body.weight(.semibold))
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(canConnect ? Color.brandOrange : Color.brandOrange.opacity(0.4))
                            .foregroundColor(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .shadow(color: canConnect ? .brandOrange.opacity(0.25) : .clear, radius: 10, y: 5)
                        }
                        .disabled(!canConnect || connectionManager.isConnecting)
                        .animation(.easeInOut(duration: 0.2), value: connectionManager.isConnecting)
                        .padding(.top, 4)
                    }
                    .padding(.horizontal, 24)
                    .frame(maxWidth: 400)
                    .opacity(appearAnimation ? 1.0 : 0.0)
                    .offset(y: appearAnimation ? 0 : 12)

                    // Discovered servers
                    ConnectDiscoveredServersSection(serverURL: $serverURL)
                        .padding(.top, 28)
                        .frame(maxWidth: 400)
                        .opacity(appearAnimation ? 1.0 : 0.0)

                    Spacer()
                        .frame(height: 40)

                    // Footer
                    VStack(spacing: 12) {
                        Button(action: { showingServerSheet = true }) {
                            HStack(spacing: 6) {
                                Image(systemName: "gearshape")
                                    .font(.subheadline)
                                Text("Advanced Settings")
                                    .font(.subheadline.weight(.medium))
                            }
                            .foregroundColor(.secondary)
                        }

                        Text("v\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")")
                            .font(.caption2)
                            .foregroundColor(.secondary.opacity(0.5))
                    }
                    .padding(.bottom, 30)
                }
                .frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .onAppear {
            serverURL = connectionManager.serverURL?
                .replacingOccurrences(of: "ws://", with: "")
                .replacingOccurrences(of: "wss://", with: "") ?? ""
            password = connectionManager.serverPassword ?? ""
            withAnimation(.easeOut(duration: 0.6).delay(0.1)) {
                appearAnimation = true
            }
        }
        .animation(.easeInOut(duration: 0.25), value: connectionManager.lastError)
    }

    private func connect() {
        focusedField = nil
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()

        var url = serverURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if !url.hasPrefix("ws://") && !url.hasPrefix("wss://") {
            url = "ws://\(url)"
        }

        connectionManager.setServerURL(url)
        connectionManager.serverPassword = password.isEmpty ? nil : password
        connectionManager.connect()
    }
}

// MARK: - Discovered Servers (Connect Screen)
struct ConnectDiscoveredServersSection: View {
    @Binding var serverURL: String
    @StateObject private var bonjourBrowser = BonjourBrowser()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: "bonjour")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                Text("Discovered Servers")
                    .font(.subheadline.weight(.medium))
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 24)

            if bonjourBrowser.discoveredServers.isEmpty {
                HStack(spacing: 10) {
                    ProgressView()
                        .scaleEffect(0.75)
                    Text("Scanning local network...")
                        .font(.subheadline)
                        .foregroundColor(.secondary.opacity(0.7))
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 16)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(bonjourBrowser.discoveredServers.enumerated()), id: \.element.id) { index, server in
                        Button(action: {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            serverURL = server.url
                                .replacingOccurrences(of: "ws://", with: "")
                                .replacingOccurrences(of: "wss://", with: "")
                        }) {
                            HStack(spacing: 12) {
                                Image(systemName: "desktopcomputer")
                                    .font(.body)
                                    .foregroundColor(.brandOrange)
                                    .frame(width: 28)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(server.name)
                                        .font(.body.weight(.medium))
                                        .foregroundColor(.primary)
                                    Text(server.url.replacingOccurrences(of: "ws://", with: ""))
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }

                                Spacer()

                                let cleanURL = server.url
                                    .replacingOccurrences(of: "ws://", with: "")
                                    .replacingOccurrences(of: "wss://", with: "")
                                if serverURL == cleanURL {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(.brandOrange)
                                        .transition(.scale.combined(with: .opacity))
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                        }
                        .buttonStyle(.plain)

                        if index < bonjourBrowser.discoveredServers.count - 1 {
                            Divider()
                                .padding(.leading, 56)
                        }
                    }
                }
                .background {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color(uiColor: .secondarySystemBackground))
                }
                .padding(.horizontal, 24)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: bonjourBrowser.discoveredServers.count)
    }
}

#Preview {
    ContentView(windowSessionName: .constant(nil))
        .environmentObject(ConnectionManager())
        .environmentObject(BiometricManager())
}
