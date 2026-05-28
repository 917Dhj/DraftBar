//
//  ContentView.swift
//  MenuBarMemo
//
//  Created by 丁泓景 on 2026/5/28.
//

import SwiftUI
import AppKit
import Combine

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

    static func dragShadowRadius(forDragProgress progress: CGFloat) -> CGFloat {
        interpolate(from: 8, to: 24, progress: smoothstep(min(max(progress, 0), 1)))
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
    private var lastSavedText = ""
    private var isLoading = false

    override init() {
        let baseURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        noteURL = baseURL
            .appendingPathComponent("MenuBarMemo", isDirectory: true)
            .appendingPathComponent("note.md")
        super.init()
    }

    func load() {
        isLoading = true
        defer { isLoading = false }

        do {
            try prepareDirectory()
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
}

enum MarkdownStyleKind: Equatable {
    case headingLine(level: Int)
    case strongText
    case emphasisText
    case strikethroughText
    case inlineCode
    case inlineFormula
    case blockBackground
    case codeBlock
    case formulaBlock
    case linkText
    case imageAlt
    case blockquoteLine
    case blockquoteMarker
    case unorderedListMarker
    case orderedListMarker
    case taskListMarker(isChecked: Bool)
    case horizontalRule
    case codeBlockFence
    case formulaBlockFence
    case markdownDelimiter
}

struct MarkdownStyleSpan: Equatable {
    let kind: MarkdownStyleKind
    let range: NSRange
}

enum MarkdownStyleResolver {
    static func spans(in text: String, activeLocation: Int? = nil) -> [MarkdownStyleSpan] {
        let nsText = text as NSString
        let fullRange = NSRange(location: 0, length: nsText.length)
        guard fullRange.length > 0 else { return [] }

        var spans: [MarkdownStyleSpan] = []
        let codeBlockRanges = fencedCodeSpans(in: nsText, activeLocation: activeLocation, into: &spans)
        let formulaBlockRanges = formulaBlockSpans(in: nsText, activeLocation: activeLocation, into: &spans)
        let blockRanges = codeBlockRanges + formulaBlockRanges
        let codeMatches = regexMatches("`([^`\\n]+)`", in: nsText, range: fullRange)
        var excludedInlineRanges = blockRanges

        for match in codeMatches where !blockRanges.contains(where: { intersects($0, match.range) }) {
            let innerRange = match.range(at: 1)
            spans.append(MarkdownStyleSpan(kind: .inlineCode, range: innerRange))
            spans.append(MarkdownStyleSpan(kind: .markdownDelimiter, range: NSRange(location: match.range.location, length: 1)))
            spans.append(MarkdownStyleSpan(kind: .markdownDelimiter, range: NSRange(location: NSMaxRange(match.range) - 1, length: 1)))
            excludedInlineRanges.append(match.range)
        }

        let formulaMatches = regexMatches("(?<!\\$)\\$([^$\\n]+?)\\$(?!\\$)", in: nsText, range: fullRange)
        for match in formulaMatches where !excludedInlineRanges.contains(where: { intersects($0, match.range) }) {
            let innerRange = match.range(at: 1)
            spans.append(MarkdownStyleSpan(kind: .inlineFormula, range: innerRange))
            spans.append(MarkdownStyleSpan(kind: .markdownDelimiter, range: NSRange(location: match.range.location, length: 1)))
            spans.append(MarkdownStyleSpan(kind: .markdownDelimiter, range: NSRange(location: NSMaxRange(match.range) - 1, length: 1)))
            excludedInlineRanges.append(match.range)
        }

        for lineRange in lineRanges(in: nsText) {
            guard !blockRanges.contains(where: { intersects($0, lineRange) }) else { continue }
            spans.append(contentsOf: headingSpans(in: nsText, lineRange: lineRange))
            spans.append(contentsOf: blockquoteSpans(in: nsText, lineRange: lineRange))
            spans.append(contentsOf: listSpans(in: nsText, lineRange: lineRange))
            spans.append(contentsOf: horizontalRuleSpans(in: nsText, lineRange: lineRange))
        }

        spans.append(contentsOf: inlineSpans(
            in: nsText,
            fullRange: fullRange,
            excludedRanges: excludedInlineRanges
        ))

        return spans.sorted {
            if $0.range.location == $1.range.location {
                return $0.range.length > $1.range.length
            }
            return $0.range.location < $1.range.location
        }
    }

    private static func fencedCodeSpans(in text: NSString, activeLocation: Int?, into spans: inout [MarkdownStyleSpan]) -> [NSRange] {
        var codeRanges: [NSRange] = []
        var isInCodeBlock = false
        var blockStart: Int?
        var blockFenceRanges: [NSRange] = []
        var blockContentRanges: [NSRange] = []

        for lineRange in lineRanges(in: text) {
            let line = text.substring(with: lineRange)
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let isFence = trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~")

            if isFence {
                if isInCodeBlock, let start = blockStart {
                    blockFenceRanges.append(lineRange)
                    let blockRange = NSRange(location: start, length: NSMaxRange(lineRange) - start)
                    codeRanges.append(blockRange)
                    appendCodeBlockSpans(
                        fenceRanges: blockFenceRanges,
                        contentRanges: blockContentRanges,
                        blockRange: blockRange,
                        activeLocation: activeLocation,
                        into: &spans
                    )
                    blockStart = nil
                    isInCodeBlock = false
                    blockFenceRanges = []
                    blockContentRanges = []
                } else {
                    blockStart = lineRange.location
                    isInCodeBlock = true
                    blockFenceRanges = [lineRange]
                    blockContentRanges = []
                }
                continue
            }

            if isInCodeBlock {
                blockContentRanges.append(lineRange)
            }
        }

        if isInCodeBlock, let start = blockStart {
            let blockRange = NSRange(location: start, length: text.length - start)
            codeRanges.append(blockRange)
            appendCodeBlockSpans(
                fenceRanges: blockFenceRanges,
                contentRanges: blockContentRanges,
                blockRange: blockRange,
                activeLocation: activeLocation,
                into: &spans
            )
        }

        return codeRanges
    }

    private static func formulaBlockSpans(in text: NSString, activeLocation: Int?, into spans: inout [MarkdownStyleSpan]) -> [NSRange] {
        var formulaRanges: [NSRange] = []
        var isInFormulaBlock = false
        var blockStart: Int?
        var blockFenceRanges: [NSRange] = []
        var blockContentRanges: [NSRange] = []

        for lineRange in lineRanges(in: text) {
            let line = text.substring(with: lineRange)
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let isFence = trimmed == "$$"

            if isFence {
                if isInFormulaBlock, let start = blockStart {
                    blockFenceRanges.append(lineRange)
                    let blockRange = NSRange(location: start, length: NSMaxRange(lineRange) - start)
                    formulaRanges.append(blockRange)
                    appendFormulaBlockSpans(
                        fenceRanges: blockFenceRanges,
                        contentRanges: blockContentRanges,
                        blockRange: blockRange,
                        activeLocation: activeLocation,
                        into: &spans
                    )
                    blockStart = nil
                    isInFormulaBlock = false
                    blockFenceRanges = []
                    blockContentRanges = []
                } else {
                    blockStart = lineRange.location
                    isInFormulaBlock = true
                    blockFenceRanges = [lineRange]
                    blockContentRanges = []
                }
                continue
            }

            if isInFormulaBlock {
                blockContentRanges.append(lineRange)
            }
        }

        if isInFormulaBlock, let start = blockStart {
            let blockRange = NSRange(location: start, length: text.length - start)
            formulaRanges.append(blockRange)
            appendFormulaBlockSpans(
                fenceRanges: blockFenceRanges,
                contentRanges: blockContentRanges,
                blockRange: blockRange,
                activeLocation: activeLocation,
                into: &spans
            )
        }

        return formulaRanges
    }

    private static func appendCodeBlockSpans(
        fenceRanges: [NSRange],
        contentRanges: [NSRange],
        blockRange: NSRange,
        activeLocation: Int?,
        into spans: inout [MarkdownStyleSpan]
    ) {
        let isActive = activeLocation.map { containsInsertionLocation($0, in: blockRange) } ?? false
        let fenceKind: MarkdownStyleKind = isActive ? .codeBlockFence : .markdownDelimiter

        spans.append(MarkdownStyleSpan(kind: .blockBackground, range: blockRange))
        for fenceRange in fenceRanges {
            spans.append(MarkdownStyleSpan(kind: fenceKind, range: fenceRange))
        }
        for contentRange in contentRanges {
            spans.append(MarkdownStyleSpan(kind: .codeBlock, range: contentRange))
        }
    }

    private static func appendFormulaBlockSpans(
        fenceRanges: [NSRange],
        contentRanges: [NSRange],
        blockRange: NSRange,
        activeLocation: Int?,
        into spans: inout [MarkdownStyleSpan]
    ) {
        let isActive = activeLocation.map { containsInsertionLocation($0, in: blockRange) } ?? false
        let fenceKind: MarkdownStyleKind = isActive ? .formulaBlockFence : .markdownDelimiter

        spans.append(MarkdownStyleSpan(kind: .blockBackground, range: blockRange))
        for fenceRange in fenceRanges {
            spans.append(MarkdownStyleSpan(kind: fenceKind, range: fenceRange))
        }
        for contentRange in contentRanges {
            spans.append(MarkdownStyleSpan(kind: .formulaBlock, range: contentRange))
        }
    }

    private static func headingSpans(in text: NSString, lineRange: NSRange) -> [MarkdownStyleSpan] {
        let line = text.substring(with: lineRange) as NSString
        var level = 0

        while level < min(6, line.length),
              line.character(at: level) == Character("#").utf16.first {
            level += 1
        }

        guard level > 0,
              line.length > level,
              CharacterSet.whitespaces.contains(UnicodeScalar(line.character(at: level)) ?? " ") else {
            return []
        }

        return [
            MarkdownStyleSpan(kind: .headingLine(level: level), range: lineRange),
            MarkdownStyleSpan(kind: .markdownDelimiter, range: NSRange(location: lineRange.location, length: level))
        ]
    }

    private static func blockquoteSpans(in text: NSString, lineRange: NSRange) -> [MarkdownStyleSpan] {
        let line = text.substring(with: lineRange) as NSString
        let firstContentIndex = firstNonWhitespaceIndex(in: line)

        guard firstContentIndex < line.length,
              line.character(at: firstContentIndex) == Character(">").utf16.first else {
            return []
        }

        let markerRange = NSRange(location: lineRange.location + firstContentIndex, length: 1)
        var spaceRange: NSRange?
        if firstContentIndex + 1 < line.length,
           CharacterSet.whitespaces.contains(UnicodeScalar(line.character(at: firstContentIndex + 1)) ?? " ") {
            spaceRange = NSRange(location: lineRange.location + firstContentIndex + 1, length: 1)
        }

        var spans = [
            MarkdownStyleSpan(kind: .blockquoteLine, range: lineRange),
            MarkdownStyleSpan(kind: .blockquoteMarker, range: markerRange)
        ]
        if let spaceRange {
            spans.append(MarkdownStyleSpan(kind: .markdownDelimiter, range: spaceRange))
        }
        return spans
    }

    private static func listSpans(in text: NSString, lineRange: NSRange) -> [MarkdownStyleSpan] {
        let line = text.substring(with: lineRange) as NSString
        let index = firstNonWhitespaceIndex(in: line)

        guard index < line.length else { return [] }

        let absoluteIndex = lineRange.location + index
        let lineString = line as String
        let remainingRange = NSRange(location: index, length: line.length - index)

        if let taskMatch = firstRegexMatch("([-*+])\\s+\\[([ xX])\\]\\s+", in: lineString, range: remainingRange),
           taskMatch.range.location == index {
            let checkmark = line.substring(with: taskMatch.range(at: 2))
            let hiddenStart = absoluteIndex + 1
            let hiddenLength = max(taskMatch.range.length - 2, 0)
            return [
                MarkdownStyleSpan(kind: .taskListMarker(isChecked: checkmark.lowercased() == "x"), range: NSRange(location: absoluteIndex, length: 1)),
                MarkdownStyleSpan(kind: .markdownDelimiter, range: NSRange(location: hiddenStart, length: hiddenLength))
            ]
        }

        if let orderedMatch = firstRegexMatch("\\d+[.)]\\s+", in: lineString, range: remainingRange),
           orderedMatch.range.location == index {
            return [
                MarkdownStyleSpan(kind: .orderedListMarker, range: NSRange(location: absoluteIndex, length: orderedMatch.range.length - 1))
            ]
        }

        guard index < line.length,
              let scalar = UnicodeScalar(line.character(at: index)),
              ["-", "*", "+"].contains(String(scalar)),
              index + 1 < line.length,
              CharacterSet.whitespaces.contains(UnicodeScalar(line.character(at: index + 1)) ?? " ") else {
            return []
        }

        return [
            MarkdownStyleSpan(kind: .unorderedListMarker, range: NSRange(location: absoluteIndex, length: 1))
        ]
    }

    private static func horizontalRuleSpans(in text: NSString, lineRange: NSRange) -> [MarkdownStyleSpan] {
        let line = text.substring(with: lineRange)
        let trimmed = line.trimmingCharacters(in: .whitespaces)

        guard trimmed.count >= 3,
              Set(trimmed).count == 1,
              ["-", "*", "_"].contains(trimmed.first.map(String.init) ?? "") else {
            return []
        }

        return [
            MarkdownStyleSpan(kind: .horizontalRule, range: NSRange(location: lineRange.location, length: 1)),
            MarkdownStyleSpan(kind: .markdownDelimiter, range: NSRange(location: lineRange.location + 1, length: max(lineRange.length - 1, 0)))
        ]
    }

    private static func inlineSpans(
        in text: NSString,
        fullRange: NSRange,
        excludedRanges: [NSRange]
    ) -> [MarkdownStyleSpan] {
        var spans: [MarkdownStyleSpan] = []

        appendLinkSpans(to: &spans, in: text, fullRange: fullRange, excludedRanges: excludedRanges)
        appendDelimitedInlineSpans(
            to: &spans,
            in: text,
            fullRange: fullRange,
            excludedRanges: excludedRanges,
            pattern: "\\*\\*([^*\\n]+?)\\*\\*|__([^_\\n]+?)__",
            kind: .strongText,
            delimiterLength: 2
        )
        appendDelimitedInlineSpans(
            to: &spans,
            in: text,
            fullRange: fullRange,
            excludedRanges: excludedRanges,
            pattern: "~~([^~\\n]+?)~~",
            kind: .strikethroughText,
            delimiterLength: 2
        )
        appendDelimitedInlineSpans(
            to: &spans,
            in: text,
            fullRange: fullRange,
            excludedRanges: excludedRanges,
            pattern: "(?<!\\*)\\*([^*\\n]+?)\\*(?!\\*)|(?<!_)_([^_\\n]+?)_(?!_)",
            kind: .emphasisText,
            delimiterLength: 1
        )

        return spans
    }

    private static func appendLinkSpans(
        to spans: inout [MarkdownStyleSpan],
        in text: NSString,
        fullRange: NSRange,
        excludedRanges: [NSRange]
    ) {
        let matches = regexMatches("!?\\[([^\\]\\n]+)\\]\\(([^)\\n]+)\\)", in: text, range: fullRange)

        for match in matches where !excludedRanges.contains(where: { intersects($0, match.range) }) {
            let isImage = text.substring(with: NSRange(location: match.range.location, length: 1)) == "!"
            let textRange = match.range(at: 1)
            let destinationRange = match.range(at: 2)
            let openLength = isImage ? 2 : 1

            spans.append(MarkdownStyleSpan(kind: isImage ? .imageAlt : .linkText, range: textRange))
            spans.append(MarkdownStyleSpan(kind: .markdownDelimiter, range: NSRange(location: match.range.location, length: openLength)))
            spans.append(MarkdownStyleSpan(
                kind: .markdownDelimiter,
                range: NSRange(location: NSMaxRange(textRange), length: destinationRange.location - NSMaxRange(textRange))
            ))
            spans.append(MarkdownStyleSpan(kind: .markdownDelimiter, range: destinationRange))
            spans.append(MarkdownStyleSpan(kind: .markdownDelimiter, range: NSRange(location: NSMaxRange(match.range) - 1, length: 1)))
        }
    }

    private static func appendDelimitedInlineSpans(
        to spans: inout [MarkdownStyleSpan],
        in text: NSString,
        fullRange: NSRange,
        excludedRanges: [NSRange],
        pattern: String,
        kind: MarkdownStyleKind,
        delimiterLength: Int
    ) {
        let matches = regexMatches(pattern, in: text, range: fullRange)

        for match in matches where !excludedRanges.contains(where: { intersects($0, match.range) }) {
            let innerRange = firstCaptureRange(in: match)
            guard innerRange.location != NSNotFound else { continue }

            spans.append(MarkdownStyleSpan(kind: kind, range: innerRange))
            spans.append(MarkdownStyleSpan(kind: .markdownDelimiter, range: NSRange(location: match.range.location, length: delimiterLength)))
            spans.append(MarkdownStyleSpan(kind: .markdownDelimiter, range: NSRange(location: NSMaxRange(match.range) - delimiterLength, length: delimiterLength)))
        }
    }

    private static func lineRanges(in text: NSString) -> [NSRange] {
        var ranges: [NSRange] = []
        text.enumerateSubstrings(
            in: NSRange(location: 0, length: text.length),
            options: [.byLines, .substringNotRequired]
        ) { _, range, _, _ in
            ranges.append(range)
        }
        return ranges
    }

    private static func regexMatches(_ pattern: String, in text: NSString, range: NSRange) -> [NSTextCheckingResult] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        return regex.matches(in: text as String, range: range)
    }

    private static func firstRegexMatch(_ pattern: String, in text: String, range: NSRange) -> NSTextCheckingResult? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        return regex.firstMatch(in: text, range: range)
    }

    private static func firstCaptureRange(in match: NSTextCheckingResult) -> NSRange {
        for index in 1..<match.numberOfRanges {
            let range = match.range(at: index)
            if range.location != NSNotFound {
                return range
            }
        }
        return NSRange(location: NSNotFound, length: 0)
    }

    private static func firstNonWhitespaceIndex(in text: NSString) -> Int {
        var index = 0
        while index < text.length,
              CharacterSet.whitespaces.contains(UnicodeScalar(text.character(at: index)) ?? " ") {
            index += 1
        }
        return index
    }

    private static func containsInsertionLocation(_ location: Int, in range: NSRange) -> Bool {
        guard range.length > 0 else { return false }
        return location >= range.location && location <= NSMaxRange(range)
    }

    private static func intersects(_ first: NSRange, _ second: NSRange) -> Bool {
        NSIntersectionRange(first, second).length > 0
    }
}

