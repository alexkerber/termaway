import SwiftUI

struct ShortcutsSettingsView: View {
    @EnvironmentObject var shortcutsManager: ShortcutsManager
    @Environment(\.dismiss) var dismiss
    @State private var showingAddSheet = false
    @State private var editingShortcut: Shortcut?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(shortcutsManager.shortcuts) { shortcut in
                        ShortcutRow(shortcut: shortcut)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                editingShortcut = shortcut
                            }
                    }
                    .onDelete(perform: shortcutsManager.deleteShortcut)
                    .onMove(perform: shortcutsManager.moveShortcut)
                } header: {
                    Text("Shortcuts")
                } footer: {
                    Text("Tap to edit, swipe to delete. Drag to reorder.")
                }

                Section {
                    Button(action: { showingAddSheet = true }) {
                        Label("Add Shortcut", systemImage: "plus.circle.fill")
                    }

                    Button(role: .destructive, action: shortcutsManager.resetToDefaults) {
                        Label("Reset to Defaults", systemImage: "arrow.counterclockwise")
                    }
                }
            }
            .navigationTitle("Keyboard Shortcuts")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    EditButton()
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $showingAddSheet) {
                ShortcutEditView(shortcut: nil) { newShortcut in
                    shortcutsManager.addShortcut(newShortcut)
                }
            }
            .sheet(item: $editingShortcut) { shortcut in
                ShortcutEditView(shortcut: shortcut) { updatedShortcut in
                    shortcutsManager.updateShortcut(updatedShortcut)
                }
            }
        }
    }
}

struct ShortcutRow: View {
    let shortcut: Shortcut

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(shortcut.name)
                    .font(.body)

                Text(shortcut.displayLabel)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(Color.secondary.opacity(0.2))
                    .cornerRadius(4)
            }

            Spacer()

            if shortcut.showInToolbar {
                Image(systemName: "keyboard")
                    .foregroundColor(.blue)
                    .font(.caption)
            }

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 4)
    }
}

struct ShortcutEditView: View {
    @Environment(\.dismiss) var dismiss
    let shortcut: Shortcut?
    let onSave: (Shortcut) -> Void

    @State private var name: String = ""
    @State private var displayLabel: String = ""
    @State private var command: String = ""
    @State private var showInToolbar: Bool = true
    @State private var useControlChar: Bool = false
    @State private var controlCharacter: String = ""

    var isEditing: Bool { shortcut != nil }

    var body: some View {
        NavigationStack {
            Form {
                Section("Details") {
                    TextField("Name", text: $name)
                    TextField("Display Label", text: $displayLabel)
                        .textInputAutocapitalization(.never)
                }

                Section("Command") {
                    Toggle("Control Character", isOn: $useControlChar)

                    if useControlChar {
                        HStack {
                            Text("Ctrl +")
                            TextField("Character (A-Z)", text: $controlCharacter)
                                .textInputAutocapitalization(.characters)
                                .autocorrectionDisabled()
                                .onChange(of: controlCharacter) { _, newValue in
                                    // Limit to single character
                                    if newValue.count > 1 {
                                        controlCharacter = String(newValue.prefix(1))
                                    }
                                }
                        }
                    } else {
                        TextField("Raw Command", text: $command)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    }
                }

                Section {
                    Toggle("Show in Toolbar", isOn: $showInToolbar)
                } footer: {
                    Text("When enabled, this shortcut appears in the keyboard toolbar.")
                }

                if !isEditing {
                    Section("Presets") {
                        Button("Tab") { applyPreset(name: "Tab", display: "Tab", command: "\t") }
                        Button("Escape") { applyPreset(name: "Escape", display: "Esc", command: "\u{1B}") }
                        Button("Enter") { applyPreset(name: "Enter", display: "Return", command: "\r") }
                        Button("Up Arrow") { applyPreset(name: "Up Arrow", display: "\u{2191}", command: "\u{1B}[A") }
                        Button("Down Arrow") { applyPreset(name: "Down Arrow", display: "\u{2193}", command: "\u{1B}[B") }
                        Button("Left Arrow") { applyPreset(name: "Left Arrow", display: "\u{2190}", command: "\u{1B}[D") }
                        Button("Right Arrow") { applyPreset(name: "Right Arrow", display: "\u{2192}", command: "\u{1B}[C") }
                    }
                }
            }
            .navigationTitle(isEditing ? "Edit Shortcut" : "New Shortcut")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveShortcut()
                    }
                    .disabled(name.isEmpty || displayLabel.isEmpty)
                }
            }
            .onAppear {
                if let shortcut = shortcut {
                    name = shortcut.name
                    displayLabel = shortcut.displayLabel
                    command = shortcut.command
                    showInToolbar = shortcut.showInToolbar

                    // Check if this is a control character
                    if shortcut.command.count == 1,
                       let ascii = shortcut.command.unicodeScalars.first?.value,
                       ascii >= 1 && ascii <= 26 {
                        useControlChar = true
                        controlCharacter = String(Character(UnicodeScalar(ascii + 64)!))
                    }
                }
            }
        }
    }

    private func applyPreset(name: String, display: String, command: String) {
        self.name = name
        self.displayLabel = display
        self.command = command
        self.useControlChar = false
    }

    private func saveShortcut() {
        let finalCommand: String
        if useControlChar, let char = controlCharacter.uppercased().first {
            finalCommand = Shortcut.controlChar(char)
        } else {
            finalCommand = command
        }

        let newShortcut = Shortcut(
            id: shortcut?.id ?? UUID(),
            name: name,
            command: finalCommand,
            displayLabel: displayLabel,
            showInToolbar: showInToolbar
        )
        onSave(newShortcut)
        dismiss()
    }
}

#Preview {
    ShortcutsSettingsView()
        .environmentObject(ShortcutsManager())
}
