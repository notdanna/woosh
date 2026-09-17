// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import ApplicationServices
import Carbon.HIToolbox
import CoreGraphics
import Darwin
import Foundation

enum InstantSpacesActionType: String, Codable, CaseIterable, Identifiable {
    case space
    case command

    var id: String { rawValue }
    var title: String {
        switch self {
        case .space: return "Desktop Space"
        case .command: return "Run Command / App"
        }
    }
}

struct InstantSpacesShortcutItem: Identifiable, Codable, Equatable, Hashable {
    var id: UUID
    var storageValue: String
    var actionType: InstantSpacesActionType
    var targetSpace: Int
    var command: String

    init(id: UUID = UUID(), shortcut: GlobalShortcut, actionType: InstantSpacesActionType, targetSpace: Int = 1, command: String = "") {
        self.id = id
        self.storageValue = shortcut.storageValue
        self.actionType = actionType
        self.targetSpace = targetSpace
        self.command = command
    }

    var shortcut: GlobalShortcut {
        get {
            GlobalShortcut(storageValue: storageValue) ?? GlobalShortcut(keyCode: Int64(kVK_ANSI_1), modifiers: [.option])
        }
        set {
            storageValue = newValue.storageValue
        }
    }
}

struct InstantSpacesHotkey: Identifiable {
    let id: UUID
    let label: String
    let flags: CGEventFlags
    let keyCode: CGKeyCode
    let targetSpaceIndex: UInt32?
    let command: String?
}

enum InstantSpacesConfigManager {
    static var primaryConfigPath: String {
        let home = NSHomeDirectory()
        let swapkPath = "\(home)/.config/swapk/swapk.conf"
        if FileManager.default.fileExists(atPath: swapkPath) {
            return swapkPath
        }
        let issPath = "\(home)/.config/iss/iss.conf"
        if FileManager.default.fileExists(atPath: issPath) {
            return issPath
        }
        return swapkPath
    }

    static func defaultShortcuts() -> [InstantSpacesShortcutItem] {
        let digits: [(Int, Int64)] = [
            (1, Int64(kVK_ANSI_1)),
            (2, Int64(kVK_ANSI_2)),
            (3, Int64(kVK_ANSI_3)),
            (4, Int64(kVK_ANSI_4)),
            (5, Int64(kVK_ANSI_5)),
            (6, Int64(kVK_ANSI_6)),
        ]
        return digits.map { spaceNum, keyCode in
            InstantSpacesShortcutItem(
                shortcut: GlobalShortcut(keyCode: keyCode, modifiers: [.option]),
                actionType: .space,
                targetSpace: spaceNum
            )
        }
    }

    static func loadShortcuts() -> [InstantSpacesShortcutItem] {
        if let data = UserDefaults.standard.data(forKey: DefaultsKey.instantSpacesShortcuts),
           let items = try? JSONDecoder().decode([InstantSpacesShortcutItem].self, from: data) {
            return items
        }

        // First run: migrate from ~/.config/swapk/swapk.conf if it exists
        let migrated = migrateFromConfigFile()
        let result = migrated.isEmpty ? defaultShortcuts() : migrated
        saveShortcuts(result)
        return result
    }

    static func saveShortcuts(_ items: [InstantSpacesShortcutItem]) {
        if let data = try? JSONEncoder().encode(items) {
            UserDefaults.standard.set(data, forKey: DefaultsKey.instantSpacesShortcuts)
        }
        syncToConfigFile(items)
    }

    private static func migrateFromConfigFile() -> [InstantSpacesShortcutItem] {
        let path = primaryConfigPath
        guard FileManager.default.fileExists(atPath: path),
              let content = try? String(contentsOfFile: path, encoding: .utf8) else {
            return []
        }

        var items: [InstantSpacesShortcutItem] = []
        let lines = content.components(separatedBy: .newlines)

        for rawLine in lines {
            var line = rawLine
            if let commentIndex = line.firstIndex(of: "#") {
                line = String(line[..<commentIndex])
            }
            line = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.isEmpty { continue }

            let parts = line.split(separator: "=", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            guard parts.count == 2 else { continue }
            let key = parts[0]
            let value = parts[1]

            switch key.lowercased() {
            case "swipe", "swipe_direction", "space_numbering", "overlay_detection", "gesture_speed":
                break
            default:
                if let (flags, code) = parseHotkeySpec(key) {
                    var modifiers: GlobalShortcutModifiers = []
                    if flags.contains(.maskCommand) { modifiers.insert(.command) }
                    if flags.contains(.maskAlternate) { modifiers.insert(.option) }
                    if flags.contains(.maskControl) { modifiers.insert(.control) }
                    if flags.contains(.maskShift) { modifiers.insert(.shift) }

                    let shortcut = GlobalShortcut(keyCode: Int64(code), modifiers: modifiers)
                    let isDigits = !value.isEmpty && value.allSatisfy { $0.isNumber }
                    if isDigits, let spaceNum = Int(value), spaceNum >= 1 {
                        items.append(InstantSpacesShortcutItem(
                            shortcut: shortcut,
                            actionType: .space,
                            targetSpace: spaceNum
                        ))
                    } else {
                        items.append(InstantSpacesShortcutItem(
                            shortcut: shortcut,
                            actionType: .command,
                            command: value
                        ))
                    }
                }
            }
        }

        return items
    }

    private static func syncToConfigFile(_ items: [InstantSpacesShortcutItem]) {
        let path = primaryConfigPath
        let dir = (path as NSString).deletingLastPathComponent
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)

        var lines: [String] = [
            "# Auto-generated by Woosh (Instant Spaces)",
            "swipe = on",
            "swipe_direction = \(UserDefaults.standard.bool(forKey: DefaultsKey.instantSpacesSwipeDirectionReversed) ? "reversed" : "normal")",
            "space_numbering = \(UserDefaults.standard.bool(forKey: DefaultsKey.instantSpacesSpaceNumberingReversed) ? "reversed" : "normal")",
            "gesture_speed = \(Int(UserDefaults.standard.double(forKey: DefaultsKey.instantSpacesGestureSpeed)))",
            "overlay_detection = \(UserDefaults.standard.bool(forKey: DefaultsKey.instantSpacesOverlayDetectionEnabled) ? "on" : "off")",
            ""
        ]

        for item in items {
            let keySpec = formatHotkeySpec(item.shortcut)
            if item.actionType == .space {
                lines.append("\(keySpec) = \(item.targetSpace)")
            } else {
                lines.append("\(keySpec) = \(item.command)")
            }
        }

        let output = lines.joined(separator: "\n") + "\n"
        try? output.write(toFile: path, atomically: true, encoding: .utf8)
    }