enum MarkdownTextStyler {
    static func apply(to textView: NSTextView, glyphHider: MarkdownGlyphHider? = nil) {
        guard !textView.hasMarkedText(), let textStorage = textView.textStorage else {
            updateTypingAttributes(for: textView)
            return
        }

        let nsText = textView.string as NSString
        let fullRange = NSRange(location: 0, length: nsText.length)
        guard fullRange.length > 0 else {
            glyphHider?.update(hiddenRanges: [], blockBackgroundRanges: [])
            updateTypingAttributes(for: textView)
            return
        }

        let selectedRanges = textView.selectedRanges
        let selectedLocation = selectedRanges.first?.rangeValue.location ?? textView.selectedRange().location
        let spans = MarkdownStyleResolver.spans(in: textView.string, activeLocation: selectedLocation)
        let hiddenRanges = spans.compactMap { span -> NSRange? in
            span.kind == .markdownDelimiter ? span.range : nil
        }
        let blockBackgroundRanges = spans.compactMap { span -> NSRange? in
            isBlockBackgroundStyle(span.kind) ? span.range : nil
        }
        glyphHider?.update(hiddenRanges: hiddenRanges, blockBackgroundRanges: blockBackgroundRanges)

        textStorage.beginEditing()
        textStorage.setAttributes(baseAttributes(), range: fullRange)
        for span in spans where NSMaxRange(span.range) <= textStorage.length {
            textStorage.addAttributes(attributes(for: span.kind), range: span.range)
        }
        textStorage.endEditing()
        textView.layoutManager?.invalidateGlyphs(forCharacterRange: fullRange, changeInLength: 0, actualCharacterRange: nil)
        textView.layoutManager?.invalidateLayout(forCharacterRange: fullRange, actualCharacterRange: nil)

        textView.selectedRanges = selectedRanges
        updateTypingAttributes(for: textView)
    }

