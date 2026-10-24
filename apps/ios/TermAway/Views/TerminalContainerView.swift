import SwiftUI
import SwiftTerm
import UIKit
import PhotosUI

struct TerminalContainerView: View {
    @EnvironmentObject var connectionManager: ConnectionManager
    @EnvironmentObject var shortcutsManager: ShortcutsManager
    @EnvironmentObject var themeManager: ThemeManager
    let session: Session
    /// False under a system navigation bar, which insets the content itself.
    var reservesTopBar = true
    @State private var terminalView: TerminalView?
    @State private var showScrollButton = false
    @State private var keyboardHeight: CGFloat = 0
    // Owned here so the terminal can make room for the pill above the composer.
    @State private var shortcutsExpanded = false
    @Namespace private var scrollButtonNamespace

    private var iconColor: SwiftUI.Color {
        themeManager.chromeIconColor
    }

    /// The open shortcuts pill: its 44pt height plus the stack's 8pt spacing.
    private var pillRoom: CGFloat { shortcutsExpanded ? 52 : 0 }

    /// Calculate bottom padding based on keyboard and toolbar state
    private func bottomPadding(safeArea: CGFloat) -> CGFloat {
        if keyboardHeight > 0 {
            // Keyboard visible: add space for keyboard + toolbar (toolbar sits above keyboard)
            return keyboardHeight + (shortcutsManager.showToolbar ? 60 : 20) + pillRoom
        } else {
            // No keyboard: normal padding
            return safeArea + (shortcutsManager.showToolbar ? 60 : 20) + pillRoom
        }
    }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .bottom) {
                // Terminal with top padding for app bar (extra when search visible)
                // Bottom padding adjusts for keyboard when visible
                TerminalViewRepresentable(
                    connectionManager: connectionManager,
                    themeManager: themeManager,
                    terminalView: $terminalView,
                    sessionName: session.name
                )
                // Extra top room for the port-chip row when this session has ports.
                .padding(.top, (reservesTopBar ? 44 : 0) + (session.ports.isEmpty ? 0 : 36))
                .padding(.horizontal, 8)
                .padding(.bottom, bottomPadding(safeArea: geo.safeAreaInsets.bottom))

                // Toolbar at bottom (only if enabled)
                if terminalView != nil && shortcutsManager.showToolbar {
                    ShortcutsToolbarView(
                        terminalView: $terminalView,
                        bottomSafeArea: geo.safeAreaInsets.bottom,
                        sessionName: session.name,
                        shortcutsExpanded: $shortcutsExpanded
                    )
                }

                // Scroll to bottom button - only show when scrolled up and keyboard not visible
                if terminalView != nil && showScrollButton && keyboardHeight == 0 {
                    VStack {
                        Spacer()
                        HStack {
                            Spacer()
                            scrollToBottomButton
                                .padding(.trailing, 16)
                                .padding(.bottom, shortcutsManager.showToolbar ? geo.safeAreaInsets.bottom + 70 : geo.safeAreaInsets.bottom + 24)
                        }
                    }
                    .transition(.scale(scale: 0, anchor: .center).combined(with: .opacity))
                }
            }
            .animation(.spring(response: 0.3, dampingFraction: 0.8), value: showScrollButton)
            .animation(.easeInOut(duration: 0.25), value: keyboardHeight)
        }
        .ignoresSafeArea(edges: .bottom)
        .onReceive(Timer.publish(every: 0.3, on: .main, in: .common).autoconnect()) { _ in
            updateScrollState()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { notification in
            keyboardHeight = visibleKeyboardHeight(notification)
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            keyboardHeight = 0
        }
        .onReceive(NotificationCenter.default.publisher(for: .dismissTerminalSearch)) { _ in
            // Return focus to the terminal when search is dismissed from ContentView
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                terminalView?.becomeFirstResponder()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .scrollToSearchMatch)) { note in
            guard note.userInfo?["session"] as? String == session.name,
                  let proportion = note.userInfo?["proportion"] as? Double else { return }
            terminalView?.scrollToSearchMatch(proportion: proportion)
        }
    }

    @ViewBuilder
    private var scrollToBottomButton: some View {
        GlassCircleButton(
            icon: "arrow.down.to.line",
            size: 44,
            color: iconColor,
            lightMode: themeManager.isChromeLightMode,
            action: { scrollToBottom() }
        )
    }

    private func updateScrollState() {
        guard let terminal = terminalView else { return }
        let contentHeight = terminal.contentSize.height
        let frameHeight = terminal.bounds.height
        let offsetY = terminal.contentOffset.y

        // Has scrollable content and not at bottom
        let hasScrollableContent = contentHeight > frameHeight + 50
        let maxOffset = max(0, contentHeight - frameHeight)
        let isAtBottom = offsetY >= maxOffset - 50

        let shouldShow = hasScrollableContent && !isAtBottom
        if shouldShow != showScrollButton {
            showScrollButton = shouldShow
        }
    }

    private func scrollToBottom() {
        guard let terminal = terminalView else { return }
        let bottomOffset = CGPoint(x: 0, y: max(terminal.contentSize.height - terminal.bounds.height, 0))
        terminal.setContentOffset(bottomOffset, animated: true)
    }

}

