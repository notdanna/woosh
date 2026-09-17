// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import ApplicationServices
import Carbon.HIToolbox
import Combine
import Foundation

final class OneThingService: NSObject, ObservableObject, NSMenuDelegate {
    static let shared = OneThingService()

    @Published private(set) var isRunning = false
    @Published private(set) var activeTask: OneThingTask?
    @Published private(set) var history: [OneThingTask] = []

    private var statusItem: NSStatusItem?
    private let menu = NSMenu()

    private let toggleHotkey = QuickToolHotkey(id: 30)
    private let selectionHotkey = QuickToolHotkey(id: 31)
    private let completeHotkey = QuickToolHotkey(id: 32)

    private override init() {
        super.init()
        menu.delegate = self
        loadPersistedState()
    }

    // MARK: - Lifecycle

    func syncWithPreferences() {
        let defaults = UserDefaults.standard
        let wanted = AppFeature.oneThing.isAvailable
            && defaults.bool(forKey: DefaultsKey.oneThingEnabled)

        if wanted {
            start()
        } else {
            stop()
        }
    }

    private func start() {
        guard !isRunning else {
            syncShortcuts()
            updateStatusItem()
            return
        }

        isRunning = true
        loadPersistedState()
        ensureStatusItem()
        syncShortcuts()
        updateStatusItem()
    }

    private func stop() {
        guard isRunning else { return }
        isRunning = false
        toggleHotkey.unregister()
        selectionHotkey.unregister()
        completeHotkey.unregister()

        if let statusItem {
            statusItem.isVisible = false
            NSStatusBar.system.removeStatusItem(statusItem)
            self.statusItem = nil
        }
        OneThingPanelController.shared.close()
    }

    // MARK: - Shortcuts

    private func syncShortcuts() {
        let defaults = UserDefaults.standard

        let toggleRaw = defaults.string(forKey: DefaultsKey.oneThingShortcutToggle) ?? ""
        let toggleShortcut = GlobalShortcut(storageValue: toggleRaw) ?? .oneThingToggleDefault
        toggleHotkey.onPress = { [weak self] in
            self?.handleToggleShortcut()
        }
        toggleHotkey.sync(enabled: isRunning, shortcut: toggleShortcut)

        let selectionRaw = defaults.string(forKey: DefaultsKey.oneThingShortcutFromSelection) ?? ""
        let selectionShortcut = GlobalShortcut(storageValue: selectionRaw) ?? .oneThingFromSelectionDefault
        selectionHotkey.onPress = { [weak self] in
            self?.handleCaptureSelectionShortcut()
        }
        selectionHotkey.sync(enabled: isRunning, shortcut: selectionShortcut)

        let completeRaw = defaults.string(forKey: DefaultsKey.oneThingShortcutComplete) ?? ""
        let completeShortcut = GlobalShortcut(storageValue: completeRaw) ?? .oneThingCompleteDefault
        completeHotkey.onPress = { [weak self] in
            self?.handleQuickCompleteShortcut()
        }
        completeHotkey.sync(enabled: isRunning, shortcut: completeShortcut)
    }

    private func handleToggleShortcut() {
        OneThingPanelController.shared.toggle(statusItem: statusItem)
    }

