// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

struct PanelWindowLayoutView: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var permissions = Permissions.shared
    @ObservedObject private var service = WindowLayoutService.shared
    @AppStorage(DefaultsKey.windowLayoutShortcutsEnabled) private var shortcutsEnabled = true
    @AppStorage(DefaultsKey.windowEdgeSnapEnabled) private var edgeSnapEnabled = false
    @AppStorage(DefaultsKey.windowGestureEnabled) private var gestureEnabled = false
    @AppStorage(DefaultsKey.windowGestureModifiers) private var gestureModifiers = WindowGestureSupport.defaultModifierStorageValue
    @AppStorage(DefaultsKey.windowLayoutHiddenActions) private var hiddenActionsRaw = ""
    @State private var editingActions = false
    @State private var systemTilingEnabled = WindowEdgeSnapSupport.isSystemTilingEnabled

    var onClose: () -> Void

    private var text: WindowLayoutFeatureStrings {
        FeatureStrings.windowLayout(l10n.language)
    }

    private let columns = [
        GridItem(.adaptive(minimum: 44, maximum: 72), spacing: 6)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            intro
            actionGroup(title: text.halves, actions: [.leftHalf, .rightHalf, .topHalf, .bottomHalf])
            actionGroup(title: text.thirds, actions: [.leftThird, .centerThird, .rightThird, .leftTwoThirds, .rightTwoThirds])
            actionGroup(title: text.sixths, actions: [
                .topLeftSixth, .topCenterSixth, .topRightSixth,
                .bottomLeftSixth, .bottomCenterSixth, .bottomRightSixth,
            ])
            actionGroup(title: text.corners, actions: [.topLeft, .topRight, .bottomLeft, .bottomRight])
            actionGroup(title: text.other, actions: [
                .maximize, .marginMaximize, .fullScreen, .center, .previousDisplay, .nextDisplay, .restore,
            ])
            if let message = resultMessage {
                Label(message, systemImage: resultSymbol)
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(resultColor)
                    .panelCard()
            }
        }
        .onAppear {
            PanelInteractionState.shared.keepsPopoverOpen = true
            refreshSystemTilingState()
        }
        .onReceive(NotificationCenter.default.publisher(
            for: NSApplication.didBecomeActiveNotification)) { _ in
            refreshSystemTilingState()
        }
        .onDisappear { PanelInteractionState.shared.keepsPopoverOpen = false }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Label(text.title, systemImage: "rectangle.3.group")
                .font(.system(size: 12, weight: .semibold))
            Spacer()
            PanelIconButton(
                icon: editingActions ? "checkmark" : "slider.horizontal.3",
                title: l10n.s.menuSettings,
                help: l10n.s.menuSettings,
                isActive: editingActions,
                size: 24,
                iconSize: 11
            ) {
                withAnimation(.easeOut(duration: 0.15)) { editingActions.toggle() }
            }

            PanelIconButton(
                icon: "xmark",
                title: l10n.s.menuClose,
                help: l10n.s.uninstallerCancel,
                size: 24,
                iconSize: 11
            ) {
                onClose()
            }
        }
    }

    private var hiddenActions: Set<WindowLayoutAction> {
        WindowLayoutAction.hiddenActions(from: hiddenActionsRaw)
    }

    private func toggleHidden(_ action: WindowLayoutAction) {
        var hidden = hiddenActions
        if !hidden.insert(action).inserted { hidden.remove(action) }
        hiddenActionsRaw = WindowLayoutAction.hiddenActionsStorageValue(hidden)
    }

    private var intro: some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle(text.edgeSnapEnable, isOn: $edgeSnapEnabled)
                .toggleStyle(.checkbox)
                .controlSize(.small)
                .font(.system(size: 10.5, weight: .medium))
                .onChange(of: edgeSnapEnabled) { _, _ in
                    WindowLayoutService.shared.syncWithPreferences()
                }
            Text(text.edgeSnapCaption)
                .font(.system(size: 9.5))
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
            if systemTilingEnabled {
                Label(text.edgeSnapSystemConflict, systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 9.5))
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
                if edgeSnapEnabled {
                    Text(text.edgeSnapWaitingForSystem)
                        .font(.system(size: 9.5))
                        .foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Button(text.edgeSnapOpenSystemSettings) {
                    NSWorkspace.shared.open(WindowEdgeSnapSupport.desktopAndDockSettingsURL)
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)
            }
            Divider()
            Text(text.caption)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Toggle(text.shortcuts, isOn: $shortcutsEnabled)
                .toggleStyle(.checkbox)
                .controlSize(.small)
                .font(.system(size: 10.5, weight: .medium))
                .onChange(of: shortcutsEnabled) { _, _ in
                    WindowLayoutService.shared.syncWithPreferences()
                }
            if shortcutsEnabled {
                Text(text.shortcutsCaption)
                    .font(.system(size: 9.5))
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Divider()
            Toggle(text.gestureEnable, isOn: $gestureEnabled)
                .toggleStyle(.checkbox)
                .controlSize(.small)
                .font(.system(size: 10.5, weight: .medium))
                .onChange(of: gestureEnabled) { _, _ in
                    WindowLayoutService.shared.syncWithPreferences()
                }
            if gestureEnabled {
                WindowGestureModifierPicker(storageValue: $gestureModifiers,
                                            title: text.gestureModifiers,
                                            compact: true)
                    .onChange(of: gestureModifiers) { _, _ in
                        WindowLayoutService.shared.syncWithPreferences()
                    }
                WindowGestureHints(modifierStorage: gestureModifiers,
                                   moveText: text.gestureMove,
                                   resizeText: text.gestureResize,
                                   compact: true)
                Text(text.gestureResizeHint)
                    .font(.system(size: 9.5))
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !permissions.accessibility {
                Button {
                    Permissions.shared.requestAccessibility()
                    Permissions.shared.openAccessibilitySettings()
                } label: {
                    Label(text.missingPermission, systemImage: "hand.raised.fill")
                        .font(.system(size: 10, weight: .semibold))
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)
            }
        }
        .panelCard()
    }

    private func refreshSystemTilingState() {
        systemTilingEnabled = WindowEdgeSnapSupport.isSystemTilingEnabled
        WindowLayoutService.shared.syncWithPreferences()
    }

    @ViewBuilder
    private func actionGroup(title groupTitle: String, actions: [WindowLayoutAction]) -> some View {
        let hidden = hiddenActions
        let shown = editingActions ? actions : actions.filter { !hidden.contains($0) }
        if !shown.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text(groupTitle.uppercased())
                    .font(.system(size: 9.5, weight: .bold))
                    .foregroundStyle(.tertiary)
                LazyVGrid(columns: columns, alignment: .leading, spacing: 6) {
                    ForEach(shown) { action in
                        Button {
                            if editingActions {
                                withAnimation(.easeOut(duration: 0.15)) { toggleHidden(action) }
                            } else {
                                service.apply(action)
                            }
                        } label: {
                            ZStack(alignment: .topTrailing) {
                                Image(systemName: editingActions
                                        ? (hidden.contains(action) ? "eye.slash" : "eye")
                                        : action.symbolName)
                                    .font(.system(size: 13.5, weight: .medium))
                                    .frame(maxWidth: .infinity, minHeight: 32)
                                    .opacity(editingActions && hidden.contains(action) ? 0.35 : 1.0)

                                if shortcutsEnabled, action.supportsShortcut, action.savedShortcut != nil {
                                    Circle()
                                        .fill(Color.accentColor.opacity(0.85))
                                        .frame(width: 4, height: 4)
                                        .padding(4)
                                }
                            }
                        }
                        .buttonStyle(PanelGlassButtonStyle(cornerRadius: PanelRadius.control))
                        .help(actionHelpText(for: action))
                        .accessibilityLabel(title(for: action))
                        .disabled(!permissions.accessibility && !editingActions)
                    }
                }
            }
            .panelCard()
        }
    }

    private func actionHelpText(for action: WindowLayoutAction) -> String {
        let name = title(for: action)
        if shortcutsEnabled, action.supportsShortcut, let shortcut = action.savedShortcut {
            return "\(name) (\(shortcut.displayString))"
        }
        return name
    }

    private func title(for action: WindowLayoutAction) -> String {
        action.title(text)
    }

    private var resultMessage: String? {
        switch service.lastResult {
        case .success(let restored): return restored ? text.restored : text.done
        case .failure(.missingAccessibility): return text.missingPermission
        case .failure(.noWindow): return text.noWindow
        case .failure(.noRestore): return text.noRestore
        case .failure(.failed): return text.failed
        case nil: return nil
        }
    }

    private var resultColor: Color {
        switch service.lastResult {
        case .success: return .green
        case .failure: return .orange
        case nil: return .secondary
        }
    }

    private var resultSymbol: String {
        switch service.lastResult {
        case .success: return "checkmark.circle.fill"
        case .failure: return "exclamationmark.triangle.fill"
        case nil: return "info.circle"
        }
    }
}

#if DEBUG
struct PanelWindowLayoutView_Previews: PreviewProvider {
    static var previews: some View {
        PanelWindowLayoutView(onClose: {})
            .padding()
            .frame(width: 320)
            .panelGlassSurface()
    }
}
#endif
