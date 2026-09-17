// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

struct OneThingSettings: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var permissions = Permissions.shared
    @ObservedObject private var service = OneThingService.shared

    @AppStorage(DefaultsKey.oneThingEnabled) private var enabled = true
    @AppStorage(DefaultsKey.oneThingMaxChars) private var maxChars = 40

    @State private var historySearch = ""
    @State private var showingClearConfirmation = false

    private var filteredHistory: [OneThingTask] {
        if historySearch.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return service.history
        }
        return service.history.filter {
            $0.text.localizedCaseInsensitiveContains(historySearch)
        }
    }

    var body: some View {
        Form {
            // General Activation
            Section {
                Toggle("Enable One Thing", isOn: $enabled)
                    .onChange(of: enabled) { _, _ in
                        OneThingService.shared.syncWithPreferences()
                    }

                Text("Keep your most important task visible in the menu bar to maintain focus on one thing at a time.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // Accessibility permission requirement
            if !permissions.accessibility {
                Section("Permission required") {
                    PermissionRow(kind: .accessibility)
                    Text("Accessibility permission is required to automatically capture selected text from other applications.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            // Keyboard Shortcuts
            Section("Keyboard Shortcuts") {
                OneThingShortcutRow(
                    title: "Open / Close Quick Panel",
                    storageKey: DefaultsKey.oneThingShortcutToggle,
                    defaultShortcut: .oneThingToggleDefault,
                    isEnabled: enabled
                ) {
                    OneThingService.shared.syncWithPreferences()
                }

                OneThingShortcutRow(
                    title: "Capture Selection as Task",
                    storageKey: DefaultsKey.oneThingShortcutFromSelection,
                    defaultShortcut: .oneThingFromSelectionDefault,
                    isEnabled: enabled
                ) {
                    OneThingService.shared.syncWithPreferences()
                }

                OneThingShortcutRow(
                    title: "Quick Complete Active Task",
                    storageKey: DefaultsKey.oneThingShortcutComplete,
                    defaultShortcut: .oneThingCompleteDefault,
                    isEnabled: enabled
                ) {
                    OneThingService.shared.syncWithPreferences()
                }
            }

            // Menu Bar Appearance
            Section("Menu Bar") {
                Stepper(value: $maxChars, in: 10...100, step: 5) {
                    HStack {
                        Text("Menu bar character limit:")
                        Spacer()
                        Text("\(maxChars) characters")
                            .foregroundStyle(.secondary)
                    }
                }
                .onChange(of: maxChars) { _, _ in
                    OneThingService.shared.updateStatusItem()
                }

                Slider(value: Binding(
                    get: { Double(maxChars) },
                    set: { maxChars = Int($0) }
                ), in: 10...100, step: 5)
                .onChange(of: maxChars) { _, _ in
                    OneThingService.shared.updateStatusItem()
                }

                Text("Longer tasks will be truncated with an ellipsis (…) in the menu bar, keeping the full text accessible on hover.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // History Section
            Section("Completed Tasks History") {
                if service.history.isEmpty {
                    Text("No completed tasks yet.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 8)
                } else {
                    HStack {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(.secondary)
                        TextField("Search history…", text: $historySearch)
                            .textFieldStyle(.plain)
                        if !historySearch.isEmpty {
                            Button {
                                historySearch = ""
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.tertiary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(6)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(Color.primary.opacity(0.05))
                    )

                    List {
                        ForEach(filteredHistory) { task in
                            HStack(alignment: .top, spacing: 10) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                                    .padding(.top, 2)

                                VStack(alignment: .leading, spacing: 3) {
                                    Text(task.text)
                                        .font(.body)
                                        .foregroundStyle(.primary)

                                    if let date = task.completedAt {
                                        Text(date, format: .dateTime.month().day().hour().minute())
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                            .padding(.vertical, 3)
                        }
                    }
                    .frame(minHeight: 140, maxHeight: 220)

                    HStack {
                        Spacer()
                        Button(role: .destructive) {
                            showingClearConfirmation = true
                        } label: {
                            Label("Clear History", systemImage: "trash")
                        }
                        .confirmationDialog(
                            "Clear Task History?",
                            isPresented: $showingClearConfirmation,
                            titleVisibility: .visible
                        ) {
                            Button("Clear History", role: .destructive) {
                                OneThingService.shared.clearHistory()
                            }
                            Button("Cancel", role: .cancel) {}
                        } message: {
                            Text("This will permanently remove all completed tasks from your history.")
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Shortcut Row Helper

private struct OneThingShortcutRow: View {
    let title: String
    let storageKey: String
    let defaultShortcut: GlobalShortcut
    let isEnabled: Bool
    let onChange: () -> Void

    @AppStorage private var rawValue: String
    @State private var errorText: String?
    @State private var isRecording = false

    init(title: String, storageKey: String, defaultShortcut: GlobalShortcut, isEnabled: Bool, onChange: @escaping () -> Void) {
        self.title = title
        self.storageKey = storageKey
        self.defaultShortcut = defaultShortcut
        self.isEnabled = isEnabled
        self.onChange = onChange
        self._rawValue = AppStorage(wrappedValue: defaultShortcut.storageValue, storageKey)
    }

    private var shortcut: GlobalShortcut {
        GlobalShortcut(storageValue: rawValue) ?? defaultShortcut
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                Spacer()
                ShortcutRecorderButton(
                    shortcut: shortcut,
                    isEnabled: isEnabled,
                    waitingTitle: L10n.shared.s.shortcutPressKeys,
                    notCapturedAction: { errorText = L10n.shared.s.shortcutNotCaptured },
                    recordingChanged: { recording in
                        isRecording = recording
                        if recording { errorText = nil }
                    },
                    invalidAction: { errorText = L10n.shared.s.shortcutInvalid },
                    captureAction: { newShortcut in
                        if let conflict = GlobalShortcutRole.conflict(for: newShortcut, excluding: nil) {
                            errorText = String(format: L10n.shared.s.shortcutConflictFormat, conflict.title(L10n.shared.s))
                            return
                        }
                        if newShortcut.conflictsWithSystemShortcut {
                            errorText = String(format: L10n.shared.s.shortcutConflictFormat, "macOS")
                            return
                        }
                        rawValue = newShortcut.storageValue
                        errorText = nil
                        onChange()
                    }
                )
                .frame(width: 108)
                .disabled(!isEnabled)

                Button(L10n.shared.s.shortcutReset) {
                    rawValue = defaultShortcut.storageValue
                    errorText = nil
                    onChange()
                }
                .disabled(!isEnabled || shortcut == defaultShortcut)
            }

            if let errorText {
                Text(errorText)
                    .font(.caption)
                    .foregroundStyle(.orange)
            } else if isRecording {
                Text(ShortcutRecordingCaption.text(L10n.shared.s, canClear: false))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
