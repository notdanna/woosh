// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import ApplicationServices
import CoreGraphics
import Foundation

enum SpaceDirection {
    case left
    case right
}

struct SpaceInfo {
    let currentIndex: UInt32
    let spaceCount: UInt32
    let displayID: String
}

enum SpaceSwitcherSupport {
    typealias ConnectionID = UInt32
    typealias SpaceID = UInt64

    private static func symbol(_ name: String) -> UnsafeMutableRawPointer? {
        dlsym(UnsafeMutableRawPointer(bitPattern: -2) /* RTLD_DEFAULT */, name)
    }

    private static let connection: ConnectionID = {
        typealias Function = @convention(c) () -> ConnectionID
        guard let s = symbol("CGSMainConnectionID") else { return 0 }
        return unsafeBitCast(s, to: Function.self)()
    }()

    private typealias GetActiveSpaceFunction = @convention(c) (ConnectionID) -> SpaceID
    private static let getActiveSpaceFn: GetActiveSpaceFunction? = {
        guard let s = symbol("CGSGetActiveSpace") else { return nil }
        return unsafeBitCast(s, to: GetActiveSpaceFunction.self)
    }()

    private typealias CopyDisplaySpacesFunction = @convention(c) (ConnectionID, CFString?) -> Unmanaged<CFArray>?
    private static let copyManagedDisplaySpacesFn: CopyDisplaySpacesFunction? = {
        guard let s = symbol("CGSCopyManagedDisplaySpaces") else { return nil }
        return unsafeBitCast(s, to: CopyDisplaySpacesFunction.self)
    }()

    private typealias CopyActiveMenuBarDisplayIdentifierFunction = @convention(c) (ConnectionID) -> Unmanaged<CFString>?
    private static let copyActiveMenuBarDisplayIdentifierFn: CopyActiveMenuBarDisplayIdentifierFunction? = {
        guard let s = symbol("CGSCopyActiveMenuBarDisplayIdentifier") else { return nil }
        return unsafeBitCast(s, to: CopyActiveMenuBarDisplayIdentifierFunction.self)
    }()

    private typealias ManagedDisplayGetCurrentSpaceFunction = @convention(c) (ConnectionID, CFString) -> SpaceID
    private static let managedDisplayGetCurrentSpaceFn: ManagedDisplayGetCurrentSpaceFunction? = {
        guard let s = symbol("SLSManagedDisplayGetCurrentSpace") else { return nil }
        return unsafeBitCast(s, to: ManagedDisplayGetCurrentSpaceFunction.self)
    }()

    private typealias CursorVisibilityFunction = @convention(c) (ConnectionID) -> Int32
    private static let cgsShowCursorFn: CursorVisibilityFunction? = {
        guard let s = symbol("CGSShowCursor") ?? symbol("SLSShowCursor") else { return nil }
        return unsafeBitCast(s, to: CursorVisibilityFunction.self)
    }()

    private static let cgsUnobscureCursorFn: CursorVisibilityFunction? = {
        guard let s = symbol("CGSUnobscureCursor") ?? symbol("SLSUnobscureCursor") else { return nil }
        return unsafeBitCast(s, to: CursorVisibilityFunction.self)
    }()

    static func ensureCursorVisible() {
        if connection != 0 {
            _ = cgsUnobscureCursorFn?(connection)
            _ = cgsShowCursorFn?(connection)
        }
        CGAssociateMouseAndMouseCursorPosition(boolean_t(1))
    }

    static func getActiveMenuBarDisplayIdentifier() -> String? {
        guard connection != 0, let copyFn = copyActiveMenuBarDisplayIdentifierFn else { return nil }
        return copyFn(connection)?.takeRetainedValue() as String?
    }

    static func getCursorDisplayIdentifier() -> String? {
        let tempEvent = CGEvent(source: nil)
        let location = tempEvent?.location ?? .zero
        var displayID: CGDirectDisplayID = 0
        var count: UInt32 = 0
        if CGGetDisplaysWithPoint(location, 1, &displayID, &count) == .success, count > 0 {
            if let uuid = CGDisplayCreateUUIDFromDisplayID(displayID)?.takeRetainedValue() {
                return CFUUIDCreateString(nil, uuid) as String?
            }
        }
        return nil
    }

    static func getSpaceInfo(useCursorDisplay: Bool = true) -> SpaceInfo? {
        guard connection != 0, let copySpacesFn = copyManagedDisplaySpacesFn else { return nil }

        let targetDisplayID = useCursorDisplay ? getCursorDisplayIdentifier() : getActiveMenuBarDisplayIdentifier()

        var activeSpaceID: SpaceID = 0
        if let targetDisplayID, let slsFn = managedDisplayGetCurrentSpaceFn {
            activeSpaceID = slsFn(connection, targetDisplayID as CFString)
        }
        if activeSpaceID == 0, let cgsActiveFn = getActiveSpaceFn {
            activeSpaceID = cgsActiveFn(connection)
        }

        let displaysArray = (targetDisplayID != nil ? copySpacesFn(connection, targetDisplayID! as CFString) : nil)
            ?? copySpacesFn(connection, nil)

        guard let displays = displaysArray?.takeRetainedValue() as? [[String: Any]], !displays.isEmpty else {
            return nil
        }

        var matchedDisplay: [String: Any]?
        if let targetDisplayID {
            matchedDisplay = displays.first { ($0["Display Identifier"] as? String) == targetDisplayID }
        }
        let displayDict = matchedDisplay ?? displays.first!
        let displayIdentifier = (displayDict["Display Identifier"] as? String) ?? ""

        guard let spacesList = displayDict["Spaces"] as? [[String: Any]] else {
            return nil
        }

        var totalSpaces: UInt32 = 0
        var activeIndex: UInt32 = 0
        var foundActive = false

        for spaceDict in spacesList {
            var candidateID: SpaceID = 0
            if let managedNum = spaceDict["ManagedSpaceID"] as? NSNumber {
                candidateID = managedNum.uint64Value
            }
            if candidateID == 0, let id64Num = spaceDict["id64"] as? NSNumber {
                candidateID = id64Num.uint64Value
            }

            if candidateID != 0 {
                if !foundActive && activeSpaceID != 0 && candidateID == activeSpaceID {
                    activeIndex = totalSpaces
                    foundActive = true
                }
                totalSpaces += 1
            }
        }

        guard totalSpaces > 0 else { return nil }

        return SpaceInfo(
            currentIndex: foundActive ? activeIndex : 0,
            spaceCount: totalSpaces,
            displayID: displayIdentifier
        )
    }

    /// Returns true if Mission Control or App Exposé is active (inspecting Dock overlay windows)
    static func isOverlayActive() -> Bool {
        guard let windowList = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]] else {
            return false
        }

        var layer18Count = 0
        var layer20Count = 0

        for info in windowList {
            guard let owner = info[kCGWindowOwnerName as String] as? String, owner == "Dock" else {
                continue
            }
            if let layerNum = info[kCGWindowLayer as String] as? NSNumber {
                let layer = layerNum.intValue
                if layer == 18 {
                    layer18Count += 1
                } else if layer == 20 {
                    layer20Count += 1
                }
            }
        }

        // App Exposé or Mission Control: layer 18 present and at least one layer 20
        return layer18Count > 0 && layer20Count > 0
    }
}
