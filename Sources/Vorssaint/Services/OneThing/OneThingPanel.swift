// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Carbon.HIToolbox
import SwiftUI

// MARK: - Keyable Panel

final class KeyableOneThingPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

// MARK: - Controller

final class OneThingPanelController: ObservableObject {
    static let shared = OneThingPanelController()

    @Published var isWritingNextTask = false

    private var panel: KeyableOneThingPanel?
    private var localKeyMonitor: Any?

    private init() {}

    var isVisible: Bool {
        panel?.isVisible ?? false
    }

    func toggle(statusItem: NSStatusItem? = nil) {
        if isVisible {
            close()
        } else {
            show(statusItem: statusItem)
        }
    }

    func show(statusItem: NSStatusItem? = nil) {
        let p = ensurePanel()
        isWritingNextTask = false
        positionPanel(p, statusItem: statusItem)
        p.alphaValue = 0
        p.orderFrontRegardless()
        p.makeKey()

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.12
            p.animator().alphaValue = 1
        }

        installLocalKeyMonitor()
    }

    func close() {
        removeLocalKeyMonitor()
        guard let p = panel, p.isVisible else { return }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.12
            p.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            self?.panel?.orderOut(nil)
            self?.isWritingNextTask = false
        })
    }

    private func ensurePanel() -> KeyableOneThingPanel {
        if let panel { return panel }
        let p = KeyableOneThingPanel(
            contentRect: NSRect(x: 0, y: 0, width: 380, height: 160),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        p.title = "One Thing"
        p.isReleasedWhenClosed = false
        p.hidesOnDeactivate = false
        p.level = .floating
        p.backgroundColor = .clear
        p.isOpaque = false
        p.hasShadow = true
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]

        let host = NSHostingController(rootView: OneThingPanelView())
        p.contentViewController = host

        self.panel = p
        return p
    }

    private func positionPanel(_ p: NSPanel, statusItem: NSStatusItem?) {
        let size = NSSize(width: 380, height: 160)
        p.setContentSize(size)

        let screen = NSScreen.main ?? NSScreen.screens.first ?? NSScreen()
        let visibleFrame = screen.visibleFrame

        var targetPoint: NSPoint
        if let button = statusItem?.button, let win = button.window, statusItem?.isVisible == true {
            let buttonRect = button.convert(button.bounds, to: nil)
            let screenRect = win.convertToScreen(buttonRect)
            targetPoint = NSPoint(
                x: min(max(screenRect.midX - size.width / 2, visibleFrame.minX + 12), visibleFrame.maxX - size.width - 12),
                y: max(screenRect.minY - size.height - 8, visibleFrame.minY + 12)
            )
        } else {
            targetPoint = NSPoint(
                x: visibleFrame.maxX - size.width - 24,
                y: visibleFrame.maxY - size.height - 16
            )
        }

        p.setFrame(NSRect(origin: targetPoint, size: size), display: true)
    }

    private func installLocalKeyMonitor() {
        removeLocalKeyMonitor()
        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.isVisible else { return event }

            // Escape cancels / closes
            if event.keyCode == 53 { // Escape
                self.close()
                return nil
            }

            // If an active task is visible and not in "typing next task" mode:
            // Space or Enter completes task immediately
            let hasActiveTask = (OneThingService.shared.activeTask != nil) && !self.isWritingNextTask
            if hasActiveTask {
                if event.keyCode == 36 || event.keyCode == 76 || event.keyCode == 49 { // Return or Keypad Enter or Space
                    OneThingService.shared.completeActiveTask()
                    self.isWritingNextTask = true
                    return nil
                }
            }

            return event
        }
    }

    private func removeLocalKeyMonitor() {
        if let monitor = localKeyMonitor {
            NSEvent.removeMonitor(monitor)
            localKeyMonitor = nil
        }
    }
}

// MARK: - Native Text Field with Auto First Responder

struct OneThingNativeTextField: NSViewRepresentable {
    @Binding var text: String
    let placeholder: String
    let onCommit: () -> Void
    let onCancel: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField()
        field.placeholderString = placeholder
        field.stringValue = text
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = .systemFont(ofSize: 15, weight: .medium)
        field.delegate = context.coordinator

        DispatchQueue.main.async {
            field.window?.makeKey()
            field.window?.makeFirstResponder(field)
            field.selectText(nil)
        }
        return field
    }

    func updateNSView(_ nsView: NSTextField, context: Context) {
        if nsView.stringValue != text {
            nsView.stringValue = text
        }
        DispatchQueue.main.async {
            if nsView.window?.firstResponder != nsView.currentEditor() && nsView.window?.firstResponder != nsView {
                nsView.window?.makeFirstResponder(nsView)
            }
        }
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        let parent: OneThingNativeTextField

        init(_ parent: OneThingNativeTextField) {
            self.parent = parent
        }

        func controlTextDidChange(_ obj: Notification) {
            guard let field = obj.object as? NSTextField else { return }
            parent.text = field.stringValue
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                parent.onCommit()
                return true
            }
            if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
                parent.onCancel()
                return true
            }
            return false
        }
    }
}

// MARK: - SwiftUI Panel View

struct OneThingPanelView: View {
    @ObservedObject private var service = OneThingService.shared
    @ObservedObject private var controller = OneThingPanelController.shared
    @State private var inputText = ""

    private var activeTask: OneThingTask? {
        controller.isWritingNextTask ? nil : service.activeTask
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Label("One Thing", systemImage: "checklist")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    controller.close()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 8)

            Divider()
                .opacity(0.4)

            // Content
            VStack(alignment: .leading, spacing: 12) {
                if let task = activeTask, !task.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    // Active Task View
                    Text(task.text)
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 4)

                    HStack {
                        Text(task.createdAt, style: .time)
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Spacer()

                        Button {
                            service.completeActiveTask()
                            controller.isWritingNextTask = true
                            inputText = ""
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "checkmark.circle.fill")
                                Text("Complete (Enter)")
                            }
                            .font(.system(size: 13, weight: .semibold))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.accentColor)
                            .foregroundStyle(.white)
                            .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                } else {
                    // New Task Input View
                    VStack(alignment: .leading, spacing: 8) {
                        OneThingNativeTextField(
                            text: $inputText,
                            placeholder: "What is your One Thing?",
                            onCommit: {
                                commitNewTask()
                            },
                            onCancel: {
                                controller.close()
                            }
                        )
                        .frame(height: 32)
                        .padding(.horizontal, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(Color.primary.opacity(0.06))
                        )

                        HStack {
                            Text("Press Enter to set • Esc to cancel")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                            Spacer()
                            Button("Set") {
                                commitNewTask()
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                            .disabled(inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                    }
                    .padding(.top, 4)
                }
            }
            .padding(16)

            Spacer(minLength: 0)
        }
        .frame(width: 380, height: 160)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.regularMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.5)
                )
        )
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func commitNewTask() {
        let trimmed = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            service.setTask(text: trimmed)
            inputText = ""
            controller.close()
        }
    }
}
