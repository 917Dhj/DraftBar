//
//  ContentView.swift
//  DraftBar
//
//  Created by 917Dhj on 2026/5/28.
//

import SwiftUI
import AppKit
import Combine
import MarkdownEngine
import MarkdownEngineCodeBlocks
import MarkdownEngineLatex

final class MemoEditorFocusController: ObservableObject {
    @Published private(set) var requestID = 0

    func requestFocus() {
        requestID += 1
    }
}

final class FloatingNoteWindowState: ObservableObject {
    @Published var isPinned = true
}

final class FloatingNoteVisualState: ObservableObject {
    @Published var isDraggingFromStatusItem = false
    @Published var dragProgress: CGFloat = 1
}

enum FloatingNoteLayout {
    private static let dragEmergenceDistance: CGFloat = 180
    static let dragSeedSize = NSSize(width: 36, height: 36)

    static func dragFrame(for screenPoint: NSPoint, panelSize: NSSize, visibleFrame: NSRect) -> NSRect {
        let x = min(max(screenPoint.x - 32, visibleFrame.minX + 12), visibleFrame.maxX - panelSize.width - 12)
        let y = min(max(screenPoint.y - panelSize.height + 28, visibleFrame.minY + 12), visibleFrame.maxY - panelSize.height - 12)
        return NSRect(origin: NSPoint(x: x, y: y), size: panelSize)
    }

    static func emergingDragFrame(
        for screenPoint: NSPoint,
        panelSize: NSSize,
        constraintFrame: NSRect,
        progress: CGFloat
    ) -> NSRect {
        let clampedProgress = min(max(progress, 0), 1)
        let easedProgress = smoothstep(clampedProgress)
        let seedSize = dragSeedSize
        let currentSize = NSSize(
            width: interpolate(from: seedSize.width, to: panelSize.width, progress: easedProgress),
            height: interpolate(from: seedSize.height, to: panelSize.height, progress: easedProgress)
        )
        let cursorXOffset = interpolate(from: seedSize.width / 2, to: 32, progress: easedProgress)
        let cursorTopOffset = interpolate(from: seedSize.height / 2, to: 28, progress: easedProgress)

        return clampedFrame(
            NSRect(
                x: screenPoint.x - cursorXOffset,
                y: screenPoint.y - currentSize.height + cursorTopOffset,
                width: currentSize.width,
                height: currentSize.height
            ),
            in: constraintFrame,
            clampsTopEdge: false
        )
    }

    static func dragSeedFrame(from anchorFrame: NSRect) -> NSRect {
        NSRect(
            x: anchorFrame.midX - dragSeedSize.width / 2,
            y: anchorFrame.midY - dragSeedSize.height / 2,
            width: dragSeedSize.width,
            height: dragSeedSize.height
        )
    }

    static func dragProgress(from anchorFrame: NSRect, to screenPoint: NSPoint) -> CGFloat {
        let dx = screenPoint.x - anchorFrame.midX
        let dy = screenPoint.y - anchorFrame.midY
        let distance = sqrt(dx * dx + dy * dy)
        return min(max(distance / dragEmergenceDistance, 0), 1)
    }

    static func contentRevealProgress(forDragProgress progress: CGFloat) -> CGFloat {
        let revealStart: CGFloat = 0.28
        let clampedProgress = min(max(progress, 0), 1)
        guard clampedProgress > revealStart else { return 0 }
        return smoothstep((clampedProgress - revealStart) / (1 - revealStart))
    }

    static func dragSeedIconOpacity(forDragProgress progress: CGFloat) -> CGFloat {
        1 - contentRevealProgress(forDragProgress: progress)
    }

    private static func interpolate(from start: CGFloat, to end: CGFloat, progress: CGFloat) -> CGFloat {
        start + (end - start) * progress
    }

    private static func smoothstep(_ progress: CGFloat) -> CGFloat {
        progress * progress * (3 - 2 * progress)
    }

    private static func clampedFrame(_ frame: NSRect, in visibleFrame: NSRect, clampsTopEdge: Bool = true) -> NSRect {
        let x = min(max(frame.origin.x, visibleFrame.minX + 12), visibleFrame.maxX - frame.width - 12)
        let minY = visibleFrame.minY + 12
        let maxY = visibleFrame.maxY - frame.height - 12
        let y = clampsTopEdge ? min(max(frame.origin.y, minY), maxY) : max(frame.origin.y, minY)
        return NSRect(origin: NSPoint(x: x, y: y), size: frame.size)
    }
}

