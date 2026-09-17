import Carbon.HIToolbox
import SwiftUI

struct InstantSpacesSettings: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var permissions = Permissions.shared
    @ObservedObject private var service = InstantSpacesService.shared

    @AppStorage(DefaultsKey.instantSpacesEnabled) private var enabled = true
    @AppStorage(DefaultsKey.instantSpacesTrackpadSwipeEnabled) private var trackpadSwipe = true
    @AppStorage(DefaultsKey.instantSpacesSwipeDirectionReversed) private var swipeDirectionReversed = false
    @AppStorage(DefaultsKey.instantSpacesSpaceNumberingReversed) private var spaceNumberingReversed = false
    @AppStorage(DefaultsKey.instantSpacesGestureSpeed) private var gestureSpeed = 2000.0
    @AppStorage(DefaultsKey.instantSpacesOverlayDetectionEnabled) private var overlayDetection = true
    @AppStorage(DefaultsKey.instantSpacesHotkeysEnabled) private var hotkeysEnabled = true
    @AppStorage(DefaultsKey.instantSpacesShowMenuBarBadge) private var showMenuBarBadge = true

    @State private var currentSpaceInfo: SpaceInfo?

    var body: some View {
        Form {
            Section {
                Toggle("Enable Instant Spaces", isOn: $enabled)
                    .onChange(of: enabled) { _, _ in
                        InstantSpacesService.shared.syncWithPreferences()
                    }
                Text("Switches macOS desktop spaces instantly without the standard sliding animation.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if enabled && service.isRunning {
                    Label("Instant Spaces is active", systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.green)
                }
            }

            if !permissions.accessibility {
                Section("Permission required") {
                    PermissionRow(kind: .accessibility)
                }
            }

            Section("Trackpad Gesture") {
                Toggle("Intercept 3-finger horizontal trackpad swipe", isOn: $trackpadSwipe)
                    .onChange(of: trackpadSwipe) { _, _ in
                        InstantSpacesService.shared.syncWithPreferences()
                    }
                Text("Suppresses the system sliding animation and instantly switches spaces on 3-finger swipe.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Toggle("Reverse swipe direction", isOn: $swipeDirectionReversed)
                    .disabled(!trackpadSwipe || !enabled)

                Toggle("Ignore during Exposé and Mission Control", isOn: $overlayDetection)
                    .disabled(!trackpadSwipe || !enabled)
                Text("Passes the gesture through normally when Mission Control or App Exposé is active.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Gesture Velocity:")
                        Spacer()
                        Text("\(Int(gestureSpeed))")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    Slider(value: $gestureSpeed, in: 500...4000, step: 100)
                }
                .disabled(!trackpadSwipe || !enabled)
            }

            Section("Keyboard Shortcuts & Commands") {
                Toggle("Enable keyboard hotkeys", isOn: $hotkeysEnabled)
                    .onChange(of: hotkeysEnabled) { _, _ in
                        InstantSpacesService.shared.syncWithPreferences()
                    }

                Toggle("Reverse space numbering mapping", isOn: $spaceNumberingReversed)
                    .disabled(!hotkeysEnabled || !enabled)
                Text("Enable if your Mission Control spaces order is inverted relative to system CGS indexing.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if hotkeysEnabled && enabled {
                    if service.customShortcuts.isEmpty {
                        Text("No shortcuts configured.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(service.customShortcuts) { item in
                            InstantSpacesShortcutRow(
                                item: item,
                                onUpdate: { updated in
                                    service.updateShortcut(updated)
                                },
                                onDelete: {
                                    service.deleteShortcut(id: item.id)
                                }
                            )
                        }
                    }

                    HStack {
                        Button {
                            let nextSpace = min(16, (service.customShortcuts.filter { $0.actionType == .space }.count) + 1)
                            let newItem = InstantSpacesShortcutItem(
                                shortcut: GlobalShortcut(keyCode: Int64(kVK_ANSI_N), modifiers: [.option, .shift]),
                                actionType: .space,
                                targetSpace: nextSpace
                            )
                            service.addShortcut(newItem)
                        } label: {
                            Label("Add Shortcut", systemImage: "plus")
                        }

                        Spacer()

                        Button("Reset to Defaults") {
                            service.resetShortcutsToDefaults()
                        }
                    }
                    .controlSize(.small)
                }

                Text("Assign hotkeys to switch directly to spaces or execute custom shell commands and launch applications (e.g. open -n -a iTerm).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Menu Bar Indicator") {
                Toggle("Show current space badge in menu bar", isOn: $showMenuBarBadge)
                    .onChange(of: showMenuBarBadge) { _, _ in
                        InstantSpacesService.shared.syncWithPreferences()
                    }
                Text("Places an icon in the macOS menu bar showing the active space number as a cutout badge.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Live Status & Testing") {
                if let info = currentSpaceInfo {
                    HStack {
                        Text("Active Space:")
                        Spacer()
                        Text("Space \(info.currentIndex + 1) of \(info.spaceCount)")
                            .bold()
                    }
                    HStack {
                        Text("Display UUID:")
                        Spacer()
                        Text(info.displayID.isEmpty ? "Main" : String(info.displayID.prefix(12)) + "…")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Text("Space information unavailable or permissions missing.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 12) {
                    Button("Switch Left (←)") {
                        InstantSpacesService.shared.switchRight()
                        refreshSpaceInfo()
                    }
                    Button("Switch Right (→)") {
                        InstantSpacesService.shared.switchLeft()
                        refreshSpaceInfo()
                    }
                    Spacer()
                    Button("Refresh Info") {
                        refreshSpaceInfo()
                    }
                }
                .controlSize(.small)
            }
        }
        .formStyle(.grouped)
        .onAppear {
            refreshSpaceInfo()
        }
    }

    private func refreshSpaceInfo() {
        currentSpaceInfo = SpaceSwitcherSupport.getSpaceInfo()
    }
}

private struct InstantSpacesShortcutRow: View {
    let item: InstantSpacesShortcutItem
    @ObservedObject private var l10n = L10n.shared
    @State private var errorText: String?

    var onUpdate: (InstantSpacesShortcutItem) -> Void
    var onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                ShortcutRecorderButton(
                    shortcut: item.shortcut,
                    isEnabled: true,
                    waitingTitle: l10n.s.shortcutPressKeys,
                    emptyTitle: nil,
                    clearAction: nil,
                    notCapturedAction: { errorText = l10n.s.shortcutNotCaptured },
                    recordingChanged: { recording in
                        if recording { errorText = nil }
                    },
                    invalidAction: { errorText = l10n.s.shortcutInvalid },
                    captureAction: { newShortcut in
                        var updated = item
                        updated.shortcut = newShortcut
                        onUpdate(updated)
                    }
                )
                .frame(width: 110)

                Picker("", selection: Binding(
                    get: { item.actionType },
                    set: { newType in
                        var updated = item
                        updated.actionType = newType
                        onUpdate(updated)
                    }
                )) {
                    ForEach(InstantSpacesActionType.allCases) { type in
                        Text(type.title).tag(type)
                    }
                }
                .labelsHidden()
                .frame(width: 145)

                if item.actionType == .space {
                    Picker("", selection: Binding(
                        get: { item.targetSpace },
                        set: { newSpace in
                            var updated = item
                            updated.targetSpace = newSpace
                            onUpdate(updated)
                        }
                    )) {
                        ForEach(1...16, id: \.self) { num in
                            Text("Space \(num)").tag(num)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 95)
                } else {
                    TextField("e.g. open -n -a iTerm", text: Binding(
                        get: { item.command },
                        set: { newCmd in
                            var updated = item
                            updated.command = newCmd
                            onUpdate(updated)
                        }
                    ))
                    .textFieldStyle(.roundedBorder)
                }

                Spacer(minLength: 4)

                Button(role: .destructive, action: onDelete) {
                    Image(systemName: "trash")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Remove Shortcut")
            }

            if let errorText {
                Text(errorText)
                    .font(.caption2)
                    .foregroundStyle(.red)
            }
        }
        .padding(.vertical, 2)
    }
}

