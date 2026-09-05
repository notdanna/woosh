// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

struct PanelClipboardView: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var history = ClipboardHistoryService.shared
    @AppStorage(DefaultsKey.clipboardHistoryEnabled) private var enabled = false
    @AppStorage(DefaultsKey.clipboardHistoryShortcutEnabled) private var shortcutEnabled = true
    @State private var query = ""
    @State private var copiedID: UUID?

    var onClose: () -> Void

    private var text: ClipboardFeatureStrings {
        FeatureStrings.clipboard(l10n.language)
    }

    private var filteredEntries: [ClipboardHistoryEntry] {
        history.filteredEntries(matching: query)
    }

    private var canReorderEntries: Bool {
        query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            controls
            entriesList
        }
        .onAppear { PanelInteractionState.shared.keepsPopoverOpen = true }
        .onDisappear { PanelInteractionState.shared.keepsPopoverOpen = false }
    }

    @Environment(\.colorScheme) private var colorScheme

    private var header: some View {
        HStack(spacing: 8) {
            Label(text.title, systemImage: "doc.on.clipboard")
                .font(.system(size: 12, weight: .semibold))
            Spacer()
            PanelIconButton(
                icon: "xmark",
                title: l10n.s.uninstallerCancel,
                help: l10n.s.uninstallerCancel,
                size: 22,
                iconSize: 10,
                cornerRadius: 11
            ) {
                onClose()
            }
        }
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 7) {
            Toggle(text.enable, isOn: $enabled)
                .toggleStyle(.checkbox)
                .font(.system(size: 11.5, weight: .medium))
                .onChange(of: enabled) { _, _ in
                    ClipboardHistoryService.shared.syncWithPreferences()
                }
            Text(enabled ? text.caption : text.disabled)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if enabled, shortcutEnabled {
                Text("\(text.shortcut): \(shortcut.displayString)")
                    .font(.system(size: 9.5, weight: .medium, design: .rounded))
                    .foregroundStyle(.tertiary)
            }
            HStack(spacing: 6) {
                HStack(spacing: 5) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                    TextField(text.search, text: $query)
                        .textFieldStyle(.plain)
                        .font(.system(size: 11))
                        .disabled(history.entries.isEmpty)
                    if !query.isEmpty {
                        Button {
                            query = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 10))
                                .foregroundStyle(.tertiary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(
                    Capsule(style: .continuous)
                        .fill(PanelSurface.controlFill(for: colorScheme))
                )
                .overlay(
                    Capsule(style: .continuous)
                        .strokeBorder(PanelSurface.border(for: colorScheme), lineWidth: 0.7)
                )

                PanelIconButton(
                    icon: "trash",
                    title: text.clearRecent,
                    help: text.clearRecent,
                    isDestructive: true,
                    size: 24,
                    iconSize: 11,
                    cornerRadius: 12,
                    disabled: history.recentEntries.isEmpty
                ) {
                    history.clearRecent()
                    copiedID = nil
                }

                PanelIconButton(
                    icon: "arrow.up.forward.app",
                    title: text.shortcut,
                    help: text.shortcut,
                    size: 24,
                    iconSize: 11,
                    cornerRadius: 12
                ) {
                    history.showHistoryWindow()
                }
            }
        }
        .panelCard()
    }

    @ViewBuilder
    private var entriesList: some View {
        if history.entries.isEmpty {
            emptyState(text.empty)
        } else if filteredEntries.isEmpty {
            emptyState(text.noResults)
        } else {
            ScrollView {
                // Lazy: a large history would otherwise build every row, and
                // decode every image thumbnail, each time the panel opens.
                LazyVStack(alignment: .leading, spacing: 7) {
                    ForEach(filteredEntries) { entry in
                        entryRow(entry)
                    }
                }
            }
            .frame(maxHeight: 260)
        }
    }

    private func emptyState(_ message: String) -> some View {
        Text(message)
            .font(.system(size: 10.5))
            .foregroundStyle(.tertiary)
            .frame(maxWidth: .infinity)
            .frame(height: 72)
            .panelCard()
    }

    private var shortcut: GlobalShortcut {
        GlobalShortcut.saved(for: DefaultsKey.clipboardHistoryShortcut,
                             fallback: .clipboardDefault)
    }

    @ViewBuilder
    private func entryPreview(_ entry: ClipboardHistoryEntry) -> some View {
        switch entry.kind {
        case .text:
            Text(entry.preview)
                .font(.system(size: 10.5))
                .lineLimit(3)
                .truncationMode(.tail)
                .textSelection(.enabled)
        case .image:
            HStack(alignment: .center, spacing: 7) {
                if let name = entry.imageFile,
                   let thumbnail = ClipboardImageStore.thumbnail(named: name) {
                    Image(nsImage: thumbnail)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: 110, maxHeight: 40)
                        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                }
                Text("\(text.imageEntryLabel) · \(entry.imageDimensionsLabel)")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
        case .files:
            HStack(alignment: .center, spacing: 7) {
                Image(systemName: "folder")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                Text(entry.filePaths.count == 1
                     ? (entry.fileNames.first ?? entry.preview)
                     : String(format: text.fileCountFormat, entry.filePaths.count))
                    .font(.system(size: 10.5))
                    .lineLimit(2)
                    .truncationMode(.middle)
            }
            .help(entry.filePaths.joined(separator: "\n"))
        }
    }

    private func entryRow(_ entry: ClipboardHistoryEntry) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            if entry.isPinned {
                Label(text.pinned, systemImage: "pin.fill")
                    .font(.system(size: 9.5, weight: .bold))
                    .foregroundStyle(Color.accentColor)
            }
            entryPreview(entry)
            HStack(spacing: 5) {
                PanelIconButton(
                    icon: "arrow.up",
                    title: text.moveUp,
                    help: text.moveUp,
                    size: 22,
                    iconSize: 9.5,
                    cornerRadius: 11,
                    disabled: !canReorderEntries || !history.canMove(entry, .up)
                ) {
                    history.move(entry, .up)
                }

                PanelIconButton(
                    icon: "arrow.down",
                    title: text.moveDown,
                    help: text.moveDown,
                    size: 22,
                    iconSize: 9.5,
                    cornerRadius: 11,
                    disabled: !canReorderEntries || !history.canMove(entry, .down)
                ) {
                    history.move(entry, .down)
                }

                PanelIconButton(
                    icon: entry.isPinned ? "pin.slash.fill" : "pin",
                    title: entry.isPinned ? text.unpin : text.pin,
                    help: entry.isPinned ? text.unpin : text.pin,
                    isActive: entry.isPinned,
                    size: 22,
                    iconSize: 9.5,
                    cornerRadius: 11
                ) {
                    history.togglePin(entry)
                }

                PanelIconButton(
                    icon: copiedID == entry.id ? "checkmark" : "doc.on.doc",
                    title: copiedID == entry.id ? text.copied : text.copy,
                    help: copiedID == entry.id ? text.copied : text.copy,
                    isProminent: true,
                    size: 22,
                    iconSize: 9.5,
                    cornerRadius: 11
                ) {
                    history.copy(entry)
                    copiedID = entry.id
                }

                PanelIconButton(
                    icon: "trash",
                    title: text.delete,
                    help: text.delete,
                    isDestructive: true,
                    size: 22,
                    iconSize: 9.5,
                    cornerRadius: 11
                ) {
                    history.remove(entry)
                }

                Spacer()
                Text(entry.copiedAt, style: .time)
                    .font(.system(size: 9.5))
                    .foregroundStyle(.tertiary)
            }
        }
        .panelCard()
    }
}

#if DEBUG
struct PanelClipboardView_Previews: PreviewProvider {
    static var previews: some View {
        PanelClipboardView(onClose: {})
            .padding()
            .frame(width: 320)
            .panelGlassSurface()
    }
}
#endif