    private static func formatHotkeySpec(_ shortcut: GlobalShortcut) -> String {
        var parts: [String] = []
        if shortcut.modifiers.contains(.control) { parts.append("ctrl") }
        if shortcut.modifiers.contains(.option) { parts.append("opt") }
        if shortcut.modifiers.contains(.shift) { parts.append("shift") }
        if shortcut.modifiers.contains(.command) { parts.append("cmd") }

        let keyName = keycodeNameMap[CGKeyCode(shortcut.keyCode)] ?? "key_\(shortcut.keyCode)"
        parts.append(keyName)
        return parts.joined(separator: "+")
    }

    private static let keycodeMap: [String: CGKeyCode] = [
        "0": 29, "1": 18, "2": 19, "3": 20, "4": 21,
        "5": 23, "6": 22, "7": 26, "8": 28, "9": 25,
        "a": 0,  "b": 11, "c": 8,  "d": 2,  "e": 14, "f": 3,
        "g": 5,  "h": 4,  "i": 34, "j": 38, "k": 40, "l": 37,
        "m": 46, "n": 45, "o": 31, "p": 35, "q": 12, "r": 15,
        "s": 1,  "t": 17, "u": 32, "v": 9,  "w": 13, "x": 7,
        "y": 16, "z": 6,
        "return": 36, "enter": 36,
        "space": 49, "tab": 48, "esc": 53, "escape": 53,
        "backspace": 51, "delete": 51, "forwarddelete": 117,
        "left": 123, "right": 124, "down": 125, "up": 126,
        "f1": 122, "f2": 120, "f3": 99, "f4": 118, "f5": 96, "f6": 97,
        "f7": 98, "f8": 100, "f9": 101, "f10": 109, "f11": 103, "f12": 111,
        "minus": 27, "-": 27, "equal": 24, "=": 24,
        "leftbracket": 33, "[": 33, "rightbracket": 30, "]": 30,
        "semicolon": 41, ";": 41, "quote": 39, "'": 39,
        "comma": 43, ",": 43, "period": 47, ".": 47, "slash": 44, "/": 44,
        "backslash": 42, "\\": 42, "grave": 50, "`": 50
    ]

    private static let keycodeNameMap: [CGKeyCode: String] = {
        var map: [CGKeyCode: String] = [:]
        for (name, code) in keycodeMap {
            if map[code] == nil || name.count == 1 {
                map[code] = name
            }
        }
        map[36] = "return"
        map[49] = "space"
        map[48] = "tab"
        map[53] = "esc"
        return map
    }()

    static func parseHotkeySpec(_ rawKey: String) -> (flags: CGEventFlags, keyCode: CGKeyCode)? {
        let parts = rawKey.lowercased().split(separator: "+").map { $0.trimmingCharacters(in: .whitespaces) }
        guard parts.count >= 2, let keyStr = parts.last else { return nil }

        var flags: CGEventFlags = []
        for mod in parts.dropLast() {
            switch mod {
            case "cmd", "command":
                flags.insert(.maskCommand)
            case "ctrl", "control":
                flags.insert(.maskControl)
            case "opt", "alt", "option":
                flags.insert(.maskAlternate)
            case "shift":
                flags.insert(.maskShift)
            default:
                break
            }
        }

        guard let code = keycodeMap[keyStr] else { return nil }
        return (flags, code)
    }

    static func convertToHotkeys(_ items: [InstantSpacesShortcutItem]) -> [InstantSpacesHotkey] {
        return items.map { item in
            let shortcut = item.shortcut
            let flags = shortcut.modifiers.cgFlags
            let keyCode = CGKeyCode(shortcut.keyCode)
            let label = shortcut.displayString

            if item.actionType == .space {
                return InstantSpacesHotkey(
                    id: item.id,
                    label: label,
                    flags: flags,
                    keyCode: keyCode,
                    targetSpaceIndex: UInt32(max(0, item.targetSpace - 1)),
                    command: nil
                )
            } else {
                return InstantSpacesHotkey(
                    id: item.id,
                    label: label,
                    flags: flags,
                    keyCode: keyCode,
                    targetSpaceIndex: nil,
                    command: item.command
                )
            }
        }
    }
}

