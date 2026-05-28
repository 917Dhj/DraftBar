//
//  MenuBarMemoApp.swift
//  MenuBarMemo
//
//  Created by 丁泓景 on 2026/5/28.
//

import SwiftUI
import AppKit
import QuartzCore

@main
struct MenuBarMemoApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    init() {
        NSApplication.shared.setActivationPolicy(.accessory)
    }

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private let store = MemoStore()
    private let focusController = MemoEditorFocusController()
    private let windowState = FloatingNoteWindowState()
    private let visualState = FloatingNoteVisualState()
    private var statusItem: NSStatusItem?
    private var notePanel: FloatingNotePanel?
    private var lastFloatingFrame: NSRect?
    private var dragAnchorFrame: NSRect?
    private var dragPanelSize: NSSize?
    private var isClosingPanel = false
    private var ignoreNextStatusClick = false

    private let defaultPanelSize = NSSize(width: 420, height: 520)
    private let normalMinimumPanelSize = NSSize(width: 320, height: 260)

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        store.load()
        configureStatusItem()
    }

    func applicationWillTerminate(_ notification: Notification) {
        store.saveNow(force: true)
    }

    private func configureStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem = item

        guard let button = item.button else { return }
        let image = NSImage(systemSymbolName: "square.and.pencil", accessibilityDescription: "MenuBarMemo")
        image?.isTemplate = true
        button.image = image
        button.toolTip = "MenuBarMemo"
        button.target = self
        button.action = #selector(statusItemClicked(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])

        let dragRecognizer = NSPanGestureRecognizer(target: self, action: #selector(statusItemDragged(_:)))
        button.addGestureRecognizer(dragRecognizer)
    }

    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        guard !ignoreNextStatusClick else { return }

        if NSApp.currentEvent?.type == .rightMouseUp {
            showStatusMenu(from: sender)
        } else {
            showFloatingNote(animatedFromStatusItem: true)
        }
    }

    @objc private func showNoteFromMenu() {
        showFloatingNote(animatedFromStatusItem: true)
    }

    @objc private func openNoteFile() {
        store.saveNow(force: true)
        NSWorkspace.shared.activateFileViewerSelecting([store.noteURL])
    }

    @objc private func quitApp() {
        store.saveNow(force: true)
        NSApp.terminate(nil)
    }

    @objc private func statusItemDragged(_ recognizer: NSPanGestureRecognizer) {
        switch recognizer.state {
        case .began:
            ignoreNextStatusClick = true
            dragAnchorFrame = statusButtonScreenFrame()?.insetBy(dx: -6, dy: -6)
            dragPanelSize = lastFloatingFrame?.size ?? defaultPanelSize
            let panel = ensureNotePanel()
            if !panel.isVisible {
                panel.minSize = FloatingNoteLayout.dragSeedSize
                updateDragVisualState(for: NSEvent.mouseLocation, isDragging: true)
            }
            showFloatingNoteForDrag(at: NSEvent.mouseLocation)
        case .changed:
            guard let panel = notePanel else { return }
            let panelSize = dragPanelSize ?? panel.frame.size
            panel.setFrame(dragPresentationFrame(for: NSEvent.mouseLocation, panelSize: panelSize), display: true)
            panel.alphaValue = dragAlpha(for: NSEvent.mouseLocation)
            updateDragVisualState(for: NSEvent.mouseLocation, isDragging: true)
        case .ended, .cancelled, .failed:
            if let panel = notePanel {
                let panelSize = dragPanelSize ?? panel.frame.size
                let finalFrame = dragFrame(for: NSEvent.mouseLocation, currentSize: panelSize)
                visualState.dragProgress = 1
                animate(panel: panel, to: finalFrame, alpha: 1, duration: 0.12) { [weak self, weak panel] in
                    guard let self, let panel else { return }
                    panel.minSize = self.normalMinimumPanelSize
                    self.visualState.isDraggingFromStatusItem = false
                }
                lastFloatingFrame = finalFrame
            }
            dragAnchorFrame = nil
            dragPanelSize = nil
            NSApp.activate(ignoringOtherApps: true)
            focusController.requestFocus()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
                self?.ignoreNextStatusClick = false
            }
        default:
            break
        }
    }

    private func showFloatingNote(animatedFromStatusItem: Bool) {
        let panel = ensureNotePanel()
        panel.minSize = normalMinimumPanelSize
        visualState.isDraggingFromStatusItem = false
        visualState.dragProgress = 1
        let targetFrame = lastFloatingFrame ?? defaultPanelFrame()

        if animatedFromStatusItem, !panel.isVisible, let startFrame = statusButtonScreenFrame()?.insetBy(dx: -6, dy: -6) {
            panel.alphaValue = 0
            panel.setFrame(startFrame, display: false)
            panel.makeKeyAndOrderFront(nil)
            animate(panel: panel, to: targetFrame, alpha: 1, duration: 0.22)
        } else {
            panel.alphaValue = 1
            panel.setFrame(targetFrame, display: true)
            panel.makeKeyAndOrderFront(nil)
        }

        NSApp.activate(ignoringOtherApps: true)
        focusController.requestFocus()
    }

    private func showFloatingNoteForDrag(at screenPoint: NSPoint) {
        let panel = ensureNotePanel()
        let wasVisible = panel.isVisible
        let panelSize = dragPanelSize ?? lastFloatingFrame?.size ?? defaultPanelSize
        let frame = dragPresentationFrame(for: screenPoint, panelSize: panelSize)
        let alpha = dragAlpha(for: screenPoint)

        if !wasVisible, let dragAnchorFrame {
            panel.alphaValue = 0.14
            panel.setFrame(FloatingNoteLayout.dragSeedFrame(from: dragAnchorFrame), display: false)
            panel.makeKeyAndOrderFront(nil)
            animate(panel: panel, to: frame, alpha: alpha, duration: 0.11, timingFunctionName: .easeOut)
        } else {
            panel.alphaValue = alpha
            panel.setFrame(frame, display: true)
            panel.makeKeyAndOrderFront(nil)
        }

        applyPinnedLevel(to: panel)
        NSApp.activate(ignoringOtherApps: true)
        focusController.requestFocus()
    }

    private func closeFloatingNote() {
        guard let panel = notePanel else { return }

        store.saveNow(force: true)
        lastFloatingFrame = panel.frame

        guard let targetFrame = statusButtonScreenFrame()?.insetBy(dx: -6, dy: -6) else {
            panel.orderOut(nil)
            return
        }

        let restoreFrame = panel.frame
        isClosingPanel = true
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            context.allowsImplicitAnimation = true
            panel.animator().setFrame(targetFrame, display: true)
            panel.animator().alphaValue = 0
        } completionHandler: { [weak self, weak panel] in
            guard let panel else { return }
            panel.orderOut(nil)
            panel.alphaValue = 1
            panel.setFrame(restoreFrame, display: false)
            self?.isClosingPanel = false
        }
    }

    private func ensureNotePanel() -> FloatingNotePanel {
        if let notePanel {
            return notePanel
        }

        let panel = FloatingNotePanel(
            contentRect: defaultPanelFrame(),
            styleMask: [.titled, .fullSizeContentView, .resizable],
            backing: .buffered,
            defer: false
        )
        panel.delegate = self
        applyPinnedLevel(to: panel)
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isMovableByWindowBackground = true
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.minSize = normalMinimumPanelSize

        panel.standardWindowButton(.closeButton)?.isHidden = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true

        panel.contentViewController = NSHostingController(
            rootView: FloatingNoteView(
                store: store,
                focusController: focusController,
                windowState: windowState,
                visualState: visualState,
                closeNote: { [weak self] in self?.closeFloatingNote() },
                togglePin: { [weak self] in self?.togglePinned() },
                openNoteFile: { [weak self] in self?.openNoteFile() },
                quitApp: { [weak self] in self?.quitApp() }
            )
        )

        notePanel = panel
        return panel
    }

    private func togglePinned() {
        windowState.isPinned.toggle()
        if let panel = notePanel {
            applyPinnedLevel(to: panel)
        }
    }

    private func applyPinnedLevel(to panel: NSPanel) {
        panel.level = windowState.isPinned ? .floating : .normal
    }

    private func updateDragVisualState(for screenPoint: NSPoint, isDragging: Bool) {
        visualState.isDraggingFromStatusItem = isDragging
        if let dragAnchorFrame {
            visualState.dragProgress = FloatingNoteLayout.dragProgress(from: dragAnchorFrame, to: screenPoint)
        } else {
            visualState.dragProgress = isDragging ? 0 : 1
        }
    }

    private func animate(
        panel: NSPanel,
        to frame: NSRect,
        alpha: CGFloat,
        duration: TimeInterval,
        timingFunctionName: CAMediaTimingFunctionName = .easeInEaseOut,
        completionHandler: (() -> Void)? = nil
    ) {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = duration
            context.allowsImplicitAnimation = true
            context.timingFunction = CAMediaTimingFunction(name: timingFunctionName)
            panel.animator().setFrame(frame, display: true)
            panel.animator().alphaValue = alpha
        } completionHandler: {
            completionHandler?()
        }
    }

    private func defaultPanelFrame() -> NSRect {
        let anchorFrame = statusButtonScreenFrame()
        let screen = screen(containing: anchorFrame?.midPoint ?? NSEvent.mouseLocation)
        let visibleFrame = screen.visibleFrame
        let size = lastFloatingFrame?.size ?? defaultPanelSize
        let anchorX = anchorFrame?.midX ?? visibleFrame.midX
        let anchorY = anchorFrame?.minY ?? visibleFrame.maxY

        let x = min(max(anchorX - size.width + 48, visibleFrame.minX + 12), visibleFrame.maxX - size.width - 12)
        let y = min(max(anchorY - size.height - 10, visibleFrame.minY + 12), visibleFrame.maxY - size.height - 12)
        return NSRect(origin: NSPoint(x: x, y: y), size: size)
    }

    private func dragFrame(for screenPoint: NSPoint, currentSize: NSSize) -> NSRect {
        let screen = screen(containing: screenPoint)
        return FloatingNoteLayout.dragFrame(
            for: screenPoint,
            panelSize: currentSize,
            visibleFrame: screen.visibleFrame
        )
    }

    private func dragPresentationFrame(for screenPoint: NSPoint, panelSize: NSSize) -> NSRect {
        let screen = screen(containing: screenPoint)
        guard let dragAnchorFrame else {
            return FloatingNoteLayout.dragFrame(
                for: screenPoint,
                panelSize: panelSize,
                visibleFrame: screen.visibleFrame
            )
        }

        return FloatingNoteLayout.emergingDragFrame(
            for: screenPoint,
            panelSize: panelSize,
            constraintFrame: screen.frame,
            progress: FloatingNoteLayout.dragProgress(from: dragAnchorFrame, to: screenPoint)
        )
    }

    private func dragAlpha(for screenPoint: NSPoint) -> CGFloat {
        guard let dragAnchorFrame else { return 1 }
        let progress = FloatingNoteLayout.dragProgress(from: dragAnchorFrame, to: screenPoint)
        return 0.34 + progress * 0.66
    }

    private func statusButtonScreenFrame() -> NSRect? {
        guard let button = statusItem?.button,
              let window = button.window else {
            return nil
        }

        let rectInWindow = button.convert(button.bounds, to: nil)
        return window.convertToScreen(rectInWindow)
    }

    private func screen(containing point: NSPoint) -> NSScreen {
        NSScreen.screens.first { NSMouseInRect(point, $0.frame, false) } ?? NSScreen.main ?? NSScreen.screens[0]
    }

    func windowDidMove(_ notification: Notification) {
        guard !isClosingPanel, let panel = notification.object as? NSPanel else { return }
        lastFloatingFrame = panel.frame
    }

    func windowDidResize(_ notification: Notification) {
        guard !isClosingPanel, let panel = notification.object as? NSPanel else { return }
        lastFloatingFrame = panel.frame
    }

    private func showStatusMenu(from sender: NSStatusBarButton) {
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: notePanel?.isVisible == true ? "Focus Note" : "Show Note", action: #selector(showNoteFromMenu), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Open Note File", action: #selector(openNoteFile), keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(quitApp), keyEquivalent: "q"))
        menu.items.forEach { $0.target = self }

        statusItem?.menu = menu
        sender.performClick(nil)
        statusItem?.menu = nil
    }
}

private extension NSRect {
    var midPoint: NSPoint {
        NSPoint(x: midX, y: midY)
    }
}

final class FloatingNotePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}