    static func updateTypingAttributes(for textView: NSTextView) {
        let selectedLocation = textView.selectedRanges.first?.rangeValue.location
            ?? textView.selectedRange().location
        textView.typingAttributes = typingAttributes(in: textView.string, at: selectedLocation)
    }

    private static func baseAttributes() -> [NSAttributedString.Key: Any] {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 2
        paragraph.paragraphSpacing = 4

        return [
            .font: NSFont.systemFont(ofSize: 15),
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: paragraph
        ]
    }

    private static func attributes(for kind: MarkdownStyleKind) -> [NSAttributedString.Key: Any] {
        switch kind {
        case let .headingLine(level):
            return [
                .font: NSFont.systemFont(ofSize: headingFontSize(for: level), weight: .semibold),
                .foregroundColor: NSColor.labelColor
            ]
        case .strongText:
            return [
                .font: NSFont.systemFont(ofSize: 15, weight: .semibold),
                .foregroundColor: NSColor.labelColor
            ]
        case .emphasisText:
            let font = NSFont.systemFont(ofSize: 15)
            let italicFont = NSFontManager.shared.convert(font, toHaveTrait: .italicFontMask)
            return [
                .font: italicFont,
                .foregroundColor: NSColor.labelColor
            ]
        case .strikethroughText:
            return [
                .font: NSFont.systemFont(ofSize: 15),
                .foregroundColor: NSColor.labelColor,
                .strikethroughStyle: NSUnderlineStyle.single.rawValue
            ]
        case .inlineCode:
            return [
                .font: NSFont.monospacedSystemFont(ofSize: 14, weight: .regular),
                .foregroundColor: NSColor.labelColor,
                .backgroundColor: NSColor.textColor.withAlphaComponent(0.08)
            ]
        case .inlineFormula:
            return [
                .font: NSFont.monospacedSystemFont(ofSize: 14, weight: .regular),
                .foregroundColor: NSColor.labelColor,
                .backgroundColor: inlineFormulaBackgroundColor()
            ]
        case .blockBackground:
            return [:]
        case .codeBlock:
            let paragraph = NSMutableParagraphStyle()
            paragraph.lineSpacing = 2
            paragraph.paragraphSpacing = 2
            paragraph.firstLineHeadIndent = blockContentIndent
            paragraph.headIndent = blockContentIndent
            paragraph.tailIndent = -blockContentIndent
            return [
                .font: NSFont.monospacedSystemFont(ofSize: 14, weight: .regular),
                .foregroundColor: NSColor.labelColor,
                .paragraphStyle: paragraph
            ]
        case .formulaBlock:
            let paragraph = NSMutableParagraphStyle()
            paragraph.lineSpacing = 2
            paragraph.paragraphSpacing = 2
            paragraph.firstLineHeadIndent = blockContentIndent
            paragraph.headIndent = blockContentIndent
            paragraph.tailIndent = -blockContentIndent
            return [
                .font: NSFont.monospacedSystemFont(ofSize: 14, weight: .regular),
                .foregroundColor: NSColor.labelColor,
                .paragraphStyle: paragraph
            ]
        case .linkText:
            return [
                .font: NSFont.systemFont(ofSize: 15),
                .foregroundColor: NSColor.linkColor,
                .underlineStyle: NSUnderlineStyle.single.rawValue
            ]
        case .imageAlt:
            return [
                .font: NSFont.systemFont(ofSize: 15, weight: .medium),
                .foregroundColor: NSColor.secondaryLabelColor
            ]
        case .blockquoteLine:
            let paragraph = NSMutableParagraphStyle()
            paragraph.lineSpacing = 2
            paragraph.paragraphSpacing = 4
            paragraph.firstLineHeadIndent = 6
            paragraph.headIndent = 6
            return [
                .font: NSFont.systemFont(ofSize: 15),
                .foregroundColor: NSColor.secondaryLabelColor,
                .backgroundColor: NSColor.separatorColor.withAlphaComponent(0.12),
                .paragraphStyle: paragraph
            ]
        case .blockquoteMarker:
            let font = NSFont.systemFont(ofSize: 17, weight: .heavy)
            var attributes: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: markerColor()
            ]
            attributes[.glyphInfo] = NSGlyphInfo(glyphName: "bar", for: font, baseString: ">")
            return attributes
        case .unorderedListMarker:
            let font = NSFont.systemFont(ofSize: 15, weight: .semibold)
            var attributes: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: markerColor()
            ]
            attributes[.glyphInfo] = NSGlyphInfo(glyphName: "bullet", for: font, baseString: "-")
            return attributes
        case .orderedListMarker:
            return [
                .font: NSFont.systemFont(ofSize: 15, weight: .semibold),
                .foregroundColor: markerColor()
            ]
        case let .taskListMarker(isChecked):
            let font = NSFont.systemFont(ofSize: 15, weight: .regular)
            let glyphName = isChecked ? "uni2611" : "uni25A1"
            var attributes: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: markerColor()
            ]
            attributes[.glyphInfo] = NSGlyphInfo(glyphName: glyphName, for: font, baseString: "-")
            return attributes
        case .horizontalRule:
            let font = NSFont.systemFont(ofSize: 15, weight: .regular)
            var attributes: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: NSColor.separatorColor
            ]
            attributes[.glyphInfo] = NSGlyphInfo(glyphName: "emdash", for: font, baseString: "-")
            return attributes
        case .codeBlockFence:
            return [
                .font: NSFont.monospacedSystemFont(ofSize: 14, weight: .regular),
                .foregroundColor: NSColor.secondaryLabelColor
            ]
        case .formulaBlockFence:
            return [
                .font: NSFont.monospacedSystemFont(ofSize: 14, weight: .regular),
                .foregroundColor: NSColor.secondaryLabelColor
            ]
        case .markdownDelimiter:
            return [
                .foregroundColor: NSColor.secondaryLabelColor
            ]
        }
    }

    static func fullBlockBackgroundColor() -> NSColor {
        NSColor(name: nil) { appearance in
            let match = appearance.bestMatch(from: [.darkAqua, .aqua])
            let alpha: CGFloat = match == .darkAqua ? 0.08 : 0.06
            return NSColor.textColor.withAlphaComponent(alpha)
        }
    }

    static let blockBackgroundCornerRadius: CGFloat = 12
    static let blockBackgroundHorizontalInset: CGFloat = 4
    static let blockBackgroundVerticalPadding: CGFloat = 10
    private static let blockContentIndent: CGFloat = 24

    private static func inlineFormulaBackgroundColor() -> NSColor {
        NSColor.textColor.withAlphaComponent(0.08)
    }

    private static func markerColor() -> NSColor {
        NSColor.secondaryLabelColor
    }

    private static func isBlockBackgroundStyle(_ kind: MarkdownStyleKind) -> Bool {
        switch kind {
        case .blockBackground:
            return true
        default:
            return false
        }
    }

    private static func headingFontSize(for level: Int) -> CGFloat {
        switch level {
        case 1:
            return 24
        case 2:
            return 20
        default:
            return 17
        }
    }

    private static func typingAttributes(in text: String, at insertionLocation: Int) -> [NSAttributedString.Key: Any] {
        let textLength = (text as NSString).length
        let location = min(max(insertionLocation, 0), textLength)

        for span in MarkdownStyleResolver.spans(in: text) where isLineTypingStyle(span.kind) {
            guard containsInsertionLocation(location, in: span.range) else { continue }
            return baseAttributes().merging(attributes(for: span.kind)) { _, styledValue in styledValue }
        }

        return baseAttributes()
    }

    private static func isLineTypingStyle(_ kind: MarkdownStyleKind) -> Bool {
        switch kind {
        case .headingLine(_), .codeBlock, .formulaBlock, .blockquoteLine:
            return true
        default:
            return false
        }
    }

    private static func containsInsertionLocation(_ location: Int, in range: NSRange) -> Bool {
        guard range.length > 0 else { return false }
        return location >= range.location && location <= NSMaxRange(range)
    }
}

