import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var connectionManager: ConnectionManager
    @EnvironmentObject var themeManager: ThemeManager
    @EnvironmentObject var shortcutsManager: ShortcutsManager

    var body: some View {
        NavigationStack {
            List {
                // Appearance Section
                Section {
                    Picker("Appearance", selection: $themeManager.appearanceMode) {
                        ForEach(AppearanceMode.allCases, id: \.self) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                } header: {
                    Text("Appearance")
                }

                // Terminal Section
                Section {
                    NavigationLink {
                        ThemeSettingsView()
                    } label: {
                        HStack {
                            Label("Terminal Theme", systemImage: "paintpalette.fill")
                            Spacer()
                            Text(themeManager.currentTheme.name)
                                .foregroundStyle(.secondary)
                        }
                    }

                    NavigationLink {
                        ShortcutsSettingsView()
                    } label: {
                        Label("Keyboard Shortcuts", systemImage: "keyboard")
                    }
                } header: {
                    Text("Terminal")
                }

                // Connection Info Section
                Section {
                    if let serverURL = connectionManager.serverURL {
                        HStack {
                            Text("Server")
                            Spacer()
                            Text(serverURL)
                                .foregroundStyle(.secondary)
                                .font(.footnote)
                        }
                    }

                    HStack {
                        Text("Status")
                        Spacer()
                        HStack(spacing: 6) {
                            Circle()
                                .fill(connectionManager.isConnected ? .green : .red)
                                .frame(width: 8, height: 8)
                            Text(connectionManager.isConnected ? "Connected" : "Disconnected")
                                .foregroundStyle(.secondary)
                        }
                    }

                    HStack {
                        Text("Sessions")
                        Spacer()
                        Text("\(connectionManager.sessions.count)")
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Connection")
                }

                // Disconnect Section
                if connectionManager.isConnected {
                    Section {
                        Button(role: .destructive) {
                            connectionManager.disconnect()
                            dismiss()
                        } label: {
                            HStack {
                                Spacer()
                                Text("Disconnect")
                                Spacer()
                            }
                        }
                    }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}
