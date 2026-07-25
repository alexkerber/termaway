import SwiftUI
import SwiftTerm

// MARK: - Terminal Search Bar
/// A search bar that appears at the top of the terminal for searching through output.
/// Uses glass/blur background consistent with the app's design language.
struct TerminalSearchBar: View {
    @Binding var searchQuery: String
    @Binding var isVisible: Bool
    let matchCount: Int
    let currentMatch: Int
    let iconColor: SwiftUI.Color
    let onNext: () -> Void
    let onPrevious: () -> Void
    let onDismiss: () -> Void

    @FocusState private var isSearchFieldFocused: Bool

    var body: some View {
        HStack(spacing: 8) {
            // Search field
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(iconColor.opacity(0.6))

                TextField("Search terminal", text: $searchQuery)
                    .font(.system(size: 15))
                    .foregroundColor(iconColor)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .focused($isSearchFieldFocused)
                    .submitLabel(.search)

                if !searchQuery.isEmpty {
                    Button(action: { searchQuery = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(iconColor.opacity(0.5))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background {
                if #available(iOS 26.0, *) {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(.clear)
                        .glassEffect(.regular)
                } else {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(.ultraThinMaterial)
                }
            }

            // Match count
            if !searchQuery.isEmpty {
                Text(matchCount > 0 ? "\(currentMatch) of \(matchCount)" : "No results")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(iconColor.opacity(0.7))
                    .lineLimit(1)
                    .fixedSize()
            }

            // Navigation arrows
            if matchCount > 0 {
                HStack(spacing: 2) {
                    Button(action: {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        onPrevious()
                    }) {
                        Image(systemName: "chevron.up")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(iconColor.opacity(0.85))
                            .frame(width: 30, height: 30)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(ShortcutKeyButtonStyle())

                    Button(action: {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        onNext()
                    }) {
                        Image(systemName: "chevron.down")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(iconColor.opacity(0.85))
                            .frame(width: 30, height: 30)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(ShortcutKeyButtonStyle())
                }
            }

            // Close button
            Button(action: {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                onDismiss()
            }) {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(iconColor.opacity(0.7))
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(ShortcutKeyButtonStyle())
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background {
            if #available(iOS 26.0, *) {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(.clear)
                    .glassEffect(.regular)
            } else {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(.ultraThinMaterial)
            }
        }
        .onAppear {
            isSearchFieldFocused = true
        }
    }
}

// MARK: - Inline Search Field
/// A compact search field that replaces the top bar buttons with an expanding search experience.
/// Animates in from the trailing edge like Apple's native search bars.
struct InlineSearchField: View {
    @ObservedObject var searchManager: TerminalSearchManager
    let iconColor: SwiftUI.Color
    let onDismiss: () -> Void

    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 8) {
            // Search input with glass background
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(iconColor.opacity(0.5))

                TextField("Search", text: $searchManager.searchQuery)
                    .font(.system(size: 15))
                    .foregroundColor(iconColor)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .focused($isFocused)
                    .submitLabel(.search)

                if !searchManager.searchQuery.isEmpty {
                    Button(action: { searchManager.searchQuery = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(iconColor.opacity(0.4))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background {
                if #available(iOS 26.0, *) {
                    Capsule()
                        .fill(.clear)
                        .glassEffect(.regular)
                } else {
                    Capsule()
                        .fill(.ultraThinMaterial)
                }
            }

            // Match count + navigation
            if !searchManager.searchQuery.isEmpty {
                Text(searchManager.matchCount > 0 ? "\(searchManager.currentMatchDisplay)/\(searchManager.matchCount)" : "0")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(iconColor.opacity(0.6))
                    .fixedSize()
                    .contentTransition(.numericText())

                if searchManager.matchCount > 0 {
                    HStack(spacing: 0) {
                        Button(action: {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            searchManager.previousMatch()
                        }) {
                            Image(systemName: "chevron.up")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(iconColor.opacity(0.8))
                                .frame(width: 28, height: 28)
                        }
                        .buttonStyle(.plain)

                        Button(action: {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            searchManager.nextMatch()
                        }) {
                            Image(systemName: "chevron.down")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(iconColor.opacity(0.8))
                                .frame(width: 28, height: 28)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            // Cancel button
            Button("Cancel") {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                onDismiss()
            }
            .font(.system(size: 15, weight: .regular))
            .foregroundStyle(iconColor.opacity(0.8))
            .fixedSize()
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                isFocused = true
            }
        }
    }
}

// MARK: - Dismiss Search Notification
extension TerminalView {
    /// Scroll so that a match `proportion` of the way through the session's
    /// output is on screen.
    ///
    /// ponytail: proportional, not exact — it assumes the output buffer maps
    /// linearly onto the scrollback. Good enough to land on the right screenful;
    /// mapping through SwiftTerm's buffer coordinates would be exact.
    func scrollToSearchMatch(proportion: Double) {
        let maxOffset = max(0, contentSize.height - bounds.height)
        guard maxOffset > 0 else { return }
        let y = max(0, min(CGFloat(proportion) * maxOffset, maxOffset))
        setContentOffset(CGPoint(x: 0, y: y), animated: true)
    }
}

extension Notification.Name {
    static let dismissTerminalSearch = Notification.Name("dismissTerminalSearch")
    static let scrollToSearchMatch = Notification.Name("scrollToSearchMatch")
}

// MARK: - Terminal Search Manager
/// Manages search state and logic for searching through terminal output.
/// Uses the session output buffer from ConnectionManager (stripped of ANSI codes)
/// and provides proportional scroll-to-match via SwiftTerm's TerminalView.
@MainActor
class TerminalSearchManager: ObservableObject {
    // Re-run on every keystroke. The query is bound straight to the text field,
    // and nothing else observed it — so the only search that ever ran was the
    // one when the field opened, with the field empty. It reported 0 matches
    // for a word plainly on screen. performSearch debounces, so typing fast
    // costs one pass, not one per character.
    @Published var searchQuery = "" {
        didSet {
            guard searchQuery != oldValue else { return }
            performSearch()
        }
    }
    @Published var matches: [Range<String.Index>] = []
    @Published var currentMatchIndex = 0

    private var searchableText = ""
    /// Session whose terminal should follow the current match.
    private var sessionName = ""
    /// Character offsets of each match, and the length they were measured
    /// against. Kept as plain integers: a String.Index belongs to the string it
    /// came from, and the buffer is replaced on every output update.
    private var matchOffsets: [Int] = []
    private var searchableLength = 0
    /// Line offsets into searchableText (character index where each line starts)
    private var lineStartOffsets: [String.Index] = []
    private var searchWorkItem: DispatchWorkItem?

    var matchCount: Int { matches.count }

    /// The 1-based display index of the current match
    var currentMatchDisplay: Int {
        guard !matches.isEmpty else { return 0 }
        return currentMatchIndex + 1
    }

    /// Extract searchable text from the session's output buffer in ConnectionManager.
    /// The output buffer accumulates all terminal output (including scrollback sent on attach).
    /// We strip ANSI escape codes to produce clean searchable text.
    func updateSearchableText(from outputBuffer: String, session: String) {
        sessionName = session
        searchableText = Self.stripAnsiCodes(outputBuffer)
        performSearch()
    }

    /// Strip ANSI escape sequences and control characters from terminal output
    /// to produce plain searchable text.
    private static func stripAnsiCodes(_ text: String) -> String {
        // Remove ANSI escape sequences: ESC[ ... letter, ESC] ... ST, ESC( etc.
        var result = text
        // CSI sequences: ESC [ <params> <letter>
        let csiPattern = "\\x1b\\[[0-9;?]*[A-Za-z]"
        // OSC sequences: ESC ] ... (BEL or ST)
        let oscPattern = "\\x1b\\][^\u{07}\u{1b}]*(\\x07|\\x1b\\\\)"
        // Simple escape sequences: ESC followed by single char
        let simpleEscPattern = "\\x1b[()][A-Z0-9]"
        // Other escape sequences
        let otherEscPattern = "\\x1b[>=<]"

        for pattern in [csiPattern, oscPattern, simpleEscPattern, otherEscPattern] {
            if let regex = try? NSRegularExpression(pattern: pattern, options: []) {
                result = regex.stringByReplacingMatches(
                    in: result,
                    options: [],
                    range: NSRange(result.startIndex..., in: result),
                    withTemplate: ""
                )
            }
        }

        // Remove remaining control characters except newline, tab and carriage return
        result = result.filter { char in
            let scalar = char.unicodeScalars.first!.value
            return scalar >= 32 || char == "\n" || char == "\t" || char == "\r"
        }

        // Normalize \r\n to \n and remove lone \r
        result = result.replacingOccurrences(of: "\r\n", with: "\n")
        result = result.replacingOccurrences(of: "\r", with: "\n")

        return result
    }

    /// Perform the search with the current query (case-insensitive)
    func performSearch() {
        searchWorkItem?.cancel()

        guard !searchQuery.isEmpty else {
            matches = []
            matchOffsets = []
            currentMatchIndex = 0
            return
        }

        let work = DispatchWorkItem { [weak self] in
            guard let self = self else { return }

            let text = self.searchableText
            let query = self.searchQuery.lowercased()
            let lowered = text.lowercased()

            var found: [Range<String.Index>] = []
            var offsets: [Int] = []
            var searchStart = lowered.startIndex

            while searchStart < lowered.endIndex,
                  let range = lowered.range(of: query, range: searchStart..<lowered.endIndex) {
                found.append(range.lowerBound..<range.upperBound)
                offsets.append(lowered.distance(from: lowered.startIndex, to: range.lowerBound))
                searchStart = range.upperBound
            }
            let length = lowered.count

            Task { @MainActor in
                self.matches = found
                self.matchOffsets = offsets
                self.searchableLength = length
                if self.currentMatchIndex >= found.count {
                    self.currentMatchIndex = max(0, found.count - 1)
                }
                self.revealCurrentMatch()
            }
        }

        searchWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: work)
    }

    /// Navigate to the next match
    func nextMatch() {
        guard !matches.isEmpty else { return }
        currentMatchIndex = (currentMatchIndex + 1) % matches.count
        revealCurrentMatch()
    }

    /// Navigate to the previous match
    func previousMatch() {
        guard !matches.isEmpty else { return }
        currentMatchIndex = (currentMatchIndex - 1 + matches.count) % matches.count
        revealCurrentMatch()
    }

    /// Ask the terminal showing this session to bring the current match into
    /// view. The manager has no reference to a TerminalView — the views own
    /// theirs — so this goes out as a notification, the same way search
    /// dismissal already reaches them.
    private func revealCurrentMatch() {
        guard currentMatchIndex < matchOffsets.count,
              searchableLength > 0,
              !sessionName.isEmpty else { return }

        let proportion = Double(matchOffsets[currentMatchIndex]) / Double(searchableLength)

        NotificationCenter.default.post(
            name: .scrollToSearchMatch,
            object: nil,
            userInfo: ["session": sessionName, "proportion": proportion]
        )
    }

    func reset() {
        searchQuery = ""
        matches = []
        matchOffsets = []
        searchableLength = 0
        currentMatchIndex = 0
        searchableText = ""
        lineStartOffsets = []
    }
}
