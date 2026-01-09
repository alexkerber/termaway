import SwiftUI

struct ThemeSettingsView: View {
    @ObservedObject var themeManager = ThemeManager.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    livePreviewSection
                    themeGridSection
                    fontSizeSection
                }
                .padding()
            }
            .background(Color.black.ignoresSafeArea())
            .navigationTitle("Appearance")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private var livePreviewSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Preview")
                .font(.headline)
                .foregroundColor(.secondary)
            TerminalPreview(theme: themeManager.currentTheme, fontSize: themeManager.fontSize)
                .frame(height: 160)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.1), lineWidth: 1))
        }
    }

    private var themeGridSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Themes")
                .font(.headline)
                .foregroundColor(.secondary)
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                ForEach(themeManager.builtInThemes) { theme in
                    ThemePreviewCard(theme: theme, isSelected: theme.id == themeManager.currentTheme.id) {
                        withAnimation(.easeInOut(duration: 0.2)) { themeManager.currentTheme = theme }
                    }
                }
            }
        }
    }

    private var fontSizeSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Font Size")
                .font(.headline)
                .foregroundColor(.secondary)
            VStack(spacing: 16) {
                HStack {
                    Text("A").font(.system(size: 12, design: .monospaced)).foregroundColor(.secondary)
                    Slider(value: $themeManager.fontSize, in: 10...24, step: 1).tint(.blue)
                    Text("A").font(.system(size: 20, design: .monospaced)).foregroundColor(.secondary)
                }
                Text("\(Int(themeManager.fontSize)) pt")
                    .font(.subheadline.monospacedDigit())
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 16).padding(.vertical, 8)
                    .background(.ultraThinMaterial, in: Capsule())
            }
            .padding()
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
        }
    }
}

struct ThemePreviewCard: View {
    let theme: TerminalTheme
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                HStack(spacing: 2) {
                    ForEach(0..<6) { index in theme.previewColors[index].frame(maxWidth: .infinity) }
                }
                .frame(height: 40)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                Text(theme.name).font(.subheadline.weight(.medium)).foregroundColor(.primary)
            }
            .padding(12)
            .background(theme.background.color)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(isSelected ? Color.blue : Color.white.opacity(0.1), lineWidth: isSelected ? 2 : 1))
            .shadow(color: isSelected ? .blue.opacity(0.3) : .clear, radius: 8)
        }
        .buttonStyle(.plain)
    }
}

struct TerminalPreview: View {
    let theme: TerminalTheme
    let fontSize: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 0) {
                Text("user@mac").foregroundColor(theme.ansiColors[2].color)
                Text(":").foregroundColor(theme.foreground.color)
                Text("~").foregroundColor(theme.ansiColors[4].color)
                Text("$ ls -la").foregroundColor(theme.foreground.color)
            }
            Text("drwxr-xr-x  5 user staff  160 Jan  9 10:30 Documents").foregroundColor(theme.foreground.color)
            Text("drwxr-xr-x  3 user staff   96 Jan  9 09:15 Downloads").foregroundColor(theme.foreground.color)
            HStack(spacing: 0) {
                Text("user@mac").foregroundColor(theme.ansiColors[2].color)
                Text(":").foregroundColor(theme.foreground.color)
                Text("~").foregroundColor(theme.ansiColors[4].color)
                Text("$ ").foregroundColor(theme.foreground.color)
                Rectangle().fill(theme.cursor.color).frame(width: fontSize * 0.6, height: fontSize)
            }
            Spacer()
        }
        .font(.system(size: fontSize, design: .monospaced))
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.background.color)
    }
}

#Preview { ThemeSettingsView() }
