// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import ApplicationServices
import CoreGraphics
import Darwin
import Foundation

final class InstantSpacesService: ObservableObject {
    static let shared = InstantSpacesService()

    @Published private(set) var isRunning = false
    @Published private(set) var activeBindings: [InstantSpacesHotkey] = []
    private(set) var loadedConfig = InstantSpacesConfigParser.LoadedConfig()

    private static let kCGSEventTypeField = CGEventField(rawValue: 55)!
    private static let kCGEventGestureHIDType = CGEventField(rawValue: 110)!
    private static let kCGEventGestureSwipeMotion = CGEventField(rawValue: 123)!
    private static let kCGEventGestureSwipeProgress = CGEventField(rawValue: 124)!
    private static let kCGEventGestureSwipePositionX = CGEventField(rawValue: 125)!
    private static let kCGEventGestureSwipeVelocityX = CGEventField(rawValue: 129)!
    private static let kCGEventGestureSwipeVelocityY = CGEventField(rawValue: 130)!
    private static let kCGEventGesturePhase = CGEventField(rawValue: 132)!
    private static let kCGEventGesturePhaseAlias = CGEventField(rawValue: 134)!
    private static let kCGEventGestureZoomDeltaY = CGEventField(rawValue: 138)!
    private static let kCGEventSourceUnixProcessIDAlias = CGEventField(rawValue: 169)!

    private static let kCGSEventGesture: Int64 = 29
    private static let kCGSEventDockControl: Int64 = 30
    private static let kIOHIDEventTypeDockSwipe: Int64 = 23
    private static let kCGGestureMotionHorizontal: Int64 = 1

    private enum CGSGesturePhase: Int64 {
        case began = 1
        case changed = 2
        case ended = 4
        case cancelled = 8
    }

    private var gestureTap: CFMachPort?
    private var gestureSource: CFRunLoopSource?

    private var hotkeyTap: CFMachPort?
    private var hotkeySource: CFRunLoopSource?

    private var spaceObserver: NSObjectProtocol?

    private var swipeTracking = false
    private var swipeFired = false

    private init() {}

    func reloadConfig() {
        loadedConfig = InstantSpacesConfigParser.loadConfig()
        activeBindings = loadedConfig.bindings
    }

    func syncWithPreferences() {
        let defaults = UserDefaults.standard
        let wanted = AppFeature.instantSpaces.isAvailable
            && defaults.bool(forKey: DefaultsKey.instantSpacesEnabled)

        if wanted, Permissions.shared.accessibility {
            start()
        } else {
            stop()
        }

        SpaceMenuBarIndicator.shared.syncWithPreferences(isEnabled: isRunning)
    }

    private func start() {
        reloadConfig()
        guard !isRunning else {
            SpaceMenuBarIndicator.shared.syncWithPreferences(isEnabled: true)
            return
        }

        installGestureTap()
        installHotkeyTap()

        spaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            SpacePredictionCache.shared.reset()
            SpaceMenuBarIndicator.shared.refresh()
            self?.restoreCursorVisibility()
        }