final class MarkdownGlyphHider: NSObject, NSLayoutManagerDelegate {
    private var hiddenCharacterIndexes = Set<Int>()
    private var blockBackgroundRanges: [NSRange] = []

    func update(hiddenRanges: [NSRange], blockBackgroundRanges: [NSRange]) {
        hiddenCharacterIndexes = Set(hiddenRanges.flatMap { range in
            range.location..<(range.location + range.length)
        })
        self.blockBackgroundRanges = Self.mergedRanges(blockBackgroundRanges)
    }

    func isHiddenCharacter(at index: Int) -> Bool {
        hiddenCharacterIndexes.contains(index)
    }

    func isBlockBackgroundCharacter(at index: Int) -> Bool {
        blockBackgroundRanges.contains { NSLocationInRange(index, $0) }
    }

    func layoutManager(
        _ layoutManager: NSLayoutManager,
        drawBackgroundForGlyphRange glyphsToShow: NSRange,
        at origin: NSPoint
    ) {
        guard !blockBackgroundRanges.isEmpty else { return }
        MarkdownTextStyler.fullBlockBackgroundColor().setFill()

        for characterRange in blockBackgroundRanges {
            var effectiveCharacterRange = NSRange(location: 0, length: 0)
            let blockGlyphRange = layoutManager.glyphRange(
                forCharacterRange: characterRange,
                actualCharacterRange: &effectiveCharacterRange
            )
            let visibleGlyphRange = NSIntersectionRange(blockGlyphRange, glyphsToShow)
            guard visibleGlyphRange.length > 0 else { continue }

            if let rect = backgroundRect(
                for: visibleGlyphRange,
                layoutManager: layoutManager,
                origin: origin
            ) {
                NSBezierPath(
                    roundedRect: rect,
                    xRadius: MarkdownTextStyler.blockBackgroundCornerRadius,
                    yRadius: MarkdownTextStyler.blockBackgroundCornerRadius
                ).fill()
            }
        }
    }