final class MemoStore: NSObject, ObservableObject {
    enum SaveState: Equatable {
        case saved
        case saving
        case failed(String)
    }

    @Published var text = "" {
        didSet {
            guard !isLoading, text != oldValue else { return }
            scheduleSave()
        }
    }

    @Published private(set) var saveState: SaveState = .saved

    let noteURL: URL
    private let legacyNoteURLs: [URL]
    private var lastSavedText = ""
    private var isLoading = false

    override init() {
        let baseURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        noteURL = baseURL
            .appendingPathComponent("DraftBar", isDirectory: true)
            .appendingPathComponent("note.md")
        legacyNoteURLs = Self.legacyNoteURLs(baseURL: baseURL)
        super.init()
    }

    func load() {
        isLoading = true
        defer { isLoading = false }

        do {
            try prepareDirectory()
            migrateLegacyNoteIfNeeded()
            if FileManager.default.fileExists(atPath: noteURL.path) {
                text = try String(contentsOf: noteURL, encoding: .utf8)
            } else {
                text = ""
            }
            lastSavedText = text
            saveState = .saved
        } catch {
            saveState = .failed(error.localizedDescription)
        }
    }

    func saveNow(force: Bool = false) {
        NSObject.cancelPreviousPerformRequests(
            withTarget: self,
            selector: #selector(saveFromDebounce),
            object: nil
        )

        guard force || text != lastSavedText || !FileManager.default.fileExists(atPath: noteURL.path) else {
            saveState = .saved
            return
        }

        do {
            try prepareDirectory()
            try text.write(to: noteURL, atomically: true, encoding: .utf8)
            lastSavedText = text
            saveState = .saved
        } catch {
            saveState = .failed(error.localizedDescription)
        }
    }

