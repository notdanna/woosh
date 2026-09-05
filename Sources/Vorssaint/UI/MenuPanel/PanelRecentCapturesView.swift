// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

struct PanelRecentCapturesView: View {
    var onClose: () -> Void

    var body: some View {
        RecentCapturesView(onClose: onClose)
        .onAppear {
            PanelInteractionState.shared.keepsPopoverOpen = true
        }
        .onDisappear { PanelInteractionState.shared.keepsPopoverOpen = false }
    }
}

/// The same history surface is used by the menu panel and by the floating
/// palette opened from editors and the Command Bar.
struct RecentCapturesView: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var history = RecentCaptureService.shared
    @State private var confirmingClear = false

    var onClose: (() -> Void)?

    private var text: RecentCaptureStrings {
        FeatureStrings.recentCaptures(l10n.language)
    }

    private var visibleEntries: [RecentCaptureEntry] {
        history.entries.filter { entry in
            entry.kind == .screenshot
                ? AppFeature.screenshot.isAvailable
                : AppFeature.screenRecorder.isAvailable
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            content
        }
        .onAppear { history.reload() }
        .confirmationDialog(text.clear,
                            isPresented: $confirmingClear,
                            titleVisibility: .visible) {
            Button(text.clear, role: .destructive) {
                history.clear()
            }
            Button(l10n.s.uninstallerCancel, role: .cancel) {}
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Label(text.title, systemImage: "clock.arrow.circlepath")
                .font(.system(size: 12, weight: .semibold))
            Spacer()
            PanelIconButton(
                icon: "trash",
                title: text.clear,
                help: text.clear,
                isDestructive: true,
                size: 24,
                iconSize: 11,
                disabled: visibleEntries.isEmpty
            ) {
                confirmingClear = true
            }
            if let onClose {
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

    @ViewBuilder
    private var content: some View {
        if visibleEntries.isEmpty {
            Text(text.empty)
                .font(.system(size: 10.5))
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .frame(height: 92)
                .panelCard()
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 7) {
                    ForEach(visibleEntries) { entry in
                        row(entry)
                    }
                }
            }
            .frame(maxHeight: 300)
        }
    }

    private func row(_ entry: RecentCaptureEntry) -> some View {
        HStack(spacing: 10) {
            preview(entry)
            VStack(alignment: .leading, spacing: 5) {
                Text(entry.kind == .screenshot ? text.screenshot : text.recording)
                    .font(.system(size: 11.5, weight: .semibold))
                if entry.kind == .recording, let name = entry.recordingURL?.lastPathComponent {
                    Text(name)
                        .font(.system(size: 9.5))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Text(entry.createdAt, style: .relative)
                    .font(.system(size: 9.5))
                    .foregroundStyle(.tertiary)
                HStack(spacing: 6) {
                    Button(entry.kind == .screenshot ? text.restore : text.open) {
                        history.open(entry)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.mini)
                    PanelIconButton(
                        icon: "trash",
                        title: text.remove,
                        help: text.remove,
                        isDestructive: true,
                        size: 20,
                        iconSize: 10
                    ) {
                        history.remove(entry)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .panelCard()
    }

    @ViewBuilder
    private func preview(_ entry: RecentCaptureEntry) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Color.black.opacity(0.13))
            if let image = history.thumbnail(for: entry) {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            } else {
                Image(systemName: entry.kind == .screenshot ? "photo" : "film")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(width: 104, height: 68)
        .overlay(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.1), lineWidth: 1)
        )
    }
}

/// Borderless palette content. Its compact fixed width keeps the same list
/// readable over either editor without covering the work area.
struct RecentCapturesWindowView: View {
    var onClose: () -> Void

    var body: some View {
        RecentCapturesView(onClose: onClose)
            .padding(14)
            .frame(width: 440)
            .panelGlassSurface(cornerRadius: 18)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

#if DEBUG
struct PanelRecentCapturesView_Previews: PreviewProvider {
    static var previews: some View {
        PanelRecentCapturesView(onClose: {})
            .padding()
            .frame(width: 320)
            .panelGlassSurface()
    }
}
#endif