// MARK: - Search Notification
extension Notification.Name {
    static let toggleTerminalSearch = Notification.Name("toggleTerminalSearch")
}

// MARK: - Shortcuts Toolbar
struct ShortcutsToolbarView: View {
    @EnvironmentObject var shortcutsManager: ShortcutsManager
    @EnvironmentObject var themeManager: ThemeManager
    @EnvironmentObject var connectionManager: ConnectionManager
    @Binding var terminalView: TerminalView?
    var bottomSafeArea: CGFloat = 0
    let sessionName: String

    @State private var isToolbarVisible = true
    @State private var isKeyboardVisible = false
    @State private var keyboardHeight: CGFloat = 0
    @Namespace private var toolbarNamespace

    // Composer: a multi-line draft box, always shown, with the shortcuts pill
    // folded away above it behind "…". Return inserts a newline (impossible in
    // the raw terminal), Send fires draft + Enter. Drafts persist per session so
    // a long prompt survives a switch away.
    @Binding var shortcutsExpanded: Bool
    @State private var draft = ""
    @State private var composerError: String?
    @FocusState private var composerFocused: Bool
    // A photo goes to the server's inbox and its path into the draft, which is
    // how Claude Code and most agents take an image.
    @State private var photoItem: PhotosPickerItem?
    @State private var isUploadingPhoto = false

    private var draftIsEmpty: Bool {
        draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    // Icon color adapts to appearance mode
    private var iconColor: SwiftUI.Color {
        themeManager.chromeIconColor
    }

    var body: some View {
        // The shortcuts pill (when expanded) opens above the composer, so the field
        // never moves; the whole stack is pinned to the bottom above the keyboard.
        VStack(spacing: 8) {
            Spacer()
            if shortcutsExpanded {
                toolbarContent
                    .transition(.scale(scale: 0.9, anchor: .bottom).combined(with: .opacity))
            }
            composerPanel
        }
        // By height, not isKeyboardVisible: a hardware keyboard shows nothing on screen.
        .padding(.bottom, keyboardHeight > 0 ? (keyboardHeight + 8) : (bottomSafeArea + 20))
        .onAppear { draft = connectionManager.loadDraft(for: sessionName) }
        .onChange(of: draft) { _, newValue in
            connectionManager.saveDraft(newValue, for: sessionName)
            if composerError != nil { withAnimation { composerError = nil } }
        }
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            photoItem = nil
            attachPhoto(item)
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { notification in
            keyboardHeight = visibleKeyboardHeight(notification)
            withAnimation(liquidAnimation) {
                isKeyboardVisible = true
                isToolbarVisible = true
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            withAnimation(liquidAnimation) {
                isKeyboardVisible = false
                keyboardHeight = 0
            }
        }
    }

    // iOS 26 bouncy animation, fallback for older versions
    private var liquidAnimation: Animation {
        if #available(iOS 26.0, *) {
            return .smooth(duration: 0.4)
        } else {
            return .spring(response: 0.3, dampingFraction: 0.8)
        }
    }

    @ViewBuilder
    private var toolbarContent: some View {
        if #available(iOS 26.0, *) {
            GlassEffectContainer {
                toolbarLayout
            }
            .background {
                // Light backing layer — glass picks this up and renders light naturally
                if themeManager.isChromeLightMode {
                    Capsule()
                        .fill(Color(.systemBackground))
                        .padding(.horizontal, 16)
                }
            }
        } else {
            toolbarLayout
                .environment(\.colorScheme, themeManager.isChromeLightMode ? .light : .dark)
                .animation(.spring(response: 0.3, dampingFraction: 0.8), value: isToolbarVisible)
        }
    }

