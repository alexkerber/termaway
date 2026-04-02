import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var connectionManager: ConnectionManager
    @EnvironmentObject var themeManager: ThemeManager
    @EnvironmentObject var shortcutsManager: ShortcutsManager
    @EnvironmentObject var biometricManager: BiometricManager

    var body: some View {
        NavigationStack {
            Form {
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
                                .foregroundStyle(.primary)
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
                            .foregroundStyle(.primary)
                    }

                    if shortcutsManager.showToolbar {
                        Toggle(isOn: Binding(
                            get: { shortcutsManager.showKeyboardButton },
                            set: { shortcutsManager.showKeyboardButton = $0 }
                        )) {
                            Label("Keyboard Button", systemImage: "keyboard.badge.ellipsis")
                                .foregroundStyle(.primary)
                        }

                        NavigationLink {
                            ShortcutsSettingsView()
                        } label: {
                            Label("Edit Shortcuts", systemImage: "slider.horizontal.3")
                                .foregroundStyle(.primary)
                        }
                    }
                    Toggle(isOn: Binding(
                        get: { UserDefaults.standard.object(forKey: "swipeGesturesEnabled") == nil || UserDefaults.standard.bool(forKey: "swipeGesturesEnabled") },
                        set: { UserDefaults.standard.set($0, forKey: "swipeGesturesEnabled") }
                    )) {
                        Label("Swipe Arrow Keys", systemImage: "hand.draw")
                            .foregroundStyle(.primary)
                    }
                } header: {
                    Text("Terminal")
                } footer: {
                    if shortcutsManager.showToolbar && !shortcutsManager.showKeyboardButton {
                        Text("Keyboard button hidden. Turn on if you need the on-screen keyboard.")
                    }
                }

                // Security Section
                if biometricManager.biometricsAvailable {
                    Section {
                        Toggle(isOn: Binding(
                            get: { biometricManager.biometricEnabled },
                            set: { biometricManager.biometricEnabled = $0 }
                        )) {
                            Label("Require \(biometricManager.biometricTypeName)", systemImage: biometricManager.biometricTypeName == "Face ID" ? "faceid" : "touchid")
                                .foregroundStyle(.primary)
                        }
                    } header: {
                        Text("Security")
                    } footer: {
                        Text("Lock TermAway when you leave the app. Unlock with \(biometricManager.biometricTypeName).")
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
                        LabeledContent("Server") {
                            Text(serverURL)
                                .font(.footnote)
                        }
                    }

                    LabeledContent("Status") {
                        HStack(spacing: 6) {
                            Image(systemName: "circle.fill")
                                .font(.system(size: 8))
                                .foregroundStyle(connectionManager.isConnected ? Color.green : Color.red)
                                .symbolEffect(.pulse, isActive: connectionManager.isConnected)
                            Text(connectionManager.isConnected ? "Connected" : "Disconnected")
                        }
                    }

                    LabeledContent("Windows") {
                        Text("\(connectionManager.sessions.count)")
                            .contentTransition(.numericText())
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
        .presentationBackground(.regularMaterial)
        .presentationCornerRadius(20)
        .preferredColorScheme(themeManager.appearanceMode.colorScheme)
    }
}