    private func scheduleSave() {
        saveState = .saving
        NSObject.cancelPreviousPerformRequests(
            withTarget: self,
            selector: #selector(saveFromDebounce),
            object: nil
        )
        perform(#selector(saveFromDebounce), with: nil, afterDelay: 0.4)
    }

    @objc private func saveFromDebounce() {
        saveNow()
    }

    private func prepareDirectory() throws {
        try FileManager.default.createDirectory(
            at: noteURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
    }

    private func migrateLegacyNoteIfNeeded() {
        let fileManager = FileManager.default
        guard !fileManager.fileExists(atPath: noteURL.path) else { return }

        for legacyURL in legacyNoteURLs where legacyURL.path != noteURL.path {
            guard fileManager.fileExists(atPath: legacyURL.path) else { continue }

            do {
                try fileManager.copyItem(at: legacyURL, to: noteURL)
                return
            } catch {
                continue
            }
        }
    }

    private static func legacyNoteURLs(baseURL: URL) -> [URL] {
        let homeURL = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
        let legacyDraftBarBundleID = "com.dinghongjing" + ".DraftBar"
        let candidates = [
            homeURL
                .appendingPathComponent("Library/Containers/\(legacyDraftBarBundleID)/Data/Library/Application Support/DraftBar", isDirectory: true)
                .appendingPathComponent("note.md"),
            baseURL
                .appendingPathComponent("MenuBarMemo", isDirectory: true)
                .appendingPathComponent("note.md"),
            homeURL
                .appendingPathComponent("Library/Application Support/MenuBarMemo", isDirectory: true)
                .appendingPathComponent("note.md"),
            homeURL
                .appendingPathComponent("Library/Containers/com.dinghongjing.MenuBarMemo/Data/Library/Application Support/MenuBarMemo", isDirectory: true)
                .appendingPathComponent("note.md")
        ]

        var seenPaths = Set<String>()
        return candidates.filter { url in
            let path = url.standardizedFileURL.path
            guard !seenPaths.contains(path) else { return false }
            seenPaths.insert(path)
            return true
        }
    }
}

struct FloatingNoteView: View {
    private static let editorHorizontalPadding: CGFloat = 8

    @ObservedObject var store: MemoStore
    @ObservedObject var focusController: MemoEditorFocusController
    @ObservedObject var windowState: FloatingNoteWindowState
    @ObservedObject var visualState: FloatingNoteVisualState

    let closeNote: () -> Void
    let togglePin: () -> Void
    let openNoteFile: () -> Void
    let quitApp: () -> Void

    private var revealProgress: CGFloat {
        visualState.isDraggingFromStatusItem
            ? FloatingNoteLayout.contentRevealProgress(forDragProgress: visualState.dragProgress)
            : 1
    }

    private var dragSeedOpacity: Double {
        visualState.isDraggingFromStatusItem
            ? Double(FloatingNoteLayout.dragSeedIconOpacity(forDragProgress: visualState.dragProgress))
            : 0
    }

    private var cornerRadius: CGFloat {
        visualState.isDraggingFromStatusItem
            ? 18 + (24 - 18) * revealProgress
            : 24
    }

    var body: some View {
        ZStack {
            dragSeedIcon
                .opacity(dragSeedOpacity)
                .allowsHitTesting(false)

            editorContent
                .opacity(Double(revealProgress))
                .scaleEffect(0.96 + 0.04 * revealProgress, anchor: .topLeading)
                .allowsHitTesting(revealProgress > 0.98)
        }
        .frame(
            minWidth: visualState.isDraggingFromStatusItem ? 0 : 320,
            idealWidth: 420,
            minHeight: visualState.isDraggingFromStatusItem ? 0 : 260,
            idealHeight: 520
        )
        .glassEffect(
            .regular,
            in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        )
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .animation(.easeOut(duration: 0.08), value: visualState.dragProgress)
    }

    private var editorContent: some View {
        ZStack(alignment: .topLeading) {
            MarkdownTextView(
                text: $store.text,
                focusRequestID: focusController.requestID,
                imageBaseURL: store.noteURL.deletingLastPathComponent()
            )
                .padding(.horizontal, Self.editorHorizontalPadding)
                .padding(.bottom, 8)

            floatingControls
        }
    }

    private var dragSeedIcon: some View {
        Image("StatusBarIconHidden")
            .renderingMode(.template)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: 16, height: 16)
            .foregroundStyle(.secondary)
    }

    private var floatingControls: some View {
        ZStack(alignment: .top) {
            WindowDragHandle()
                .frame(maxWidth: .infinity)
                .frame(height: 54)

            HStack(alignment: .top, spacing: 8) {
                Button(action: closeNote) {
                    CloseGlassButton()
                }
                .buttonStyle(.plain)
                .help("Close")

                Spacer(minLength: 12)

                HStack(spacing: 10) {
                    Text("\(store.text.count) 字")
                        .fontWeight(.medium)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()

                    Button(action: togglePin) {
                        PinGlassButton(isPinned: windowState.isPinned)
                    }
                    .buttonStyle(.plain)
                    .help(windowState.isPinned ? "Unpin from front" : "Pin on top")
                }
            }
            .padding(.top, 14)
            .padding(.horizontal, 16)
        }
        .font(.caption)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

struct CloseGlassButton: View {
    var body: some View {
        ZStack {
            Circle()
                .fill(.ultraThinMaterial)
                .overlay {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.42),
                                    Color(nsColor: .separatorColor).opacity(0.18)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                }
                .overlay {
                    Circle()
                        .stroke(.white.opacity(0.46), lineWidth: 1)
                }
                .shadow(color: .black.opacity(0.12), radius: 6, y: 2)

            Image(systemName: "xmark")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.secondary)
        }
        .frame(width: 30, height: 30)
        .contentShape(Circle())
    }
}

struct PinGlassButton: View {
    let isPinned: Bool

    var body: some View {
        ZStack {
            Circle()
                .fill(.ultraThinMaterial)
                .overlay {
                    Circle()
                        .stroke(.white.opacity(isPinned ? 0.34 : 0.18), lineWidth: 1)
                }
                .shadow(color: .black.opacity(0.10), radius: 6, y: 2)

            Image(systemName: isPinned ? "pin.fill" : "pin")
                .font(.system(size: 12, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(isPinned ? .primary : .secondary)
        }
        .frame(width: 30, height: 30)
        .contentShape(Circle())
    }
}

struct WindowDragHandle: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        DragHandleView()
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    final class DragHandleView: NSView {
        override func mouseDown(with event: NSEvent) {
            window?.performDrag(with: event)
        }
    }
}

struct MarkdownTextView: View {
    private static let syntaxHighlighter = HighlighterSwiftBridge()
    private static let latexRenderer = SwiftMathBridge()

    private var configuration: MarkdownEditorConfiguration {
        var configuration = MarkdownEditorConfiguration.default
        configuration.services = MarkdownEditorServices(
            images: LocalMarkdownImageProvider(baseURL: imageBaseURL),
            syntaxHighlighter: Self.syntaxHighlighter,
            latex: Self.latexRenderer
        )
        configuration.safeAreaInsets = SafeAreaInsets(top: 54)
        configuration.textInsets = TextInsets(horizontal: 23, vertical: 4)
        configuration.scrollers = .vertical
        configuration.spellChecking = SpellCheckingPolicy(
            continuousSpellChecking: false,
            grammarChecking: false,
            automaticSpellingCorrection: false
        )
        return configuration
    }