    private func handleCaptureSelectionShortcut() {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let text = self?.readFrontmostSelection() ?? ""
            DispatchQueue.main.async {
                guard let self, !text.isEmpty else {
                    QuickToolHUD.show(icon: "exclamationmark.triangle", message: "No selection found")
                    return
                }
                self.setTask(text: text)
                QuickToolHUD.show(icon: "checklist", message: "One Thing updated")
            }
        }
    }

    private func handleQuickCompleteShortcut() {
        guard let task = activeTask, !task.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            QuickToolHUD.show(icon: "info.circle", message: "No active task")
            return
        }
        completeActiveTask()
    }

    // MARK: - Text Selection Reader (AX with Pasteboard fallback)

    private func readFrontmostSelection() -> String {
        if Permissions.shared.accessibility, AXIsProcessTrusted(),
           let front = NSWorkspace.shared.frontmostApplication,
           front.bundleIdentifier != Bundle.main.bundleIdentifier {
            let app = AXUIElementCreateApplication(front.processIdentifier)
            AXUIElementSetMessagingTimeout(app, 0.35)
            var focusedValue: CFTypeRef?
            if AXUIElementCopyAttributeValue(app, kAXFocusedUIElementAttribute as CFString, &focusedValue) == .success,
               let focused = focusedValue,
               CFGetTypeID(focused) == AXUIElementGetTypeID() {
                var textValue: CFTypeRef?
                if AXUIElementCopyAttributeValue((focused as! AXUIElement), kAXSelectedTextAttribute as CFString, &textValue) == .success,
                   let text = textValue as? String {
                    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty {
                        return trimmed
                    }
                }
            }
        }

        // Safe fallback to general pasteboard
        let pb = NSPasteboard.general
        if let clip = pb.string(forType: .string) {
            let trimmed = clip.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                return trimmed
            }
        }
        return ""
    }

    // MARK: - Status Item Management

    private func ensureStatusItem() {
        guard statusItem == nil else { return }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.menu = menu
        item.isVisible = false
        statusItem = item
    }

    func updateStatusItem() {
        guard isRunning else {
            statusItem?.isVisible = false
            return
        }
        ensureStatusItem()

        guard let item = statusItem else { return }
        guard let task = activeTask, !task.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            item.isVisible = false
            item.button?.title = ""
            item.button?.toolTip = nil
            return
        }

        let fullText = task.text.trimmingCharacters(in: .whitespacesAndNewlines)
        let maxChars = UserDefaults.standard.integer(forKey: DefaultsKey.oneThingMaxChars)
        let limit = maxChars > 0 ? maxChars : 40

        let displayTitle: String
        if fullText.count > limit {
            let index = fullText.index(fullText.startIndex, offsetBy: limit)
            displayTitle = String(fullText[..<index]) + "…"
        } else {
            displayTitle = fullText
        }

        item.button?.title = displayTitle
        item.button?.toolTip = fullText
        item.isVisible = true
    }

    // MARK: - NSMenuDelegate (Avoid infinite click loops)

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        if let task = activeTask, !task.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let completeItem = NSMenuItem(title: "Complete Task", action: #selector(completeTaskMenuAction), keyEquivalent: "")
            completeItem.target = self
            menu.addItem(completeItem)

            let editItem = NSMenuItem(title: "Edit Task…", action: #selector(editTaskMenuAction), keyEquivalent: "")
            editItem.target = self
            menu.addItem(editItem)

            menu.addItem(NSMenuItem.separator())

            let clearItem = NSMenuItem(title: "Clear Task", action: #selector(clearTaskMenuAction), keyEquivalent: "")
            clearItem.target = self
            menu.addItem(clearItem)

            menu.addItem(NSMenuItem.separator())
        } else {
            let newItem = NSMenuItem(title: "New Task…", action: #selector(editTaskMenuAction), keyEquivalent: "")
            newItem.target = self
            menu.addItem(newItem)

            menu.addItem(NSMenuItem.separator())
        }

        let settingsItem = NSMenuItem(title: "One Thing Settings…", action: #selector(openSettingsMenuAction), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)
    }

    @objc private func completeTaskMenuAction() {
        completeActiveTask()
    }

    @objc private func editTaskMenuAction() {
        OneThingPanelController.shared.show(statusItem: statusItem)
    }

    @objc private func clearTaskMenuAction() {
        clearActiveTask()
    }

    @objc private func openSettingsMenuAction() {
        SettingsRouter.shared.request(FeatureSettingsDestination(.oneThing))
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: - Task & History Operations

    func setTask(text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            clearActiveTask()
            return
        }
        let task = OneThingTask(text: trimmed)
        activeTask = task
        UserDefaults.standard.set(trimmed, forKey: DefaultsKey.oneThingActiveTask)
        updateStatusItem()
    }

    func completeActiveTask() {
        guard let task = activeTask, !task.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        var completed = task
        completed.completedAt = Date()
        history.insert(completed, at: 0)

        activeTask = nil
        UserDefaults.standard.set("", forKey: DefaultsKey.oneThingActiveTask)
        saveHistory()
        updateStatusItem()
        QuickToolHUD.show(icon: "checkmark.circle.fill", message: "Task completed")
    }

    func clearActiveTask() {
        activeTask = nil
        UserDefaults.standard.set("", forKey: DefaultsKey.oneThingActiveTask)
        updateStatusItem()
    }

    func clearHistory() {
        history.removeAll()
        saveHistory()
    }

    // MARK: - Persistence

    private func loadPersistedState() {
        let defaults = UserDefaults.standard
        let activeRaw = defaults.string(forKey: DefaultsKey.oneThingActiveTask) ?? ""
        let trimmed = activeRaw.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            activeTask = OneThingTask(text: trimmed)
        } else {
            activeTask = nil
        }

        if let data = defaults.data(forKey: DefaultsKey.oneThingHistory),
           let decoded = try? JSONDecoder().decode([OneThingTask].self, from: data) {
            history = decoded
        } else {
            history = []
        }
    }

    private func saveHistory() {
        if let encoded = try? JSONEncoder().encode(history) {
            UserDefaults.standard.set(encoded, forKey: DefaultsKey.oneThingHistory)
        }
    }
}