    private func backgroundRect(
        for glyphRange: NSRange,
        layoutManager: NSLayoutManager,
        origin: NSPoint
    ) -> NSRect? {
        var unionRect: NSRect?

        layoutManager.enumerateLineFragments(forGlyphRange: glyphRange) { lineRect, _, textContainer, _, _ in
            let fragmentPadding = textContainer.lineFragmentPadding
            let horizontalInset = MarkdownTextStyler.blockBackgroundHorizontalInset
            let rect = NSRect(
                x: origin.x + lineRect.origin.x + fragmentPadding + horizontalInset,
                y: origin.y + lineRect.origin.y,
                width: max(lineRect.width - fragmentPadding * 2 - horizontalInset * 2, 0),
                height: lineRect.height
            )
            unionRect = unionRect.map { NSUnionRect($0, rect) } ?? rect
        }

        guard var rect = unionRect else { return nil }
        let verticalPadding = MarkdownTextStyler.blockBackgroundVerticalPadding
        rect.origin.y -= verticalPadding
        rect.size.height += verticalPadding * 2
        return rect
    }

    private static func mergedRanges(_ ranges: [NSRange]) -> [NSRange] {
        let sortedRanges = ranges
            .filter { $0.location != NSNotFound && $0.length > 0 }
            .sorted { $0.location < $1.location }
        guard var current = sortedRanges.first else { return [] }

        var merged: [NSRange] = []
        for range in sortedRanges.dropFirst() {
            if range.location <= NSMaxRange(current) + 1 {
                current = NSUnionRange(current, range)
            } else {
                merged.append(current)
                current = range
            }
        }
        merged.append(current)
        return merged
    }

