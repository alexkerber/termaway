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

                    Toggle(isOn: Binding(
                        get: { shortcutsManager.showToolbar },
                        set: { shortcutsManager.showToolbar = $0 }
                    )) {
                        Label("Shortcuts Toolbar", systemImage: "keyboard")
                    }

                    if shortcutsManager.showToolbar {
                        Toggle(isOn: Binding(
                            get: { shortcutsManager.showKeyboardButton },
                            set: { shortcutsManager.showKeyboardButton = $0 }
                        )) {
                            Label("Keyboard Button", systemImage: "keyboard.badge.ellipsis")
                        }

                        NavigationLink {
                            ShortcutsSettingsView()
                        } label: {
                            Label("Edit Shortcuts", systemImage: "slider.horizontal.3")
                        }
                    }
                } header: {
                    Text("Terminal")
                } footer: {
                    if shortcutsManager.showToolbar && !shortcutsManager.showKeyboardButton {
                        Text("Keyboard button hidden. Turn on if you need the on-screen keyboard.")
                    }
                }

                // Notifications Section
                Section {
                    Toggle("Connection Alerts", isOn: Binding(
                        get: { connectionManager.connectionNotificationsEnabled },
                        set: { connectionManager.connectionNotificationsEnabled = $0 }
                    ))
                } header: {
                    Text("Notifications")
                } footer: {
                    Text("Get notified when someone connects to your Mac. Also appears on Apple Watch.")
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

                // About Section
                Section {
                    VStack(spacing: 4) {
                        Text("TermAway v\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")")
                            .font(.footnote)
                            .fontWeight(.medium)

                        Link("Created by Alex Kerber", destination: URL(string: "https://alexkerber.com")!)
                            .font(.footnote)
                    }
                    .frame(maxWidth: .infinity)
                    .listRowBackground(Color.clear)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .modifier(ToolbarGlassModifier())
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
