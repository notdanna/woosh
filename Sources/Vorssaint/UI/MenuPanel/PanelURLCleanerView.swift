// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import SwiftUI

struct PanelURLCleanerView: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var cleaner = URLCleanerService.shared
    @AppStorage(DefaultsKey.urlCleanerEnabled) private var autoClean = false
    @State private var input = ""
    @State private var output = ""
    @State private var message: String?

    var onClose: () -> Void
    private var canClearInput: Bool { !input.isEmpty || !output.isEmpty || message != nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            autoCleanToggle
            manualCleaner
        }
        .onAppear { PanelInteractionState.shared.keepsPopoverOpen = true }
        .onDisappear { PanelInteractionState.shared.keepsPopoverOpen = false }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Label(l10n.s.urlCleanerName, systemImage: "link")
                .font(.system(size: 12, weight: .semibold))
            Spacer()
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

    private var autoCleanToggle: some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle(l10n.s.urlCleanerEnable, isOn: $autoClean)
                .toggleStyle(.checkbox)
                .font(.system(size: 11.5, weight: .medium))
                .onChange(of: autoClean) { _, _ in
                    URLCleanerService.shared.syncWithPreferences()
                }
            Text(l10n.s.urlCleanerEnableCaption)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if autoClean, cleaner.isRunning {
                Label(l10n.s.urlCleanerActiveNow, systemImage: "checkmark.circle.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(.green)
            }
        }
        .panelCard()
    }

    private var manualCleaner: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(l10n.s.urlCleanerManualTitle)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.tertiary)
            HStack(spacing: 6) {
                TextField(l10n.s.urlCleanerInputPlaceholder, text: $input)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 11))
                PanelIconButton(
                    icon: "xmark",
                    title: l10n.s.urlCleanerClearButton,
                    help: l10n.s.urlCleanerClearButton,
                    size: 22,
                    iconSize: 10,
                    disabled: !canClearInput,
                    action: clearInput
                )
            }
            HStack(spacing: 7) {
                Button(l10n.s.urlCleanerPasteButton) {
                    paste()
                }
                Button(l10n.s.urlCleanerCleanButton) {
                    clean()
                }
                .buttonStyle(.borderedProminent)
                .disabled(input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                Spacer()
                Button(l10n.s.urlCleanerCopyButton) {
                    copy()
                }
                .disabled(output.isEmpty)
            }
            .controlSize(.small)

            resultView
        }
        .panelCard()
    }

    @ViewBuilder
    private var resultView: some View {
        if output.isEmpty {
            Text(message ?? l10n.s.urlCleanerOutputPlaceholder)
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
                .lineLimit(2)
        } else {
            VStack(alignment: .leading, spacing: 5) {
                Text(output)
                    .font(.system(size: 10.5, design: .monospaced))
                    .lineLimit(3)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
                if let message {
                    Text(message)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func paste() {
        input = NSPasteboard.general.string(forType: .string) ?? ""
        clean()
    }

    private func clean() {
        guard let cleaned = cleaner.clean(input) else {
            output = ""
            message = l10n.s.urlCleanerNoURL
            return
        }
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        output = cleaned
        message = cleaned == trimmed ? l10n.s.urlCleanerNoChange : l10n.s.urlCleanerCleaned
    }

    private func copy() {
        guard !output.isEmpty else { return }
        cleaner.copy(output)
        message = l10n.s.urlCleanerCopied
    }

    private func clearInput() {
        input = ""
        output = ""
        message = nil
    }
}

#if DEBUG
struct PanelURLCleanerView_Previews: PreviewProvider {
    static var previews: some View {
        PanelURLCleanerView(onClose: {})
            .padding()
            .frame(width: 320)
            .panelGlassSurface()
    }
}
#endif
