// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import SwiftUI

struct ClipboardQuickPanelView: View {
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var history = ClipboardHistoryService.shared
    @FocusState private var searchFocused: Bool
    @State private var hoveredEntryID: UUID?
    @State private var previewEntryID: UUID?
    @State private var previewIsEditing = false

    private static let timeFormatter: DateFormatter = {
        let df = DateFormatter()
        df.timeStyle = .short
        return df
    }()

    private var text: ClipboardFeatureStrings {
        FeatureStrings.clipboard(l10n.language)
    }

    private var filtered: [ClipboardHistoryEntry] {
        history.filteredQuickEntries
    }

    private var previewEntry: ClipboardHistoryEntry? {
        ClipboardHistorySelection.previewEntry(preferredID: previewEntryID,
                                               visibleEntries: filtered,
                                               selectedEntry: history.selectedQuickEntry)
    }

    private var canReorderEntries: Bool {
        history.quickQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var panelSize: CGSize {
        history.quickPreviewPresented
            ? ClipboardHistoryService.quickPanelPreviewSize
            : ClipboardHistoryService.quickPanelCompactSize
    }

    var body: some View {
        VStack(spacing: 0) {
            spotlightSearchBar
            Divider()
                .opacity(0.4)
            HStack(spacing: 0) {
                content
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                if history.quickPreviewPresented {
                    Divider()
                        .opacity(0.4)
                    ClipboardEntryPreviewSidebar(text: text,
                                                 entry: previewEntry,
                                                 isEditing: $previewIsEditing,
                                                 onClose: { history.setQuickPreviewPresented(false) })
                        .frame(width: 280)
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
        }
        .frame(width: panelSize.width, height: panelSize.height, alignment: .topLeading)
        .animation(.spring(response: 0.32, dampingFraction: 0.88), value: history.quickPreviewPresented)
        .background(
            RoundedRectangle(cornerRadius: PanelRadius.window, style: .continuous)
                .fill(colorScheme == .dark ? Color.black.opacity(0.38) : Color.clear)
        )
        .glassSurface(in: RoundedRectangle(cornerRadius: PanelRadius.window, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: PanelRadius.window, style: .continuous))
        .ignoresSafeArea(.container, edges: .top)
        .onAppear {
            hoveredEntryID = nil
            previewEntryID = history.selectedQuickEntryID
            searchFocused = true
        }
        .onDisappear {
            hoveredEntryID = nil
            previewEntryID = nil
            previewIsEditing = false
        }
        .onChange(of: history.quickSelectionIndex) { _, _ in
            previewEntryID = history.selectedQuickEntryID
        }
        .onChange(of: history.quickQuery) { _, _ in
            previewEntryID = history.selectedQuickEntryID
        }
        .onChange(of: history.quickWindowPresentationID) { _, _ in
            hoveredEntryID = nil
            previewEntryID = history.selectedQuickEntryID
            searchFocused = true
        }
        .onChange(of: previewEntry?.id) { _, newID in
            if newID == nil {
                history.setQuickPreviewPresented(false)
            }
        }
    }

    // MARK: - Spotlight Search Bar

    private var spotlightSearchBar: some View {
        HStack(spacing: 12) {
            Image(systemName: "doc.on.clipboard")
                .font(.system(size: 17, weight: .regular))
                .foregroundStyle(.primary.opacity(0.75))

            TextField(text.search.isEmpty ? "Spotlight Search" : text.search, text: $history.quickQuery)
                .textFieldStyle(.plain)
                .font(.system(size: 16, weight: .regular))
                .focused($searchFocused)

            if !history.quickQuery.isEmpty {
                Button {
                    history.quickQuery = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .help(l10n.s.menuClose)
            }

            HStack(spacing: 6) {
                Button {
                    history.toggleQuickPreview()
                } label: {
                    Image(systemName: "sidebar.right")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(history.quickPreviewPresented ? Color.accentColor : Color.secondary)
                        .frame(width: 24, height: 24)
                        .background(
                            Circle()
                                .fill(history.quickPreviewPresented ? Color.accentColor.opacity(0.15) : Color.clear)
                        )
                }
                .buttonStyle(.plain)
                .help(text.previewLabel)
                .disabled(previewEntry == nil)

                Menu {
                    Button(text.clearRecent, role: .destructive) {
                        history.clearRecent()
                    }
                    .disabled(history.recentEntries.isEmpty)

                    Divider()

                    Button(l10n.s.menuClose) {
                        history.hideHistoryWindow()
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(width: 24, height: 24)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    // MARK: - Content List

    @ViewBuilder
    private var content: some View {
        if filtered.isEmpty {
            emptyState(history.entries.isEmpty ? text.empty : text.noResults)
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 1) {
                        ForEach(Array(filtered.enumerated()), id: \.element.id) { index, entry in
                            entryRow(entry,
                                     shortcutIndex: index < 9 ? index : nil,
                                     isSelected: history.quickSelectionIsVisible
                                        && history.selectedQuickEntryID == entry.id,
                                     isBatchSelected: history.isQuickBatchSelected(entry),
                                     isHovered: hoveredEntryID == entry.id)
                                .id(entry.id)
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                }
                .onChange(of: history.quickSelectionIndex) { _, _ in
                    scrollSelectedEntry(with: proxy)
                }
                .onChange(of: history.quickSelectionIsVisible) { _, _ in
                    scrollSelectedEntry(with: proxy)
                }
                .onChange(of: history.quickQuery) { _, _ in
                    scrollSelectedEntry(with: proxy)
                }
            }
        }
    }

    private func emptyState(_ message: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: "doc.on.clipboard")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(.tertiary)
            Text(message)
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Minimalist Entry Row

    private func entryRow(_ entry: ClipboardHistoryEntry,
                          shortcutIndex: Int?,
                          isSelected: Bool,
                          isBatchSelected: Bool,
                          isHovered: Bool) -> some View {
        HStack(alignment: .center, spacing: 12) {
            ClipboardItemIconView(entry: entry)

            VStack(alignment: .leading, spacing: 3) {
                Text(rowTitle(entry))
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Text(rowSubtitle(entry))
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            entryTrailing(entry, shortcutIndex: shortcutIndex, isHovered: isHovered, isSelected: isSelected)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .frame(minHeight: 48)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(rowBackground(isSelected: isSelected,
                                    isBatchSelected: isBatchSelected,
                                    isHovered: isHovered))
        )
        .overlay(
            isBatchSelected
                ? RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Color.accentColor.opacity(0.4), lineWidth: 1)
                : nil
        )
        .contentShape(Rectangle())
        .contextMenu { entryActions(entry) }
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.1)) {
                hoveredEntryID = hovering ? entry.id : (hoveredEntryID == entry.id ? nil : hoveredEntryID)
            }
            if hovering, !previewIsEditing {
                previewEntryID = entry.id
            }
        }
        .onTapGesture { activate(entry) }
    }

    private func rowTitle(_ entry: ClipboardHistoryEntry) -> String {
        switch entry.kind {
        case .text:
            return entry.preview
        case .image:
            if let imgName = entry.imageFile {
                return imgName
            }
            return entry.imageDimensionsLabel.isEmpty ? "Image" : "Image (\(entry.imageDimensionsLabel))"
        case .files:
            return fileTitle(entry)
        }
    }

    private func rowSubtitle(_ entry: ClipboardHistoryEntry) -> String {
        let time = Self.timeFormatter.string(from: entry.copiedAt)
        switch entry.kind {
        case .text:
            return "Text · Copied \(time)"
        case .image:
            let ext = (entry.imageFile as NSString?)?.pathExtension.uppercased()
            let typeLabel = (ext?.isEmpty == false ? "\(ext!) image" : "Image")
            return "\(typeLabel) · Copied \(time)"
        case .files:
            let count = entry.filePaths.count
            let label = count == 1 ? "1 file" : "\(count) files"
            return "\(label) · Copied \(time)"
        }
    }

    @ViewBuilder
    private func entryTrailing(_ entry: ClipboardHistoryEntry,
                               shortcutIndex: Int?,
                               isHovered: Bool,
                               isSelected: Bool) -> some View {
        HStack(spacing: 6) {
            if let shortcutIndex, !isHovered {
                Text("⌘\(shortcutIndex + 1)")
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(.tertiary)
            }

            Button {
                history.copyOnlyQuickEntry(entry)
            } label: {
                Image(systemName: "doc.on.doc")
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(.primary.opacity(0.85))
                    .frame(width: 24, height: 24)
                    .background(
                        Circle()
                            .fill(Color.primary.opacity(colorScheme == .dark ? 0.12 : 0.08))
                    )
            }
            .buttonStyle(.plain)
            .help(text.copy)
        }
    }

    @ViewBuilder
    private func entryActions(_ entry: ClipboardHistoryEntry) -> some View {
        Button(l10n.s.menuPaste) {
            history.copyQuickEntry(entry)
        }
        Button(text.copy) {
            history.copyOnlyQuickEntry(entry)
        }
        Divider()
        Button(entry.isPinned ? text.unpin : text.pin) {
            history.togglePin(entry)
        }
        Button(text.moveUp) {
            history.move(entry, .up)
        }
        .disabled(!canReorderEntries || !history.canMove(entry, .up))
        Button(text.moveDown) {
            history.move(entry, .down)
        }
        .disabled(!canReorderEntries || !history.canMove(entry, .down))
        Divider()
        Button(text.delete, role: .destructive) {
            history.remove(entry)
        }
    }

    private func activate(_ entry: ClipboardHistoryEntry) {
        let modifiers = NSEvent.modifierFlags.intersection([.command, .shift])
        if modifiers.contains(.command) {
            history.toggleQuickBatchSelection(entry)
        } else if modifiers.contains(.shift) {
            history.extendQuickBatchSelection(to: entry)
        } else if history.isQuickBatchSelected(entry) {
            history.copySelectedQuickEntry()
        } else {
            history.copyQuickEntry(entry)
        }
    }

    private func fileTitle(_ entry: ClipboardHistoryEntry) -> String {
        if entry.filePaths.count == 1 {
            return entry.fileNames.first ?? entry.preview
        }
        return String(format: text.fileCountFormat, entry.filePaths.count)
    }

    private func rowBackground(isSelected: Bool,
                               isBatchSelected: Bool,
                               isHovered: Bool) -> Color {
        if isBatchSelected {
            return Color.accentColor.opacity(isHovered ? 0.22 : 0.16)
        }
        if isSelected {
            return Color.primary.opacity(colorScheme == .dark ? 0.15 : 0.09)
        }
        if isHovered {
            return Color.primary.opacity(colorScheme == .dark ? 0.08 : 0.045)
        }
        return .clear
    }

    private func scrollSelectedEntry(with proxy: ScrollViewProxy) {
        guard history.quickSelectionIsVisible, let id = history.selectedQuickEntryID else { return }
        withAnimation(.easeOut(duration: 0.12)) {
            proxy.scrollTo(id, anchor: .center)
        }
    }
}

// MARK: - Leading Icon View with App Badge

private struct ClipboardItemIconView: View {
    let entry: ClipboardHistoryEntry
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            baseIcon
                .frame(width: 30, height: 32)

            if let appIcon = appIcon {
                Image(nsImage: appIcon)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 13, height: 13)
                    .clipShape(Circle())
                    .overlay(Circle().strokeBorder(Color.white.opacity(0.85), lineWidth: 0.7))
                    .shadow(color: .black.opacity(0.35), radius: 1, y: 0.5)
                    .offset(x: 3, y: 3)
            } else if entry.isPinned {
                Image(systemName: "pin.fill")
                    .font(.system(size: 6.5, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 13, height: 13)
                    .background(Circle().fill(Color.accentColor))
                    .overlay(Circle().strokeBorder(Color.white.opacity(0.85), lineWidth: 0.7))
                    .shadow(color: .black.opacity(0.35), radius: 1, y: 0.5)
                    .offset(x: 3, y: 3)
            }
        }
        .frame(width: 34, height: 34)
    }

    @ViewBuilder
    private var baseIcon: some View {
        switch entry.kind {
        case .text:
            Image(systemName: "doc.text.fill")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .foregroundStyle(Color.secondary.opacity(0.8))
                .frame(width: 24, height: 28)
        case .image:
            if let name = entry.imageFile,
               let thumb = ClipboardImageStore.thumbnail(named: name) {
                Image(nsImage: thumb)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 28, height: 28)
                    .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.15), lineWidth: 0.5)
                    )
            } else {
                Image(systemName: "photo.fill")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .foregroundStyle(Color.secondary.opacity(0.8))
                    .frame(width: 26, height: 26)
            }
        case .files:
            if let fileIcon = fileIcon {
                Image(nsImage: fileIcon)
                    .resizable()
                    .frame(width: 26, height: 26)
            } else {
                Image(systemName: "folder.fill")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .foregroundStyle(Color.secondary.opacity(0.8))
                    .frame(width: 26, height: 26)
            }
        }
    }

    private var appIcon: NSImage? {
        ClipboardAppIconStore.icon(for: entry.appBundleID)
    }

    private var fileIcon: NSImage? {
        guard entry.kind == .files,
              let path = entry.filePaths.first(where: { FileManager.default.fileExists(atPath: $0) })
        else { return nil }
        return NSWorkspace.shared.icon(forFile: path)
    }
}

#if DEBUG
struct ClipboardQuickPanelView_Previews: PreviewProvider {
    static var previews: some View {
        ClipboardQuickPanelView()
    }
}
#endif
