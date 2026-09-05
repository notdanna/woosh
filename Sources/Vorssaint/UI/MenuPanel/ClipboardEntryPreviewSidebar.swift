// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

/// On-demand inspector for the selected clipboard entry. It keeps the full
/// content selectable and editable without permanently taking space from the
/// history list.
struct ClipboardEntryPreviewSidebar: View {
    @ObservedObject private var l10n = L10n.shared
    var text: ClipboardFeatureStrings
    var entry: ClipboardHistoryEntry?
    @Binding var isEditing: Bool
    var onClose: () -> Void
    @State private var draft = ""
    @State private var editingEntryID: UUID?
    @FocusState private var editorFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            sidebarHeader
            Divider()
            if let entry {
                if editingEntryID == entry.id {
                    textEditor(entry)
                } else {
                    contentScrollView(entry)
                }
                Divider()
                sidebarFooter(entry)
            } else {
                emptyState
            }
        }
        .onChange(of: entry?.id) { _, newID in
            if editingEntryID != nil, editingEntryID != newID {
                cancelEditing()
            }
        }
        .onDisappear { cancelEditing() }
    }

    private var sidebarHeader: some View {
        HStack(spacing: 8) {
            Label(text.previewLabel, systemImage: "doc.text.magnifyingglass")
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(.secondary)
            Spacer()
            PanelIconButton(
                icon: "xmark",
                title: l10n.s.menuClose,
                help: l10n.s.menuClose,
                size: 22,
                iconSize: 10,
                cornerRadius: 11
            ) {
                onClose()
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private func contentScrollView(_ entry: ClipboardHistoryEntry) -> some View {
        ScrollView {
            previewContent(entry)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .frame(maxHeight: .infinity)
    }

    private func textEditor(_ entry: ClipboardHistoryEntry) -> some View {
        TextEditor(text: $draft)
            .font(.system(size: 12))
            .lineSpacing(2)
            .scrollContentBackground(.hidden)
            .padding(8)
            .background(
                RoundedRectangle(cornerRadius: PanelRadius.control, style: .continuous)
                    .fill(Color.primary.opacity(0.045))
            )
            .overlay(
                RoundedRectangle(cornerRadius: PanelRadius.control, style: .continuous)
                    .strokeBorder(Color.accentColor.opacity(0.45), lineWidth: 1)
            )
            .padding(12)
            .focused($editorFocused)
            .onExitCommand { cancelEditing() }
            .accessibilityLabel(text.edit)
    }

    @ViewBuilder
    private func previewContent(_ entry: ClipboardHistoryEntry) -> some View {
        switch entry.kind {
        case .text:
            // Standard text selection lets someone copy only the fragment
            // they need; the window monitor leaves ⌘C with this view.
            Text(entry.text)
                .font(.system(size: 12))
                .textSelection(.enabled)
                .lineSpacing(2)
                .frame(maxWidth: .infinity, alignment: .topLeading)
        case .image:
            imagePreview(entry)
        case .files:
            Text(entry.filePaths.joined(separator: "\n"))
                .font(.system(size: 11, design: .monospaced))
                .textSelection(.enabled)
                .lineSpacing(3)
                .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }

    @ViewBuilder
    private func imagePreview(_ entry: ClipboardHistoryEntry) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if let name = entry.imageFile,
               let image = ClipboardImageStore.thumbnail(named: name) {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: PanelRadius.control, style: .continuous))
            }
            Text("\(text.imageEntryLabel) · \(entry.imageDimensionsLabel)")
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private var emptyState: some View {
        Image(systemName: "doc.on.clipboard")
            .font(.system(size: 22, weight: .light))
            .foregroundStyle(.tertiary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func sidebarFooter(_ entry: ClipboardHistoryEntry) -> some View {
        HStack(spacing: 6) {
            if entry.isPinned {
                Image(systemName: "pin.fill")
                    .font(.system(size: 9.5))
                    .foregroundStyle(Color.accentColor)
            }
            Text(entry.copiedAt, style: .time)
                .font(.system(size: 9.5))
                .foregroundStyle(.tertiary)
            Spacer()
            if editingEntryID == entry.id {
                PanelIconButton(
                    icon: "xmark",
                    title: text.cancel,
                    help: text.cancel,
                    size: 22,
                    iconSize: 10,
                    cornerRadius: 11
                ) {
                    cancelEditing()
                }

                PanelIconButton(
                    icon: "checkmark",
                    title: text.save,
                    help: text.save,
                    isProminent: true,
                    size: 22,
                    iconSize: 10,
                    cornerRadius: 11,
                    disabled: !ClipboardHistoryEditing.canSave(original: entry.text, draft: draft)
                ) {
                    saveEditing(entry)
                }
            } else {
                if entry.kind == .text {
                    PanelIconButton(
                        icon: "pencil",
                        title: text.edit,
                        help: text.edit,
                        size: 22,
                        iconSize: 10,
                        cornerRadius: 11
                    ) {
                        beginEditing(entry)
                    }
                }
                PanelIconButton(
                    icon: "doc.on.doc",
                    title: text.copy,
                    help: text.copy,
                    isProminent: true,
                    size: 22,
                    iconSize: 10,
                    cornerRadius: 11
                ) {
                    ClipboardHistoryService.shared.copyOnlyQuickEntry(entry)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
    }

    private func beginEditing(_ entry: ClipboardHistoryEntry) {
        draft = entry.text
        editingEntryID = entry.id
        isEditing = true
        DispatchQueue.main.async { editorFocused = true }
    }

    private func cancelEditing() {
        editorFocused = false
        editingEntryID = nil
        draft = ""
        isEditing = false
    }

    private func saveEditing(_ entry: ClipboardHistoryEntry) {
        guard ClipboardHistoryService.shared.updateText(entry, to: draft) else { return }
        cancelEditing()
    }
}

#if DEBUG
struct ClipboardEntryPreviewSidebar_Previews: PreviewProvider {
    static var previews: some View {
        ClipboardEntryPreviewSidebar(
            text: FeatureStrings.clipboard(.enUS),
            entry: ClipboardHistoryEntry(text: "Sample preview item", kind: .text),
            isEditing: .constant(false),
            onClose: {}
        )
        .frame(width: 280, height: 400)
        .panelGlassSurface()
    }
}
#endif
