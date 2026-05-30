//
//  DraftBarApp.swift
//  DraftBar
//
//  Created by 917Dhj on 2026/5/28.
//

import SwiftUI
import AppKit
import QuartzCore
import Darwin

#if !DRAFTBAR_TESTING
@main
#endif
struct DraftBarApp: App {
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

private enum StatusItemIconState {
    case hidden
    case visible

    var assetName: String {
        switch self {
        case .hidden:
            "StatusBarIconHidden"
        case .visible:
            "StatusBarIconVisible"
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
    private var statusPointerTracker = StatusItemPointerTracker()

    private let defaultPanelSize = NSSize(width: 420, height: 520)
    private let normalMinimumPanelSize = NSSize(width: 320, height: 260)
    private let statusDebugEnabled = ProcessInfo.processInfo.environment["DRAFTBAR_DEBUG_STATUS"] == "1"

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
        updateStatusItemIcon(.hidden)
        button.toolTip = "DraftBar"
        button.target = self
        button.action = #selector(statusItemPressed(_:))
        button.sendAction(on: [.leftMouseDown, .rightMouseDown])
        DispatchQueue.main.async { [weak self, weak button] in
            guard let self else { return }
            self.debugStatusLog("buttonBounds=\(button?.bounds ?? .zero) frame=\(self.statusButtonScreenFrameDescription())")
        }
    }

    private func updateStatusItemIcon(_ state: StatusItemIconState) {
        guard let button = statusItem?.button else { return }
        let image = NSImage(named: state.assetName)
            ?? NSImage(systemSymbolName: "square.and.pencil", accessibilityDescription: "DraftBar")
        image?.isTemplate = true
        button.image = image
    }

    @objc private func statusItemPressed(_ sender: NSStatusBarButton) {
        guard let event = NSApp.currentEvent else { return }
        debugStatusLog("statusItemPressed type=\(event.type.rawValue) screenPoint=\(screenPoint(for: event))")

        switch event.type {
        case .rightMouseDown:
            statusPointerTracker.reset()
            showStatusMenu()
        case .leftMouseDown:
            trackStatusItemLeftMouse(from: event, in: sender)
        default:
            break
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

        updateStatusItemIcon(.visible)
        NSApp.activate(ignoringOtherApps: true)
        focusController.requestFocus()
        debugStatusLog("showFloatingNote visible=\(panel.isVisible) frame=\(panel.frame)")
    }

    private func trackStatusItemLeftMouse(from initialEvent: NSEvent, in button: NSStatusBarButton) {
        button.highlight(true)
        performStatusActions(
            statusPointerTracker.handle(.leftDown(screenPoint(for: initialEvent))),
            at: screenPoint(for: initialEvent)
        )

        guard let window = button.window else {
            button.highlight(false)
            performStatusActions(statusPointerTracker.handle(.leftUp(NSEvent.mouseLocation)), at: NSEvent.mouseLocation)
            return
        }

        window.trackEvents(
            matching: [.leftMouseDragged, .leftMouseUp],
            timeout: NSEvent.foreverDuration,
            mode: .eventTracking
        ) { [weak self, weak button] event, stop in
            guard let self, let event else { return }
            let screenPoint = self.screenPoint(for: event)

            switch event.type {
            case .leftMouseDragged:
                self.performStatusActions(
                    self.statusPointerTracker.handle(.leftDragged(screenPoint)),
                    at: screenPoint
                )
            case .leftMouseUp:
                button?.highlight(false)
                self.performStatusActions(
                    self.statusPointerTracker.handle(.leftUp(screenPoint)),
                    at: screenPoint
                )
                stop.pointee = true
            default:
                break
            }
        }
    }

    private func performStatusActions(_ actions: [StatusItemPointerTracker.Action], at screenPoint: NSPoint) {
        for action in actions {
            switch action {
            case .showMenu:
                showStatusMenu()
            case .showNote:
                showFloatingNote(animatedFromStatusItem: true)
            case .beginDrag:
                beginStatusItemDrag(at: screenPoint)
            case .updateDrag:
                updateStatusItemDrag(at: screenPoint)
            case .endDrag:
                endStatusItemDrag(at: screenPoint)
            }
        }
    }

    private func screenPoint(for event: NSEvent) -> NSPoint {
        guard let window = event.window else {
            return NSEvent.mouseLocation
        }

        let rect = NSRect(origin: event.locationInWindow, size: .zero)
        return window.convertToScreen(rect).origin
    }

    private func beginStatusItemDrag(at screenPoint: NSPoint) {
        debugStatusLog("beginDrag at=\(screenPoint)")
        dragAnchorFrame = statusButtonScreenFrame()?.insetBy(dx: -6, dy: -6)
        dragPanelSize = lastFloatingFrame?.size ?? defaultPanelSize
        let panel = ensureNotePanel()
        if !panel.isVisible {
            panel.minSize = FloatingNoteLayout.dragSeedSize
            updateDragVisualState(for: screenPoint, isDragging: true)
        }
        showFloatingNoteForDrag(at: screenPoint)
    }

    private func updateStatusItemDrag(at screenPoint: NSPoint) {
        debugStatusLog("updateDrag at=\(screenPoint)")
        guard let panel = notePanel else { return }
        let panelSize = dragPanelSize ?? panel.frame.size
        panel.setFrame(dragPresentationFrame(for: screenPoint, panelSize: panelSize), display: true)
        panel.alphaValue = dragAlpha(for: screenPoint)
        updateDragVisualState(for: screenPoint, isDragging: true)
    }

    private func endStatusItemDrag(at screenPoint: NSPoint) {
        debugStatusLog("endDrag at=\(screenPoint)")
        if let panel = notePanel {
            let panelSize = dragPanelSize ?? panel.frame.size
            let finalFrame = dragFrame(for: screenPoint, currentSize: panelSize)
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

        updateStatusItemIcon(.visible)
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
            updateStatusItemIcon(.hidden)
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
            guard let self, let panel else { return }
            panel.orderOut(nil)
            panel.alphaValue = 1
            panel.setFrame(restoreFrame, display: false)
            self.isClosingPanel = false
            self.updateStatusItemIcon(.hidden)
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

    private func showStatusMenu() {
        guard let button = statusItem?.button else { return }
        debugStatusLog("showStatusMenu frame=\(statusButtonScreenFrameDescription())")

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: notePanel?.isVisible == true ? "Focus Note" : "Show Note", action: #selector(showNoteFromMenu), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Open Note File", action: #selector(openNoteFile), keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(quitApp), keyEquivalent: "q"))
        menu.items.forEach { $0.target = self }

        let menuPoint = NSPoint(x: button.bounds.minX, y: button.bounds.minY - 4)
        menu.popUp(positioning: nil, at: menuPoint, in: button)
    }

    private func statusButtonScreenFrameDescription() -> String {
        guard let frame = statusButtonScreenFrame() else { return "nil" }
        let cgPoint = cgEventPoint(forScreenPoint: frame.midPoint)
        return "\(frame) cgMid=\(cgPoint)"
    }

    private func cgEventPoint(forScreenPoint point: NSPoint) -> CGPoint {
        let screen = screen(containing: point)
        return CGPoint(x: point.x, y: screen.frame.maxY - point.y)
    }

    private func debugStatusLog(_ message: String) {
        guard statusDebugEnabled else { return }
        print("DraftBarStatusDebug: \(message)")
        fflush(stdout)
    }
}

struct StatusItemPointerTracker {
    enum PointerEvent {
        case leftDown(NSPoint)
        case leftDragged(NSPoint)
        case leftUp(NSPoint)
        case rightDown
    }

    enum Action: Equatable {
        case showMenu
        case showNote
        case beginDrag
        case updateDrag
        case endDrag
    }

    private let dragThreshold: CGFloat
    private var leftDownPoint: NSPoint?
    private var isDragging = false

    var isTracking: Bool {
        leftDownPoint != nil
    }

    init(dragThreshold: CGFloat = 4) {
        self.dragThreshold = dragThreshold
    }

    mutating func handle(_ event: PointerEvent) -> [Action] {
        switch event {
        case .rightDown:
            reset()
            return [.showMenu]
        case let .leftDown(point):
            leftDownPoint = point
            isDragging = false
            return []
        case let .leftDragged(point):
            guard let leftDownPoint else { return [] }
            if isDragging {
                return [.updateDrag]
            }
            guard distance(from: leftDownPoint, to: point) >= dragThreshold else {
                return []
            }
            isDragging = true
            return [.beginDrag, .updateDrag]
        case .leftUp:
            defer { reset() }
            return isDragging ? [.endDrag] : [.showNote]
        }
    }

    mutating func reset() {
        leftDownPoint = nil
        isDragging = false
    }

    private func distance(from start: NSPoint, to end: NSPoint) -> CGFloat {
        let dx = end.x - start.x
        let dy = end.y - start.y
        return sqrt(dx * dx + dy * dy)
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
