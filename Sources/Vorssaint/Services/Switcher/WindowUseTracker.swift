// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import ApplicationServices
import CoreGraphics

/// Remembers which windows and applications the user actually used, most
/// recent first. The switcher and window layout orders are built from this history.
///
/// Application activation is observed passively through NSWorkspace notifications
/// (zero polling, zero persistent background threads). When an application takes
/// focus, its process is immediately recorded, and its focused window is queried
/// asynchronously via Accessibility on a low-priority utility queue with a strict
/// messaging timeout so the main thread never blocks and macOS efficiency cores
/// remain in low-power idle states (zero Idle Prevention).
///
/// The window server's front-to-back order seeds the history at startup and
/// files windows that were never focused since.
final class WindowUseTracker {
    static let shared = WindowUseTracker()

    /// Ceiling for a single Accessibility round trip to an app that may not be
    /// servicing its run loop.
    private static let messagingTimeout: Float = 0.35

    private let stateLock = NSLock()
    private var windowHistory: [CGWindowID] = []
    private var appHistory: [pid_t] = []
    /// False from the moment the feature is switched off.
    private var recording = false

    private let lifecycleLock = NSLock()
    private var started = false
    private var activeObserver: NSObjectProtocol?
    private var terminateObserver: NSObjectProtocol?

    private init() {}

    // MARK: - History

    /// Most recently used windows, most recent first.
    var windows: [CGWindowID] { stateLock.withLock { windowHistory } }

    /// Most recently used applications, most recent first.
    var apps: [pid_t] { stateLock.withLock { appHistory } }

    /// Rank of an application; one never seen sorts after every known one.
    func rank(of pid: pid_t) -> Int {
        stateLock.withLock { appHistory.firstIndex(of: pid) ?? Int.max }
    }

    /// Records a switch the switcher itself performed. `previous` becomes the
    /// second-most-recent window, so a quick repeat toggles straight back.
    /// Applied immediately because the window server's order lags an
    /// activation by a frame or two, and a flick is faster than that.
    func recordSwitch(to windowID: CGWindowID?, from previous: CGWindowID?) {
        stateLock.withLock {
            guard recording else { return }
            windowHistory = WindowUseOrder.promoting(target: windowID,
                                                     previous: previous,
                                                     in: windowHistory)
        }
    }

    /// Drops what no longer exists and files windows that were never focused,
    /// using the window server's front-to-back order. Called by the enumerator,
    /// which already has both lists in hand.
    func reconcile(existingWindows: Set<CGWindowID>, frontToBack: FrontToBack, running: Set<pid_t>) {
        stateLock.withLock {
            guard recording else { return }
            windowHistory = WindowUseOrder.reconciled(windowHistory,
                                                      existing: existingWindows,
                                                      frontToBack: frontToBack.windows)
            appHistory = WindowUseOrder.reconciled(appHistory,
                                                   running: running,
                                                   frontToBack: frontToBack.apps)
        }
    }

    private func promote(window windowID: CGWindowID) {
        stateLock.withLock {
            guard recording else { return }
            windowHistory = WindowUseOrder.promoting(windowID, in: windowHistory)
        }
    }

    private func promote(app pid: pid_t) {
        stateLock.withLock {
            guard recording else { return }
            appHistory = WindowUseOrder.promoting(pid, in: appHistory)
        }
    }

    // MARK: - Lifecycle

    /// The history feeds the switcher and Window Layout's "every app" actions;
    /// with both features off in the hub, nothing observes anything.
    func syncWithFeatures() {
        if AppFeature.switcher.isAvailable || AppFeature.windowLayout.isAvailable {
            start()
        } else {
            stop()
        }
    }