    func layoutManager(
        _ layoutManager: NSLayoutManager,
        shouldGenerateGlyphs glyphs: UnsafePointer<CGGlyph>,
        properties props: UnsafePointer<NSLayoutManager.GlyphProperty>,
        characterIndexes charIndexes: UnsafePointer<Int>,
        font aFont: NSFont,
        forGlyphRange glyphRange: NSRange
    ) -> Int {
        let glyphCount = glyphRange.length
        guard glyphCount > 0 else { return 0 }

        var shouldOverride = false
        for offset in 0..<glyphCount where hiddenCharacterIndexes.contains(charIndexes[offset]) {
            shouldOverride = true
            break
        }

        guard shouldOverride else { return 0 }

        var newGlyphs = Array(UnsafeBufferPointer(start: glyphs, count: glyphCount))
        var newProperties = Array(UnsafeBufferPointer(start: props, count: glyphCount))
        var newCharacterIndexes = Array(UnsafeBufferPointer(start: charIndexes, count: glyphCount))

        for offset in 0..<glyphCount where hiddenCharacterIndexes.contains(newCharacterIndexes[offset]) {
            newGlyphs[offset] = 0
            newProperties[offset].insert(.null)
        }

        layoutManager.setGlyphs(
            &newGlyphs,
            properties: &newProperties,
            characterIndexes: &newCharacterIndexes,
            font: aFont,
            forGlyphRange: glyphRange
        )
        return glyphCount
    }
}