    @ViewBuilder
    private var toolbarLayout: some View {
        shortcutsPill
            .padding(.horizontal, 16)
    }

    // A solid accent circle reads far clearer than an orange icon inside glass
    // against the black terminal. Filled = solid orange + white icon (the
    // primary affordance); unfilled = quiet outlined button.
    private func accentCircleButton(icon: String, filled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            action()
        }) {
            Image(systemName: icon)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(filled ? Color.white : iconColor.opacity(0.5))
                .frame(width: 44, height: 44)
                .background(Circle().fill(filled ? Color.brandOrange : Color.clear))
                .overlay(
                    Circle().strokeBorder(
                        filled ? Color.clear : iconColor.opacity(0.25),
                        lineWidth: 1
                    )
                )
        }
        .buttonStyle(.plain)
    }

    private func toggleKeyboard() {
        if isKeyboardVisible {
            // Dismiss keyboard
            terminalView?.resignFirstResponder()
        } else {
            // Show keyboard
            terminalView?.becomeFirstResponder()
        }
    }

    @ViewBuilder
    private var toggleButton: some View {
        GlassCircleButton(
            icon: isToolbarVisible ? "chevron.down" : "chevron.up",
            size: 40,
            color: iconColor,
            lightMode: themeManager.isChromeLightMode,
            action: {
                withAnimation(liquidAnimation) {
                    isToolbarVisible.toggle()
                }
            }
        )
    }

    private var shortcutsPill: some View {
        // Hug the shortcuts when they fit and scroll only when they don't. A
        // horizontal ScrollView takes every point it is offered, which ran the
        // pill the whole width of the screen with its keys bunched at one end.
        ViewThatFits(in: .horizontal) {
            shortcutsRow
            ScrollView(.horizontal, showsIndicators: false) {
                shortcutsRow
            }
            // The fade is a scroll affordance, so it belongs to this branch
            // alone — dimming the first and last key when everything already
            // fits reads as a rendering fault.
            .mask(
                HStack(spacing: 0) {
                    LinearGradient(
                        colors: [.clear, .black],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(width: 16)
                    Rectangle().fill(.black)
                    LinearGradient(
                        colors: [.black, .clear],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(width: 16)
                }
            )
        }
        .frame(height: 44)
        .modifier(
            GlassPillModifier(
                id: "pill",
                namespace: toolbarNamespace,
                iconColor: iconColor
            )
        )
        .clipShape(Capsule())
    }

    @ViewBuilder
    private var shortcutsRow: some View {
            HStack(spacing: 2) {
                // Photo and keyboard lead the keys, set off by a divider.
                photoButton
                if shortcutsManager.showKeyboardButton {
                    Button(action: {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        toggleKeyboard()
                    }) {
                        Image(systemName: isKeyboardVisible ? "keyboard.chevron.compact.down" : "keyboard")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(iconColor.opacity(0.85))
                            .frame(width: 32, height: 32)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(ShortcutKeyButtonStyle())
                    .accessibilityLabel(isKeyboardVisible ? "Hide keyboard" : "Show keyboard")
                }
                Rectangle()
                    .fill(iconColor.opacity(0.3))
                    .frame(width: 1, height: 20)
                    .padding(.horizontal, 8)

                ForEach(shortcutsManager.toolbarShortcuts) { shortcut in
                    ShortcutKey(
                        shortcut: shortcut,
                        isActive: shortcutsManager.ctrlModeActive && shortcut.name == "Ctrl",
                        iconColor: iconColor
                    ) {
                        handleShortcut(shortcut)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
    }

    private func handleShortcut(_ shortcut: Shortcut) {
        // Handle Ctrl modifier toggle
        if shortcut.name == "Ctrl" {
            shortcutsManager.ctrlModeActive.toggle()
            return
        }

        var command = shortcut.command

        // Apply Ctrl modifier if active
        if shortcutsManager.ctrlModeActive && command.count == 1 {
            if let char = command.lowercased().first,
               let asciiValue = char.asciiValue,
               asciiValue >= 97 && asciiValue <= 122 {
                // Convert to control character (a=1, b=2, etc.)
                let ctrlChar = Character(UnicodeScalar(asciiValue - 96))
                command = String(ctrlChar)
            }
            shortcutsManager.ctrlModeActive = false
        }

        sendKey(command)
    }

    private func sendKey(_ key: String) {
        if let data = key.data(using: .utf8) {
            let bytes = Array(data)
            terminalView?.send(bytes)
        }
    }

    // MARK: - Composer

    @ViewBuilder
    private var composerPanel: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let composerError {
                Text(composerError)
                    .font(.caption)
                    .foregroundStyle(Color.brandOrange)
                    .padding(.horizontal, 8)
                    .transition(.opacity)
            }
            composerInputRow
        }
        .padding(.horizontal, 16)
    }

    /// A key in the shortcuts pill, styled like its neighbours.
    private var photoButton: some View {
        PhotosPicker(selection: $photoItem, matching: .images) {
            Group {
                if isUploadingPhoto {
                    ProgressView().tint(iconColor)
                } else {
                    Image(systemName: "photo")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(iconColor.opacity(0.85))
                }
            }
            .frame(width: 32, height: 32)
            .contentShape(Rectangle())
        }
        .buttonStyle(ShortcutKeyButtonStyle())
        .disabled(isUploadingPhoto)
        .accessibilityLabel("Attach photo")
    }

    // Sending mid-upload would fire the prompt without its image.
    private var canSend: Bool { !draftIsEmpty && !isUploadingPhoto }

    @ViewBuilder
    private var composerInputRow: some View {
        HStack(alignment: .bottom, spacing: 12) {
            // The shortcuts pill folds away behind this; it starts folded.
            GlassCircleButton(
                icon: "ellipsis",
                size: 44,
                color: iconColor,
                lightMode: themeManager.isChromeLightMode,
                action: { withAnimation(liquidAnimation) { shortcutsExpanded.toggle() } }
            )
            .accessibilityLabel(shortcutsExpanded ? "Hide shortcuts" : "Show shortcuts")

            composerField
        }
    }

    @ViewBuilder
    private var composerField: some View {
        // Send lives inside the field, as in Messages.
        HStack(alignment: .bottom, spacing: 6) {
            TextField("Message or prompt…", text: $draft, axis: .vertical)
                .lineLimit(1...6)
                .textFieldStyle(.plain)
                .focused($composerFocused)
                // Terminal input is case- and character-sensitive: never
                // capitalize (`cd`, not `Cd`) or autocorrect / smart-quote it.
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .font(.system(size: 16))
                .foregroundStyle(iconColor)
                .tint(.brandOrange)
                .padding(.leading, 14)
                .padding(.vertical, 12)

            Button(action: {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                sendDraft()
            }) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 30))
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, canSend ? Color.brandOrange : Color(.systemGray3))
            }
            .buttonStyle(.plain)
            .disabled(!canSend)
            .padding([.trailing, .bottom], 7)
            .accessibilityLabel("Send")
        }
        // As tall as the "…" button beside it, growing with more lines.
        .frame(minHeight: 44)
        .background { composerFieldBackground }
        .environment(\.colorScheme, themeManager.isChromeLightMode ? .light : .dark)
    }

    @ViewBuilder
    private var composerFieldBackground: some View {
        // Half the 44pt height: a capsule on one line, as in Messages.
        let shape = RoundedRectangle(cornerRadius: 22, style: .continuous)
        if #available(iOS 26.0, *) {
            shape.fill(.clear).glassEffect(.regular.interactive(), in: shape)
        } else {
            shape.fill(.regularMaterial)
                .overlay(shape.strokeBorder(iconColor.opacity(0.15), lineWidth: 1))
        }
    }

    private func attachPhoto(_ item: PhotosPickerItem) {
        isUploadingPhoto = true
        let session = sessionName
        Task {
            guard let data = try? await item.loadTransferable(type: Data.self),
                  let jpeg = await Task.detached(operation: { Self.jpegForUpload(data) }).value else {
                isUploadingPhoto = false
                withAnimation { composerError = "Couldn’t read that photo." }
                return
            }
            connectionManager.uploadImage(jpeg) { result in
                isUploadingPhoto = false
                switch result {
                case .success(let path):
                    // The stored draft, not @State: a session switch or a fold
                    // can tear this view down before the server answers.
                    let current = connectionManager.loadDraft(for: session)
                    let separator = current.isEmpty || current.last?.isWhitespace == true ? "" : " "
                    let updated = current + separator + path + " "
                    connectionManager.saveDraft(updated, for: session)
                    draft = updated
                    composerError = nil
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                case .failure(let error):
                    withAnimation { composerError = error.localizedDescription }
                }
            }
        }
    }

    /// A JPEG whose base64 fits the server's 1MB message cap. 1600px on the long
    /// edge loses nothing an agent reads: Claude Code downsamples past ~1568px.
    /// Runs off the main actor; decoding a 48MP photo would freeze the UI.
    nonisolated static func jpegForUpload(_ data: Data) -> Data? {
        guard let image = UIImage(data: data) else { return nil }
        let scale = min(1, 1600 / max(image.size.width, image.size.height))
        let size = CGSize(width: (image.size.width * scale).rounded(), height: (image.size.height * scale).rounded())
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let resized = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
        for quality in [0.8, 0.6, 0.4, 0.25] {
            if let data = resized.jpegData(compressionQuality: quality), data.count <= 700_000 { return data }
        }
        return nil
    }

    private func sendDraft() {
        guard !draftIsEmpty else { return }

        let isMultiline = draft.contains(where: { $0.isNewline })
        let bracketedPaste = terminalView?.getTerminal().bracketedPasteMode == true

        // A multi-line draft is only safe to send when the focused app enabled
        // bracketed paste mode (Claude Code, vim, a modern shell) — then we wrap
        // it so the whole thing arrives as one paste and the trailing CR submits.
        // With the mode off, sending raw would let each newline execute/submit a
        // line early, and sending the wrappers would show as literal `^[[200~`.
        // So refuse and tell the user instead of firing lines one at a time.
        if isMultiline && !bracketedPaste {
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
            withAnimation {
                composerError = "This app can’t take multi-line input right now. Remove the line breaks or send one line at a time."
            }
            return
        }

        let body = isMultiline
            ? "\u{1b}[200~" + draft + "\u{1b}[201~"
            : draft
        connectionManager.sendInput(body + "\r", to: sessionName)

        draft = ""  // onChange clears the persisted draft
        composerFocused = false
    }
}

