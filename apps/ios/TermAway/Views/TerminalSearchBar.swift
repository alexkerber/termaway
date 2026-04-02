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
extension Notification.Name {
    static let dismissTerminalSearch = Notification.Name("dismissTerminalSearch")
}

// MARK: - Terminal Search Manager
/// Manages search state and logic for searching through terminal output.
/// Uses the session output buffer from ConnectionManager (stripped of ANSI codes)
/// and provides proportional scroll-to-match via SwiftTerm's TerminalView.
@MainActor
class TerminalSearchManager: ObservableObject {
    @Published var searchQuery = ""
    @Published var matches: [Range<String.Index>] = []
    @Published var currentMatchIndex = 0

    private var searchableText = ""
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
    func updateSearchableText(from outputBuffer: String) {
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
            currentMatchIndex = 0
            return
        }

        let work = DispatchWorkItem { [weak self] in
            guard let self = self else { return }

            let text = self.searchableText
            let query = self.searchQuery.lowercased()
            let lowered = text.lowercased()

            var found: [Range<String.Index>] = []
            var searchStart = lowered.startIndex

            while searchStart < lowered.endIndex,
                  let range = lowered.range(of: query, range: searchStart..<lowered.endIndex) {
                found.append(range.lowerBound..<range.upperBound)
                searchStart = range.upperBound
            }

            Task { @MainActor in
                self.matches = found
                if self.currentMatchIndex >= found.count {
                    self.currentMatchIndex = max(0, found.count - 1)
                }
            }
        }

        searchWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: work)
    }

    /// Navigate to the next match
    func nextMatch() {
        guard !matches.isEmpty else { return }
        currentMatchIndex = (currentMatchIndex + 1) % matches.count
    }

    /// Navigate to the previous match
    func previousMatch() {
        guard !matches.isEmpty else { return }
        currentMatchIndex = (currentMatchIndex - 1 + matches.count) % matches.count
    }

    /// Scroll the terminal to show the current match.
    /// Uses a proportional approach: the match's position in the text maps to a position
    /// in the terminal's scrollable content.
    func scrollToCurrentMatch(in terminalView: TerminalView?) {
        guard let terminalView = terminalView,
              !matches.isEmpty,
              currentMatchIndex < matches.count,
              !searchableText.isEmpty else { return }

        let match = matches[currentMatchIndex]

        // Calculate the proportional position of the match in the full text
        let matchPosition = searchableText.distance(from: searchableText.startIndex, to: match.lowerBound)
        let totalLength = searchableText.count
        let proportion = CGFloat(matchPosition) / CGFloat(totalLength)

        // Map that proportion to the terminal's scroll content
        let contentHeight = terminalView.contentSize.height
        let frameHeight = terminalView.bounds.height
        let maxOffset = max(0, contentHeight - frameHeight)
        let targetOffset = proportion * maxOffset
        let clampedOffset = max(0, min(targetOffset, maxOffset))

        terminalView.setContentOffset(CGPoint(x: 0, y: clampedOffset), animated: true)
    }

    func reset() {
        searchQuery = ""
        matches = []
        currentMatchIndex = 0
        searchableText = ""
        lineStartOffsets = []
    }
}