struct FloatingNoteView: View {
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

    private var shadowRadius: CGFloat {
        visualState.isDraggingFromStatusItem
            ? FloatingNoteLayout.dragShadowRadius(forDragProgress: visualState.dragProgress)
            : 18
    }

    private var shadowOpacity: CGFloat {
        visualState.isDraggingFromStatusItem
            ? 0.10 + 0.12 * min(max(visualState.dragProgress, 0), 1)
            : 0.18
    }

    private var statusText: String {
        switch store.saveState {
        case .saved:
            return "Saved"
        case .saving:
            return "Saving..."
        case .failed:
            return "Save failed"
        }
    }

    var body: some View {
        ZStack {
            noteBackground

            Image(systemName: "square.and.pencil")
                .font(.system(size: 14, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.secondary)
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
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .animation(.easeOut(duration: 0.08), value: visualState.dragProgress)
    }

    private var editorContent: some View {
        VStack(spacing: 0) {
            toolbar

            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(.regularMaterial)
                    .overlay {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(.white.opacity(0.24), lineWidth: 1)
                    }

                MarkdownTextView(text: $store.text, focusRequestID: focusController.requestID)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

                if store.text.isEmpty {
                    Text("写点什么...")
                        .font(.system(size: 15))
                        .foregroundStyle(.tertiary)
                        .padding(.top, 16)
                        .padding(.leading, 18)
                        .allowsHitTesting(false)
                }
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 10)
        }
    }

    private var noteBackground: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(.ultraThinMaterial)
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(.white.opacity(0.30), lineWidth: 1)
            }
            .shadow(color: .black.opacity(shadowOpacity), radius: shadowRadius, y: 6)
    }

    private var toolbar: some View {
        ZStack {
            WindowDragHandle()

            HStack(spacing: 8) {
                Button(action: closeNote) {
                    CloseGlassButton()
                }
                .buttonStyle(.plain)
                .help("Close")

                Text(statusText)
                    .foregroundStyle(statusColor)

                if case let .failed(message) = store.saveState {
                    Text(message)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 8)

                Text("\(store.text.count) 字")
                    .foregroundStyle(.secondary)

                Button(action: togglePin) {
                    Image(systemName: windowState.isPinned ? "pin.fill" : "pin")
                        .font(.system(size: 12, weight: .semibold))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(windowState.isPinned ? .primary : .secondary)
                        .frame(width: 26, height: 26)
                        .background {
                            Circle()
                                .fill(.ultraThinMaterial)
                                .overlay {
                                    Circle()
                                        .stroke(.white.opacity(windowState.isPinned ? 0.34 : 0.18), lineWidth: 1)
                                }
                        }
                }
                .buttonStyle(.plain)
                .help(windowState.isPinned ? "Unpin from front" : "Pin on top")

                Menu {
                    Button("Open Note File", action: openNoteFile)
                    Divider()
                    Button("Quit", action: quitApp)
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .imageScale(.medium)
                        .frame(width: 26, height: 26)
                }
                .menuStyle(.button)
                .buttonStyle(.plain)
                .help("More")
            }
            .padding(.horizontal, 12)
        }
        .font(.caption)
        .frame(height: 40)
        .background(.ultraThinMaterial)
    }

    private var statusColor: Color {
        switch store.saveState {
        case .saved:
            return .secondary
        case .saving:
            return .secondary
        case .failed:
            return .red
        }
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
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.secondary)
        }
        .frame(width: 24, height: 24)
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