    func start() {
        lifecycleLock.withLock {
            guard !started else { return }
            started = true
            stateLock.withLock { recording = true }

            seedFromWindowServer()

            let center = NSWorkspace.shared.notificationCenter
            activeObserver = center.addObserver(
                forName: NSWorkspace.didActivateApplicationNotification,
                object: nil,
                queue: .main
            ) { [weak self] note in
                self?.handleAppActivated(note)
            }
            terminateObserver = center.addObserver(
                forName: NSWorkspace.didTerminateApplicationNotification,
                object: nil,
                queue: .main
            ) { [weak self] note in
                self?.handleAppTerminated(note)
            }

            if let front = NSWorkspace.shared.frontmostApplication {
                handleFrontApp(front.processIdentifier)
            }
        }
    }

    func stop() {
        lifecycleLock.withLock {
            guard started else { return }
            started = false
            stateLock.withLock {
                recording = false
                windowHistory.removeAll()
                appHistory.removeAll()
            }
            let center = NSWorkspace.shared.notificationCenter
            if let activeObserver { center.removeObserver(activeObserver) }
            if let terminateObserver { center.removeObserver(terminateObserver) }
            activeObserver = nil
            terminateObserver = nil
        }
    }

    deinit {
        let center = NSWorkspace.shared.notificationCenter
        if let activeObserver { center.removeObserver(activeObserver) }
        if let terminateObserver { center.removeObserver(terminateObserver) }
    }

    private func handleAppActivated(_ note: Notification) {
        guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
        handleFrontApp(app.processIdentifier)
    }

    private func handleFrontApp(_ pid: pid_t) {
        // The application half is exact, free, and recorded immediately.
        promote(app: pid)

        // The window half queries Accessibility IPC and happens asynchronously
        // on a low-priority background queue with a messaging timeout so it never
        // stalls the main thread or keeps efficiency cores awake in a run loop.
        guard AXIsProcessTrusted() else { return }
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self, self.stateLock.withLock({ self.recording }) else { return }
            self.readFocusedWindow(of: pid)
        }
    }

    private func handleAppTerminated(_ note: Notification) {
        guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
        let pid = app.processIdentifier
        stateLock.withLock { appHistory.removeAll { $0 == pid } }
    }

    /// First history of the session: the window server's front-to-back order is
    /// the only account of what was used before the app was even running.
    private func seedFromWindowServer() {
        let runningPIDs = Set(NSWorkspace.shared.runningApplications.map(\.processIdentifier))
        reconcile(existingWindows: Set(Self.allWindows()),
                  frontToBack: Self.frontToBack(),
                  running: runningPIDs)
    }

    // MARK: - Accessibility resolution

    private func readFocusedWindow(of pid: pid_t) {
        guard AXIsProcessTrusted() else { return }
        let application = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(application, Self.messagingTimeout)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(application, kAXFocusedWindowAttribute as CFString, &value) == .success,
              let value,
              CFGetTypeID(value) == AXUIElementGetTypeID()
        else { return }
        // A misbehaving app can answer with something that is not an element.
        let window = value as! AXUIElement
        guard let windowID = AXWindowResolver.windowID(for: window) else { return }
        promote(window: windowID)
    }

    // MARK: - Window server

    /// What is on screen, front to back.
    struct FrontToBack {
        let windows: [CGWindowID]
        let apps: [pid_t]
    }

    /// On-screen windows and their applications, front to back. This is real
    /// z-order, and for anything never seen taking focus it is the only
    /// evidence of how recently it was used.
    static func frontToBack() -> FrontToBack {
        let raw = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements],
                                             kCGNullWindowID) as? [[String: Any]] ?? []
        var windows: [CGWindowID] = []
        var apps: [pid_t] = []
        var seenApps = Set<pid_t>()
        for entry in raw where (entry[kCGWindowLayer as String] as? Int) == 0 {
            guard let windowID = entry[kCGWindowNumber as String] as? CGWindowID else { continue }
            windows.append(windowID)
            if let pid = entry[kCGWindowOwnerPID as String] as? pid_t, seenApps.insert(pid).inserted {
                apps.append(pid)
            }
        }
        return FrontToBack(windows: windows, apps: apps)
    }

    private static func allWindows() -> [CGWindowID] {
        let raw = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]] ?? []
        return raw.compactMap { $0[kCGWindowNumber as String] as? CGWindowID }
    }
}
