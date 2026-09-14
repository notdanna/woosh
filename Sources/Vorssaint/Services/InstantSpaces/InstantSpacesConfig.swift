// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import ApplicationServices
import CoreGraphics
import Darwin
import Foundation

struct InstantSpacesHotkey: Identifiable {
    let id = UUID()
    let label: String
    let flags: CGEventFlags
    let keyCode: CGKeyCode
    let targetSpaceIndex: UInt32?
    let command: String?
}

enum InstantSpacesConfigParser {
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

    struct LoadedConfig {
        var swipeEnabled: Bool = true
        var swipeDirectionReversed: Bool = false
        var spaceNumberingReversed: Bool = false
        var overlayDetectionEnabled: Bool = false
        var gestureSpeed: Double = 2000.0
        var bindings: [InstantSpacesHotkey] = []
    }

    static func loadConfig() -> LoadedConfig {
        var config = LoadedConfig()

        // Default bindings (opt+1..6) if no file or no bindings specified
        let defaultDigits: [(Character, CGKeyCode, UInt32)] = [
            ("1", 18, 0), ("2", 19, 1), ("3", 20, 2),
            ("4", 21, 3), ("5", 23, 4), ("6", 22, 5)
        ]
        var defaultsBindings: [InstantSpacesHotkey] = []
        for (char, code, idx) in defaultDigits {
            defaultsBindings.append(InstantSpacesHotkey(
                label: "opt+\(char)",
                flags: .maskAlternate,
                keyCode: code,
                targetSpaceIndex: idx,
                command: nil
            ))
        }

        let path = primaryConfigPath
        guard FileManager.default.fileExists(atPath: path),
              let content = try? String(contentsOfFile: path, encoding: .utf8) else {
            config.bindings = defaultsBindings
            return config
        }

        var loadedBindings: [InstantSpacesHotkey] = []
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
            case "swipe":
                config.swipeEnabled = (value.lowercased() == "on" || value.lowercased() == "true" || value == "1")
            case "swipe_direction":
                config.swipeDirectionReversed = (value.lowercased() == "reversed")
            case "space_numbering":
                config.spaceNumberingReversed = (value.lowercased() == "reversed")
            case "overlay_detection":
                config.overlayDetectionEnabled = (value.lowercased() == "on" || value.lowercased() == "true" || value == "1")
            case "gesture_speed":
                if let speed = Double(value) {
                    config.gestureSpeed = speed
                }
            default:
                if let (flags, code) = parseHotkeySpec(key) {
                    let isAllDigits = !value.isEmpty && value.allSatisfy { $0.isNumber }
                    if isAllDigits, let spaceNum = Int(value), spaceNum >= 1 {
                        loadedBindings.append(InstantSpacesHotkey(
                            label: key,
                            flags: flags,
                            keyCode: code,
                            targetSpaceIndex: UInt32(spaceNum - 1),
                            command: nil
                        ))
                    } else {
                        loadedBindings.append(InstantSpacesHotkey(
                            label: key,
                            flags: flags,
                            keyCode: code,
                            targetSpaceIndex: nil,
                            command: value
                        ))
                    }
                }
            }
        }

        config.bindings = loadedBindings.isEmpty ? defaultsBindings : loadedBindings
        return config
    }

    static func ensureConfigFileExists() -> String {
        let path = primaryConfigPath
        if !FileManager.default.fileExists(atPath: path) {
            let dir = (path as NSString).deletingLastPathComponent
            try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
            let defaultTemplate = """
            # ~/.config/swapk/swapk.conf
            swipe = on
            swipe_direction = reversed
            space_numbering = normal
            gesture_speed = 2000
            overlay_detection = off

            opt+1 = 1
            opt+2 = 2
            opt+3 = 3
            opt+4 = 4
            opt+5 = 5
            opt+6 = 6

            # Custom app launcher shortcuts:
            opt+return = open -n -a iTerm
            """
            try? defaultTemplate.write(toFile: path, atomically: true, encoding: .utf8)
        }
        return path
    }

    static func openConfigFile() {
        let path = ensureConfigFileExists()
        NSWorkspace.shared.open(URL(fileURLWithPath: path))
    }
}