// MARK: - Shortcut Key View (32x32 iOS 26 style)
struct ShortcutKey: View {
    let shortcut: Shortcut
    var isActive: Bool = false
    var iconColor: SwiftUI.Color = .white
    let action: () -> Void

    // Map shortcut names to SF Symbols
    private var sfSymbol: String? {
        switch shortcut.name {
        case "Tab": return "arrow.right.to.line"
        case "Escape": return "escape"
        case "Ctrl": return "control"
        case "Up Arrow": return "arrow.up"
        case "Down Arrow": return "arrow.down"
        case "Left Arrow": return "arrow.left"
        case "Right Arrow": return "arrow.right"
        default: return nil
        }
    }

    // Short label for text display
    private var shortLabel: String {
        switch shortcut.name {
        case "Ctrl+C": return "^C"
        case "Ctrl+D": return "^D"
        case "Ctrl+Z": return "^Z"
        default: return shortcut.displayLabel
        }
    }

    var body: some View {
        Button(action: {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            action()
        }) {
            Group {
                if let symbol = sfSymbol {
                    Image(systemName: symbol)
                        .font(.system(size: 15, weight: .medium))
                } else {
                    Text(shortLabel)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                }
            }
            .foregroundStyle(isActive ? Color.brandOrange : iconColor.opacity(0.85))
            .frame(width: 32, height: 32)
            .contentShape(Rectangle())
        }
        .buttonStyle(ShortcutKeyButtonStyle(isActive: isActive))
    }
}

