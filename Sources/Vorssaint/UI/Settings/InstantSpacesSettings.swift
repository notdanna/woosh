// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

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

                if !service.activeBindings.isEmpty {
                    Text("Configured Shortcuts:")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    ForEach(service.activeBindings) { binding in
                        HStack {
                            Text(binding.label)
                                .font(.system(.body, design: .monospaced))
                                .bold()
                            Spacer()
                            if let cmd = binding.command {
                                Text(cmd)
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundStyle(.secondary)
                            } else if let sp = binding.targetSpaceIndex {
                                Text("Space \(sp + 1)")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                HStack {
                    Button("Open Configuration File…") {
                        InstantSpacesConfigParser.openConfigFile()
                    }
                    Button("Reload Config") {
                        InstantSpacesService.shared.reloadConfig()
                    }
                }
                .controlSize(.small)

                Text("Custom space shortcuts and shell command triggers (e.g. opt+return = open -n -a iTerm) are configured in ~/.config/swapk/swapk.conf.")
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
