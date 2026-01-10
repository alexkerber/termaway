import SwiftUI

struct ThemeSettingsView: View {
    @EnvironmentObject var themeManager: ThemeManager
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(TerminalTheme.presets) { theme in
                        ThemePreviewRow(
                            theme: theme,
                            isSelected: themeManager.currentTheme.id == theme.id
                        ) {
                            themeManager.setTheme(theme)
                        }
                    }
                } header: {
                    Label("Theme", systemImage: "paintpalette")
                }

                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("Font Size")
                            Spacer()
                            Text("\(Int(themeManager.fontSize))pt")
                                .foregroundColor(.secondary)
                                .monospacedDigit()
                        }

                        Slider(value: $themeManager.fontSize, in: 10...24, step: 1)
                            .tint(.blue)
                    }
                    .padding(.vertical, 4)
                } header: {
                    Label("Font", systemImage: "textformat.size")
                } footer: {
                    Text("Changes apply to new terminal sessions")
                }

                Section {
                    ThemeLivePreview()
                        .frame(height: 120)
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                } header: {
                    Label("Preview", systemImage: "eye")
                }
            }
            .navigationTitle("Appearance")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

struct ThemePreviewRow: View {
    let theme: TerminalTheme
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                // Color preview
                HStack(spacing: 2) {
                    Rectangle()
                        .fill(Color(uiColor: theme.backgroundColor))
                        .frame(width: 20, height: 32)
                    Rectangle()
                        .fill(Color(uiColor: theme.foregroundColor))
                        .frame(width: 20, height: 32)
                    Rectangle()
                        .fill(Color(uiColor: theme.cursorColor))
                        .frame(width: 10, height: 32)
                }
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(Color.white.opacity(0.2), lineWidth: 1)
                )

                Text(theme.name)
                    .foregroundColor(.primary)

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark")
                        .foregroundColor(.blue)
                        .fontWeight(.semibold)
                }
            }
        }
    }
}

struct ThemeLivePreview: View {
    @EnvironmentObject var themeManager: ThemeManager

    var body: some View {
        ZStack {
            Color(uiColor: themeManager.currentTheme.backgroundColor)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 0) {
                    Text("~ ")
                        .foregroundColor(.green)
                    Text("ls -la")
                        .foregroundColor(Color(uiColor: themeManager.currentTheme.foregroundColor))
                }

                Text("drwxr-xr-x  5 user  staff   160 Jan  8 10:30 Documents")
                    .foregroundColor(Color(uiColor: themeManager.currentTheme.foregroundColor).opacity(0.7))

                HStack(spacing: 0) {
                    Text("~ ")
                        .foregroundColor(.green)
                    Rectangle()
                        .fill(Color(uiColor: themeManager.currentTheme.cursorColor))
                        .frame(width: 8, height: CGFloat(themeManager.fontSize))
                }
            }
            .font(.system(size: themeManager.fontSize, weight: .regular, design: .monospaced))
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Color.white.opacity(0.1), lineWidth: 1)
        )
        .padding(.horizontal)
        .padding(.vertical, 8)
    }
}

#Preview {
    ThemeSettingsView()
        .environmentObject(ThemeManager.shared)
}