// MARK: - Shortcut Key Button Style with press animation (pre-iOS 26)
struct ShortcutKeyButtonStyle: ButtonStyle {
    var isActive: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.85 : 1.0)
            .opacity(configuration.isPressed ? 0.6 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}

struct TerminalViewRepresentable: UIViewRepresentable {
    /// Improved ANSI 16-color palette with readable blue on dark backgrounds.
    /// SwiftTerm.Color uses UInt16 (0-65535). Multiply 8-bit values by 257.
    private static func c(_ r: UInt16, _ g: UInt16, _ b: UInt16) -> SwiftTerm.Color {
        SwiftTerm.Color(red: r * 257, green: g * 257, blue: b * 257)
    }
    static let improvedAnsiPalette: [SwiftTerm.Color] = [
        c(0, 0, 0),         // 0  black
        c(153, 0, 1),       // 1  red
        c(0, 166, 3),       // 2  green
        c(153, 153, 0),     // 3  yellow
        c(80, 120, 255),    // 4  blue (brighter, readable on dark)
        c(178, 0, 178),     // 5  magenta
        c(0, 165, 178),     // 6  cyan
        c(191, 191, 191),   // 7  white
        c(138, 137, 138),   // 8  bright black
        c(229, 0, 1),       // 9  bright red
        c(0, 216, 0),       // 10 bright green
        c(229, 229, 0),     // 11 bright yellow
        c(100, 149, 255),   // 12 bright blue (readable on dark)
        c(229, 0, 229),     // 13 bright magenta
        c(0, 229, 229),     // 14 bright cyan
        c(229, 229, 229),   // 15 bright white
    ]