    private static let placeholder = NSAttributedString(
        string: "写点什么...",
        attributes: [
            .font: NSFont.systemFont(ofSize: 15),
            .foregroundColor: NSColor.tertiaryLabelColor
        ]
    )

    @Binding var text: String
    let focusRequestID: Int
    let imageBaseURL: URL

    var body: some View {
        NativeTextViewWrapper(
            text: $text,
            configuration: configuration,
            fontSize: 15,
            documentId: "draftbar-single-draft",
            placeholder: Self.placeholder
        )
        .background(MarkdownTextPreferencesBridge(focusRequestID: focusRequestID))
    }
}

private struct LocalMarkdownImageProvider: EmbeddedImageProvider {
    let baseURL: URL

    func image(for reference: EmbeddedImageRequest) -> NSImage? {
        guard let url = localURL(for: reference.name) else { return nil }
        return NSImage(contentsOf: url)
    }

    func fingerprint() -> AnyHashable {
        baseURL.standardizedFileURL.path
    }

    private func localURL(for path: String) -> URL? {
        if let url = URL(string: path, relativeTo: baseURL), url.isFileURL {
            return url.standardizedFileURL
        }
        guard path.hasPrefix("/") else { return nil }
        return URL(fileURLWithPath: path).standardizedFileURL
    }
}

private struct MarkdownTextPreferencesBridge: NSViewRepresentable {
    let focusRequestID: Int

    func makeNSView(context: Context) -> ProbeView {
        let view = ProbeView()
        view.focusRequestID = focusRequestID
        return view
    }

    func updateNSView(_ nsView: ProbeView, context: Context) {
        nsView.focusRequestID = focusRequestID
        nsView.configureEditor()
    }

    final class ProbeView: NSView {
        var focusRequestID = 0
        private var appliedFocusRequestID = -1
        private weak var observedTextView: NSTextView?
        private var selectionObserver: NSObjectProtocol?

        deinit {
            if let selectionObserver {
                NotificationCenter.default.removeObserver(selectionObserver)
            }
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            configureEditor()
        }

        func configureEditor() {
            DispatchQueue.main.async { [weak self] in
                guard let self, let textView = self.findEditorTextView() else { return }

                self.observeSelectionChanges(in: textView)
                self.applyTextPreferences(to: textView)

                guard self.appliedFocusRequestID != self.focusRequestID else { return }
                guard let window = textView.window,
                      window.makeFirstResponder(textView) else { return }
                self.appliedFocusRequestID = self.focusRequestID
            }
        }

        private func findEditorTextView() -> NSTextView? {
            var ancestor = superview
            while let view = ancestor {
                if let textView = Self.firstTextView(in: view) {
                    return textView
                }
                ancestor = view.superview
            }
            return nil
        }

        private func observeSelectionChanges(in textView: NSTextView) {
            guard observedTextView !== textView else { return }
            if let selectionObserver {
                NotificationCenter.default.removeObserver(selectionObserver)
            }
            observedTextView = textView
            selectionObserver = NotificationCenter.default.addObserver(
                forName: NSTextView.didChangeSelectionNotification,
                object: textView,
                queue: .main
            ) { [weak self, weak textView] _ in
                DispatchQueue.main.async {
                    guard let self, let textView else { return }
                    self.applyTextPreferences(to: textView)
                }
            }
        }

        private func applyTextPreferences(to textView: NSTextView) {
            textView.backgroundColor = .clear
            textView.drawsBackground = false
            textView.insertionPointColor = .controlAccentColor
            textView.isAutomaticQuoteSubstitutionEnabled = false
            textView.isAutomaticDashSubstitutionEnabled = false
            textView.isAutomaticTextReplacementEnabled = false
            textView.isAutomaticSpellingCorrectionEnabled = false
            textView.isAutomaticDataDetectionEnabled = false
            textView.isContinuousSpellCheckingEnabled = false
            textView.isGrammarCheckingEnabled = false
            textView.usesFindPanel = true
        }

        private static func firstTextView(in view: NSView) -> NSTextView? {
            if let textView = view as? NSTextView {
                return textView
            }
            for subview in view.subviews {
                if let textView = firstTextView(in: subview) {
                    return textView
                }
            }
            return nil
        }
    }
}
