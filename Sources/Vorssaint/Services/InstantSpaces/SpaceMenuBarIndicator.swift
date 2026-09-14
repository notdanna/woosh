// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Foundation

final class SpaceMenuBarIndicator {
    static let shared = SpaceMenuBarIndicator()

    private var statusItem: NSStatusItem?
    private var iconCache: [UInt32: NSImage] = [:]
    private var workspaceObserver: NSObjectProtocol?
    private var currentSpace: UInt32 = 1
    private var totalSpaces: UInt32 = 1

    private init() {}

    func syncWithPreferences(isEnabled: Bool) {
        let wanted = isEnabled && UserDefaults.standard.bool(forKey: DefaultsKey.instantSpacesShowMenuBarBadge)
        if wanted {
            start()
        } else {
            stop()
        }
    }

    func updateSpace(index: UInt32, total: UInt32) {
        currentSpace = index + 1
        totalSpaces = total
        refreshIcon()
    }

    private func start() {
        guard statusItem == nil else {
            refresh()
            return
        }

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.toolTip = "Instant Spaces"
        item.button?.target = self
        item.button?.action = #selector(statusItemClicked)
        item.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        statusItem = item

        workspaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.refresh()
        }

        refresh()
    }

    private func stop() {
        if let workspaceObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(workspaceObserver)
            self.workspaceObserver = nil
        }
        if let statusItem {
            NSStatusBar.system.removeStatusItem(statusItem)
            self.statusItem = nil
        }
        iconCache.removeAll()
    }

    func refresh() {
        if let info = SpaceSwitcherSupport.getSpaceInfo(useCursorDisplay: false) {
            currentSpace = info.currentIndex + 1
            totalSpaces = info.spaceCount
        }
        refreshIcon()
    }

    private func refreshIcon() {
        guard let button = statusItem?.button else { return }
        button.image = icon(for: currentSpace)
        button.toolTip = "Space \(currentSpace) of \(totalSpaces)"
    }

    private func icon(for number: UInt32) -> NSImage {
        if let cached = iconCache[number] {
            return cached
        }

        let width: CGFloat = number >= 10 ? 26.0 : 18.0
        let height: CGFloat = 16.0
        let radius: CGFloat = 3.5
        let margin: CGFloat = 2.0

        let image = NSImage(size: NSSize(width: width, height: height), flipped: false) { dstRect in
            let rect = NSRect(x: 0, y: 0, width: width, height: height)
            let path = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
            NSColor.white.set()
            path.fill()

            let label = "\(number)"
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.monospacedDigitSystemFont(ofSize: 11.0, weight: .bold),
                .foregroundColor: NSColor.black
            ]
            let size = (label as NSString).size(withAttributes: attrs)
            let origin = NSPoint(
                x: (width - size.width) / 2.0,
                y: margin + (height - 2 * margin - size.height) / 2.0
            )

            NSGraphicsContext.current?.saveGraphicsState()
            NSGraphicsContext.current?.compositingOperation = .clear
            (label as NSString).draw(in: NSRect(origin: origin, size: size), withAttributes: attrs)
            NSGraphicsContext.current?.restoreGraphicsState()

            return true
        }

        image.isTemplate = true
        iconCache[number] = image
        return image
    }

    @objc private func statusItemClicked() {
        guard let button = statusItem?.button else { return }
        let menu = NSMenu()

        let headerItem = NSMenuItem(title: "Space \(currentSpace) of \(totalSpaces)", action: nil, keyEquivalent: "")
        headerItem.isEnabled = false
        menu.addItem(headerItem)

        menu.addItem(NSMenuItem.separator())

        let settingsItem = NSMenuItem(
            title: "Instant Spaces Settings…",
            action: #selector(openSettings),
            keyEquivalent: ","
        )
        settingsItem.target = self
        menu.addItem(settingsItem)

        button.menu = menu
        button.performClick(nil)
        button.menu = nil
    }

    @objc private func openSettings() {
        SettingsRouter.shared.request(FeatureSettingsDestination(.instantSpaces))
        NSApp.activate(ignoringOtherApps: true)
    }
}
