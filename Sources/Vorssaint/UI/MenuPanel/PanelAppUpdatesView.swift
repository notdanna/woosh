// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import SwiftUI

struct PanelAppUpdatesView: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var updates = AppUpdatesService.shared

    var onClose: () -> Void

    private var text: AppUpdateStrings { FeatureStrings.appUpdates(l10n.language) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            AppUpdatesListView(compact: true)
                .panelCard()
        }
        .onAppear {
            PanelInteractionState.shared.keepsPopoverOpen = true
            // The panel is the fast way in, so it arrives with an answer
            // instead of an empty list waiting for a click.
            updates.checkIfNeeded()
        }
        .onDisappear { PanelInteractionState.shared.keepsPopoverOpen = false }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Label(text.pageTitle, systemImage: "arrow.down.app")
                .font(.system(size: 12, weight: .semibold))
            Spacer()
            PanelIconButton(
                icon: "gearshape",
                title: l10n.s.menuSettings,
                help: l10n.s.menuSettings,
                size: 24,
                iconSize: 11
            ) {
                SettingsRouter.shared.page = .appUpdates
                appDelegate()?.openSettingsWindow()
            }
            PanelIconButton(
                icon: "xmark",
                title: l10n.s.menuClose,
                help: l10n.s.uninstallerCancel,
                size: 24,
                iconSize: 11,
                action: onClose
            )
        }
    }
}

#if DEBUG
struct PanelAppUpdatesView_Previews: PreviewProvider {
    static var previews: some View {
        PanelAppUpdatesView(onClose: {})
            .padding()
            .frame(width: 320)
            .panelGlassSurface()
    }
}
#endif