        isRunning = true
        SpaceMenuBarIndicator.shared.syncWithPreferences(isEnabled: true)
    }

    private func stop() {
        removeGestureTap()
        removeHotkeyTap()

        if let spaceObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(spaceObserver)
            self.spaceObserver = nil
        }

        swipeTracking = false
        swipeFired = false
        SpacePredictionCache.shared.reset()
        isRunning = false
        SpaceMenuBarIndicator.shared.syncWithPreferences(isEnabled: false)
    }

    // MARK: - Gesture Tap

    private func installGestureTap() {
        guard gestureTap == nil else { return }

        let mask = (1 << Self.kCGSEventGesture) | (1 << Self.kCGSEventDockControl)
        let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(mask),
            callback: { _, type, event, userInfo in
                guard let userInfo else { return Unmanaged.passUnretained(event) }
                let service = Unmanaged<InstantSpacesService>.fromOpaque(userInfo).takeUnretainedValue()
                return service.handleGestureEvent(type: type, event: event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        )

        guard let tap else { return }
        self.gestureTap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        self.gestureSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    private func removeGestureTap() {
        if let gestureTap {
            CGEvent.tapEnable(tap: gestureTap, enable: false)
        }
        if let gestureSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), gestureSource, .commonModes)
        }
        gestureTap = nil
        gestureSource = nil
    }

    private func handleGestureEvent(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let gestureTap { CGEvent.tapEnable(tap: gestureTap, enable: true) }
            return Unmanaged.passUnretained(event)
        }

        let defaults = UserDefaults.standard
        guard defaults.bool(forKey: DefaultsKey.instantSpacesTrackpadSwipeEnabled) else {
            return Unmanaged.passUnretained(event)
        }

        let eventType = event.getIntegerValueField(Self.kCGSEventTypeField)

        // Pass through synthetic events
        if eventType == Self.kCGSEventDockControl || eventType == Self.kCGSEventGesture {
            let sourcePid = event.getIntegerValueField(.eventSourceUnixProcessID)
            if sourcePid != 0 {
                return Unmanaged.passUnretained(event)
            }
        }

        if eventType == Self.kCGSEventDockControl {
            let hidType = event.getIntegerValueField(Self.kCGEventGestureHIDType)
            guard hidType == Self.kIOHIDEventTypeDockSwipe else {
                return Unmanaged.passUnretained(event)
            }

            let motion = event.getIntegerValueField(Self.kCGEventGestureSwipeMotion)
            guard motion == Self.kCGGestureMotionHorizontal else {
                return Unmanaged.passUnretained(event)
            }

            let phaseValue = event.getIntegerValueField(Self.kCGEventGesturePhase)
            guard let phase = CGSGesturePhase(rawValue: phaseValue) else {
                return swipeTracking ? nil : Unmanaged.passUnretained(event)
            }

            switch phase {
            case .began:
                if defaults.bool(forKey: DefaultsKey.instantSpacesOverlayDetectionEnabled)
                    && SpaceSwitcherSupport.isOverlayActive() {
                    return Unmanaged.passUnretained(event)
                }
                swipeTracking = true
                swipeFired = false
                return nil

            case .changed:
                guard swipeTracking else { return Unmanaged.passUnretained(event) }
                if !swipeFired {
                    let progress = event.getDoubleValueField(Self.kCGEventGestureSwipeProgress)
                    if progress != 0.0 {
                        var dir: SpaceDirection = progress > 0 ? .right : .left
                        if defaults.bool(forKey: DefaultsKey.instantSpacesSwipeDirectionReversed) {
                            dir = (dir == .right) ? .left : .right
                        }
                        swipeFired = true
                        performDirectionalSwitch(direction: dir)
                    }
                }
                return nil

            case .ended:
                guard swipeTracking else { return Unmanaged.passUnretained(event) }
                if !swipeFired {
                    let velocity = event.getDoubleValueField(Self.kCGEventGestureSwipeVelocityX)
                    if velocity != 0.0 {
                        var dir: SpaceDirection = velocity > 0 ? .right : .left
                        if defaults.bool(forKey: DefaultsKey.instantSpacesSwipeDirectionReversed) {
                            dir = (dir == .right) ? .left : .right
                        }
                        swipeFired = true
                        performDirectionalSwitch(direction: dir)
                    }
                }
                swipeTracking = false
                swipeFired = false
                restoreCursorVisibility()
                return nil

            case .cancelled:
                swipeTracking = false
                swipeFired = false
                restoreCursorVisibility()
                return nil
            }
        }

        if eventType == Self.kCGSEventGesture && swipeTracking {
            return nil
        }

        return Unmanaged.passUnretained(event)
    }

    // MARK: - Hotkey Tap

    private func installHotkeyTap() {
        guard hotkeyTap == nil else { return }

        let mask = 1 << CGEventType.keyDown.rawValue
        let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(mask),
            callback: { _, type, event, userInfo in
                guard let userInfo else { return Unmanaged.passUnretained(event) }
                let service = Unmanaged<InstantSpacesService>.fromOpaque(userInfo).takeUnretainedValue()
                return service.handleHotkeyEvent(type: type, event: event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        )

        guard let tap else { return }
        self.hotkeyTap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        self.hotkeySource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    private func removeHotkeyTap() {
        if let hotkeyTap {
            CGEvent.tapEnable(tap: hotkeyTap, enable: false)
        }
        if let hotkeySource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), hotkeySource, .commonModes)
        }
        hotkeyTap = nil
        hotkeySource = nil
    }

    private func handleHotkeyEvent(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let hotkeyTap { CGEvent.tapEnable(tap: hotkeyTap, enable: true) }
            return Unmanaged.passUnretained(event)
        }
        guard type == .keyDown else { return Unmanaged.passUnretained(event) }

        let defaults = UserDefaults.standard
        guard defaults.bool(forKey: DefaultsKey.instantSpacesHotkeysEnabled) else {
            return Unmanaged.passUnretained(event)
        }

        let relevantFlags: CGEventFlags = [.maskCommand, .maskShift, .maskControl, .maskAlternate]
        let flags = event.flags.intersection(relevantFlags)
        let keyCode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))

        for binding in activeBindings {
            if binding.keyCode == keyCode && binding.flags == flags {
                if let cmd = binding.command {
                    let commandToRun = cmd
                    DispatchQueue.global(qos: .userInitiated).async {
                        let proc = Process()
                        proc.executableURL = URL(fileURLWithPath: "/bin/sh")
                        proc.arguments = ["-c", commandToRun]
                        try? proc.run()
                    }
                    return nil
                } else if let targetSpaceIndex = binding.targetSpaceIndex {
                    DispatchQueue.main.async { [weak self] in
                        self?.switchToIndex(targetSpaceIndex)
                    }
                    return nil
                }
            }
        }

        return Unmanaged.passUnretained(event)
    }

    // MARK: - Switching Execution

    private func speed() -> Double {
        let saved = UserDefaults.standard.double(forKey: DefaultsKey.instantSpacesGestureSpeed)
        if saved > 0 { return saved }
        return loadedConfig.gestureSpeed > 0 ? loadedConfig.gestureSpeed : 2000.0
    }

    private func postDockSwipe(phase: CGSGesturePhase, direction: SpaceDirection, velocity: Double) -> Bool {
        let isRight = (direction == .right)
        let progress: Double
        if DockSwipeAugmentor.requiresAugmentation {
            progress = isRight ? 0.000016 : -0.000016
        } else {
            progress = isRight ? Double(Float.leastNonzeroMagnitude) : -Double(Float.leastNonzeroMagnitude)
        }

        let vel = isRight ? velocity : -velocity

        guard let ev = CGEvent(source: nil) else { return false }
        ev.setIntegerValueField(Self.kCGSEventTypeField, value: Self.kCGSEventDockControl)
        ev.setIntegerValueField(Self.kCGEventGestureHIDType, value: Self.kIOHIDEventTypeDockSwipe)
        ev.setIntegerValueField(Self.kCGEventGesturePhase, value: phase.rawValue)
        ev.setDoubleValueField(Self.kCGEventGestureSwipeProgress, value: progress)
        ev.setIntegerValueField(Self.kCGEventGestureSwipeMotion, value: Self.kCGGestureMotionHorizontal)

        if DockSwipeAugmentor.requiresAugmentation {
            ev.setIntegerValueField(Self.kCGEventGesturePhaseAlias, value: phase.rawValue)
            ev.setDoubleValueField(Self.kCGEventGestureZoomDeltaY, value: 3.0)
            ev.setDoubleValueField(Self.kCGEventSourceUnixProcessIDAlias, value: Double(mach_absolute_time()))
            ev.setDoubleValueField(Self.kCGEventGestureSwipePositionX, value: 0.1)

            if phase == .ended {
                ev.setDoubleValueField(Self.kCGEventGestureSwipeVelocityX, value: vel)
            }

            if let augmented = DockSwipeAugmentor.augment(event: ev) {
                augmented.post(tap: .cgSessionEventTap)
                return true
            }
            return false
        }

        ev.setDoubleValueField(Self.kCGEventGestureSwipeVelocityX, value: vel)
        ev.setDoubleValueField(Self.kCGEventGestureSwipeVelocityY, value: vel)
        ev.post(tap: .cgSessionEventTap)
        return true
    }

    private func performSwitchGesture(direction: SpaceDirection, velocity: Double) -> Bool {
        let phaseDelay: UInt32 = DockSwipeAugmentor.requiresAugmentation ? 10_000 : 0
        if !postDockSwipe(phase: .began, direction: direction, velocity: velocity) { return false }
        if phaseDelay > 0 { usleep(phaseDelay) }
        if !postDockSwipe(phase: .changed, direction: direction, velocity: velocity) { return false }
        if phaseDelay > 0 { usleep(phaseDelay) }
        if !postDockSwipe(phase: .ended, direction: direction, velocity: velocity) { return false }
        return true
    }

    private func performDirectionalSwitch(direction: SpaceDirection) {
        guard let info = SpaceSwitcherSupport.getSpaceInfo() else {
            _ = performSwitchGesture(direction: direction, velocity: speed())
            return
        }

        SpacePredictionCache.shared.refreshIfStale(currentInfo: info)
        let current = SpacePredictionCache.shared.getPrediction(for: info.displayID) ?? info.currentIndex

        if direction == .right && current == 0 { return }
        if direction == .left && current + 1 >= info.spaceCount { return }

        let target = direction == .right ? current - 1 : current + 1
        if performSwitchGesture(direction: direction, velocity: speed()) {
            SpacePredictionCache.shared.setPrediction(for: info.displayID, index: target)
            SpaceMenuBarIndicator.shared.updateSpace(index: target, total: info.spaceCount)
            restoreCursorVisibility()
        }
    }

    func switchToIndex(_ targetIndex: UInt32) {
        guard let info = SpaceSwitcherSupport.getSpaceInfo() else { return }
        guard info.spaceCount > 0 else { return }

        var target = min(targetIndex, info.spaceCount - 1)
        if UserDefaults.standard.bool(forKey: DefaultsKey.instantSpacesSpaceNumberingReversed) {
            target = info.spaceCount - 1 - target
        }

        SpacePredictionCache.shared.refreshIfStale(currentInfo: info)
        let current = SpacePredictionCache.shared.getPrediction(for: info.displayID) ?? info.currentIndex

        if current == target { return }

        let direction: SpaceDirection = (current < target) ? .left : .right
        let steps = (direction == .left) ? (target - current) : (current - target)
        let velocity = speed() * Double(steps)

        let sequenceDelay: UInt32 = DockSwipeAugmentor.requiresAugmentation ? 30_000 : 0
        for i in 0..<steps {
            if !performSwitchGesture(direction: direction, velocity: velocity) {
                break
            }
            if sequenceDelay > 0 && i + 1 < steps {
                usleep(sequenceDelay)
            }
        }

        SpacePredictionCache.shared.setPrediction(for: info.displayID, index: target)
        SpaceMenuBarIndicator.shared.updateSpace(index: target, total: info.spaceCount)
        restoreCursorVisibility()
    }

    func switchLeft() {
        performDirectionalSwitch(direction: .left)
    }

    func switchRight() {
        performDirectionalSwitch(direction: .right)
    }

    private func restoreCursorVisibility() {
        SpaceSwitcherSupport.ensureCursorVisible()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            SpaceSwitcherSupport.ensureCursorVisible()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            SpaceSwitcherSupport.ensureCursorVisible()
        }
    }
}