struct MarkdownTextView: NSViewRepresentable {
    @Binding var text: String
    let focusRequestID: Int

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder

        let textView = NSTextView()
        textView.delegate = context.coordinator
        textView.string = text
        textView.isEditable = true
        textView.isSelectable = true
        textView.allowsUndo = true
        textView.isRichText = false
        textView.importsGraphics = false
        textView.usesAdaptiveColorMappingForDarkAppearance = true
        textView.font = .systemFont(ofSize: 15)
        textView.textColor = .labelColor
        textView.insertionPointColor = .controlAccentColor
        textView.backgroundColor = .clear
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 12, height: 12)
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isAutomaticDataDetectionEnabled = false
        textView.isContinuousSpellCheckingEnabled = false
        textView.usesFindPanel = true
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(
            width: scrollView.contentSize.width,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]

        scrollView.documentView = textView
        context.coordinator.textView = textView
        textView.layoutManager?.delegate = context.coordinator.glyphHider
        MarkdownTextStyler.apply(to: textView, glyphHider: context.coordinator.glyphHider)
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }

        if textView.string != text, !textView.hasMarkedText() {
            let selectedRanges = textView.selectedRanges
            textView.string = text
            textView.selectedRanges = selectedRanges
            MarkdownTextStyler.apply(to: textView, glyphHider: context.coordinator.glyphHider)
        }

        if context.coordinator.lastFocusRequestID != focusRequestID {
            context.coordinator.lastFocusRequestID = focusRequestID
            DispatchQueue.main.async {
                textView.window?.makeFirstResponder(textView)
            }
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        @Binding private var text: String
        weak var textView: NSTextView?
        let glyphHider = MarkdownGlyphHider()
        var lastFocusRequestID = 0

        init(text: Binding<String>) {
            _text = text
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            guard !textView.hasMarkedText() else {
                MarkdownTextStyler.updateTypingAttributes(for: textView)
                return
            }
            text = textView.string
            MarkdownTextStyler.apply(to: textView, glyphHider: glyphHider)
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            MarkdownTextStyler.updateTypingAttributes(for: textView)
        }

        func textView(
            _ textView: NSTextView,
            shouldChangeTextIn affectedCharRange: NSRange,
            replacementString: String?
        ) -> Bool {
            MarkdownTextStyler.updateTypingAttributes(for: textView)
            return true
        }
    }
}