    let connectionManager: ConnectionManager
    @ObservedObject var themeManager: ThemeManager
    @Binding var terminalView: TerminalView?
    let sessionName: String  // Explicit session name to avoid race conditions

    func makeUIView(context: Context) -> SwiftTerm.TerminalView {
        let terminalView = TerminalView(frame: .zero)
        // The terminal is a UIScrollView; its top edge effect drew a band behind
        // the floating title.
        terminalView.topEdgeEffect.isHidden = true

        // Configure terminal appearance from theme
        let theme = themeManager.currentTheme
        terminalView.font = UIFont.monospacedSystemFont(ofSize: themeManager.fontSize, weight: .regular)
        terminalView.nativeForegroundColor = theme.foregroundColor
        terminalView.caretColor = theme.cursorColor
        terminalView.nativeBackgroundColor = theme.backgroundColor

        // Install improved ANSI palette with readable blue on dark backgrounds
        terminalView.installColors(Self.improvedAnsiPalette)

        // Hide iOS keyboard accessory bar - we have our own toolbar
        terminalView.inputAccessoryView = nil

        // Keyboard appearance follows chrome mode
        terminalView.overrideUserInterfaceStyle = themeManager.isChromeLightMode ? .light : .dark

        // Set up the terminal delegate
        terminalView.terminalDelegate = context.coordinator
        context.coordinator.terminalView = terminalView

        // Add tap gesture to ensure terminal can become first responder when tapped
        let tapGesture = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap))
        tapGesture.cancelsTouchesInView = false
        terminalView.addGestureRecognizer(tapGesture)

        // Add swipe gestures for arrow keys
        for direction: UISwipeGestureRecognizer.Direction in [.up, .down, .left, .right] {
            let swipe = UISwipeGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleSwipe(_:)))
            swipe.direction = direction
            swipe.cancelsTouchesInView = false
            terminalView.addGestureRecognizer(swipe)
        }

        // Become first responder to show keyboard
        print("TerminalContainerView[\(sessionName)]: scheduling auto-focus in 0.5s")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak terminalView, sessionName] in
            guard let tv = terminalView else { return }
            let success = tv.becomeFirstResponder()
            print("TerminalContainerView[\(sessionName)]: auto-focus becomeFirstResponder = \(success)")
        }

        // Store reference for toolbar
        DispatchQueue.main.async {
            self.terminalView = terminalView
        }

        return terminalView
    }

    func updateUIView(_ uiView: SwiftTerm.TerminalView, context: Context) {
        // Update coordinator's connection manager reference
        context.coordinator.connectionManager = connectionManager

        // Update theme if changed
        let theme = themeManager.currentTheme
        uiView.font = UIFont.monospacedSystemFont(ofSize: themeManager.fontSize, weight: .regular)
        uiView.nativeForegroundColor = theme.foregroundColor
        uiView.caretColor = theme.cursorColor
        // Set background last — its setter triggers colorsChanged() which redraws everything
        uiView.nativeBackgroundColor = theme.backgroundColor

        // Keyboard appearance follows chrome mode
        uiView.overrideUserInterfaceStyle = themeManager.isChromeLightMode ? .light : .dark
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(connectionManager: connectionManager, sessionName: sessionName)
    }

    class Coordinator: NSObject, TerminalViewDelegate {
        var connectionManager: ConnectionManager
        let sessionName: String  // The specific session this terminal displays

        /// Last known terminal size from sizeChanged callback
        private var lastCols: Int = 80
        private var lastRows: Int = 24

        /// ID for this coordinator's terminal output handler
        private var outputHandlerId: UUID?

        /// Weak reference to the terminal view
        weak var terminalView: TerminalView?

        init(connectionManager: ConnectionManager, sessionName: String) {
            self.connectionManager = connectionManager
            self.sessionName = sessionName
            super.init()

            // Register handler for live terminal output for THIS specific session.
            // IMPORTANT: Use explicit sessionName to avoid race conditions during session switch
            let session = sessionName
            Task { @MainActor in
                self.outputHandlerId = connectionManager.registerOutputHandler(for: session) { [weak self] data in
                    // Just feed the data - let SwiftTerm handle scroll position naturally
                    // SwiftTerm keeps the cursor visible automatically
                    self?.terminalView?.feed(text: data)
                }
            }
        }

        /// Handle tap on terminal to become first responder
        @objc func handleTap() {
            guard let tv = terminalView else {
                print("TerminalContainerView[\(sessionName)]: handleTap - terminalView is nil!")
                return
            }

            if tv.isFirstResponder {
                print("TerminalContainerView[\(sessionName)]: handleTap - already first responder")
                return
            }

            print("TerminalContainerView[\(sessionName)]: handleTap - attempting becomeFirstResponder")
            let success = tv.becomeFirstResponder()
            print("TerminalContainerView[\(sessionName)]: handleTap - becomeFirstResponder = \(success)")

            // If immediate attempt failed, try again after a brief delay
            if !success {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak tv, sessionName = self.sessionName] in
                    guard let tv = tv, !tv.isFirstResponder else { return }
                    let retrySuccess = tv.becomeFirstResponder()
                    print("TerminalContainerView[\(sessionName)]: handleTap retry - becomeFirstResponder = \(retrySuccess)")
                }
            }
        }

        /// Handle swipe gesture to send arrow key escape sequences
        @objc func handleSwipe(_ gesture: UISwipeGestureRecognizer) {
            guard UserDefaults.standard.object(forKey: "swipeGesturesEnabled") == nil
                    || UserDefaults.standard.bool(forKey: "swipeGesturesEnabled") else { return }

            let escapeSequence: String
            switch gesture.direction {
            case .up:    escapeSequence = "\u{1b}[A"
            case .down:  escapeSequence = "\u{1b}[B"
            case .right: escapeSequence = "\u{1b}[C"
            case .left:  escapeSequence = "\u{1b}[D"
            default: return
            }

            UIImpactFeedbackGenerator(style: .light).impactOccurred()

            let session = sessionName
            Task { @MainActor in
                connectionManager.sendInput(escapeSequence, to: session)
            }
        }

        deinit {
            // Unregister handler to prevent calling deallocated coordinator
            let cm = connectionManager
            let handlerId = outputHandlerId
            let session = sessionName
            Task { @MainActor in
                if let id = handlerId {
                    cm.unregisterOutputHandler(for: session, id: id)
                }
            }
        }

        private func scrollToBottom() {
            guard let tv = terminalView else { return }
            let bottomOffset = CGPoint(x: 0, y: max(tv.contentSize.height - tv.bounds.height, 0))
            tv.setContentOffset(bottomOffset, animated: false)
        }

        // Called when user types in terminal
        func send(source: TerminalView, data: ArraySlice<UInt8>) {
            let string = String(bytes: data, encoding: .utf8) ?? ""
            let session = sessionName
            Task { @MainActor in
                connectionManager.sendInput(string, to: session)
            }
        }

        // Called when terminal is scrolled
        func scrolled(source: TerminalView, position: Double) {
            // Not needed for remote terminal
        }

        // Called when terminal title changes
        func setTerminalTitle(source: TerminalView, title: String) {
            // Could update navigation title
        }

        // Called when terminal size changes
        func sizeChanged(source: TerminalView, newCols: Int, newRows: Int) {
            // Store for later use (e.g., triggering resize after scrollback load)
            lastCols = newCols
            lastRows = newRows
            let session = sessionName
            Task { @MainActor in
                connectionManager.sendResize(cols: newCols, rows: newRows, for: session)
            }
        }

        // Called when clipboard operation requested
        func clipboardCopy(source: TerminalView, content: Data) {
            if let string = String(data: content, encoding: .utf8) {
                UIPasteboard.general.string = string
            }
        }

        // Called to request clipboard content
        func requestOpenLink(source: TerminalView, link: String, params: [String : String]) {
            if let url = URL(string: link) {
                UIApplication.shared.open(url)
            }
        }

        // Bell sound
        func bell(source: TerminalView) {
            // Could play haptic feedback
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.warning)
        }

        // Range changed
        func rangeChanged(source: SwiftTerm.TerminalView, startY: Int, endY: Int) {
            // Not needed
        }

        func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {
            // Not needed for remote
        }

        func hostCurrentDocumentUpdate(source: SwiftTerm.TerminalView, documentUrl: URL?) {
            // Not needed
        }
    }
}

/// How much of the screen the keyboard covers. With a hardware keyboard iOS can
/// report a full-height frame that sits below the screen, so its height alone
/// would lift the composer for a keyboard nobody sees.
private func visibleKeyboardHeight(_ notification: Notification) -> CGFloat {
    guard let frame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else { return 0 }
    guard let screen = notification.object as? UIScreen else { return frame.height }
    return frame.intersection(screen.bounds).height
}
