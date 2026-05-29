//
//  ContentView.swift
//  MenuBarMemo
//
//  Created by 丁泓景 on 2026/5/28.
//

import SwiftUI
import AppKit
import Combine
#if canImport(SwiftMath)
import SwiftMath
#endif

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
    case blockFenceDelimiter
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

struct MarkdownFormulaRenderSpan: Equatable {
    let sourceRange: NSRange
    let layoutRange: NSRange
    let latex: String
    let isBlock: Bool
}

struct MarkdownEditResult: Equatable {
    let text: String
    let selectedRange: NSRange
}

enum MarkdownCodeBlockEditing {
    static func expandOpeningFence(
        in text: String,
        affectedRange: NSRange,
        replacementString: String
    ) -> MarkdownEditResult? {
        guard replacementString == "`" || replacementString == "```" else { return nil }

        let nsText = text as NSString
        let location = min(max(affectedRange.location, 0), nsText.length)
        let lineRange = nsText.lineRange(for: NSRange(location: location, length: 0))
        let lineContentRange = contentRangeExcludingLineEnding(from: lineRange, in: nsText)
        guard affectedRange.location >= lineContentRange.location,
              NSMaxRange(affectedRange) <= NSMaxRange(lineContentRange) else {
            return nil
        }

        let lineText = NSMutableString(string: nsText.substring(with: lineContentRange))
        lineText.replaceCharacters(
            in: NSRange(location: affectedRange.location - lineContentRange.location, length: affectedRange.length),
            with: replacementString
        )
        guard lineText as String == "```" else { return nil }

        let block = "```\n\n```"
        let expandedText = nsText.replacingCharacters(in: lineContentRange, with: block)
        return MarkdownEditResult(
            text: expandedText,
            selectedRange: NSRange(location: lineContentRange.location + 4, length: 0)
        )
    }

    static func expandOpeningFormulaFence(
        in text: String,
        affectedRange: NSRange,
        replacementString: String
    ) -> MarkdownEditResult? {
        guard replacementString == "$" || replacementString == "$$" else { return nil }

        let nsText = text as NSString
        let location = min(max(affectedRange.location, 0), nsText.length)
        let lineRange = nsText.lineRange(for: NSRange(location: location, length: 0))
        let lineContentRange = contentRangeExcludingLineEnding(from: lineRange, in: nsText)
        guard affectedRange.location >= lineContentRange.location,
              NSMaxRange(affectedRange) <= NSMaxRange(lineContentRange) else {
            return nil
        }

        let lineText = NSMutableString(string: nsText.substring(with: lineContentRange))
        lineText.replaceCharacters(
            in: NSRange(location: affectedRange.location - lineContentRange.location, length: affectedRange.length),
            with: replacementString
        )
        guard lineText as String == "$$" else { return nil }

        let block = "$$\n\n$$"
        let expandedText = nsText.replacingCharacters(in: lineContentRange, with: block)
        return MarkdownEditResult(
            text: expandedText,
            selectedRange: NSRange(location: lineContentRange.location + 3, length: 0)
        )
    }

    static func exitCodeBlock(in text: String, selectedRange: NSRange) -> MarkdownEditResult? {
        let nsText = text as NSString
        let location = min(max(selectedRange.location, 0), nsText.length)
        guard let blockRange = fencedCodeBlockRange(containing: location, in: nsText) else {
            return nil
        }

        let blockEnd = NSMaxRange(blockRange)
        if blockHasClosingFence(in: nsText, blockRange: blockRange) {
            if blockEnd < nsText.length,
               CharacterSet.newlines.contains(UnicodeScalar(nsText.character(at: blockEnd)) ?? "\0") {
                return MarkdownEditResult(text: text, selectedRange: NSRange(location: blockEnd + 1, length: 0))
            }

            let newText = nsText.replacingCharacters(in: NSRange(location: blockEnd, length: 0), with: "\n")
            return MarkdownEditResult(text: newText, selectedRange: NSRange(location: blockEnd + 1, length: 0))
        }

        let closingText = "\n```\n"
        let newText = nsText.replacingCharacters(in: NSRange(location: blockEnd, length: 0), with: closingText)
        return MarkdownEditResult(
            text: newText,
            selectedRange: NSRange(location: blockEnd + (closingText as NSString).length, length: 0)
        )
    }

    static func exitCodeBlockOnBlankCodeLine(in text: String, selectedRange: NSRange) -> MarkdownEditResult? {
        guard selectedRange.length == 0 else { return nil }

        let nsText = text as NSString
        let location = min(max(selectedRange.location, 0), nsText.length)
        guard let blockRange = fencedCodeBlockRange(containing: location, in: nsText),
              let closingFenceRange = closingFenceLineRange(in: nsText, blockRange: blockRange) else {
            return nil
        }

        let currentLineFullRange = nsText.lineRange(for: NSRange(location: location, length: 0))
        let currentLineContentRange = contentRangeExcludingLineEnding(from: currentLineFullRange, in: nsText)
        guard currentLineContentRange.location > blockRange.location,
              currentLineContentRange.location < closingFenceRange.location else {
            return nil
        }

        let currentLine = nsText.substring(with: currentLineContentRange)
        guard currentLine.trimmingCharacters(in: .whitespaces).isEmpty,
              hasEarlierContentLine(in: nsText, blockRange: blockRange, before: currentLineContentRange.location) else {
            return nil
        }

        let textAfterRemovingBlankLine = nsText.replacingCharacters(in: currentLineFullRange, with: "")
        let removedLength = currentLineFullRange.length
        let shiftedClosingFenceLocation = closingFenceRange.location
            - (currentLineFullRange.location < closingFenceRange.location ? removedLength : 0)
        let result = textAfterRemovingBlankLine as NSString
        let closingLineFullRange = result.lineRange(
            for: NSRange(location: min(shiftedClosingFenceLocation, result.length), length: 0)
        )
        let closingLineContentRange = contentRangeExcludingLineEnding(from: closingLineFullRange, in: result)

        if NSMaxRange(closingLineFullRange) > NSMaxRange(closingLineContentRange) {
            return MarkdownEditResult(
                text: textAfterRemovingBlankLine,
                selectedRange: NSRange(location: NSMaxRange(closingLineFullRange), length: 0)
            )
        }

        let finalText = result.replacingCharacters(in: NSRange(location: NSMaxRange(closingLineFullRange), length: 0), with: "\n")
        return MarkdownEditResult(
            text: finalText,
            selectedRange: NSRange(location: NSMaxRange(closingLineFullRange) + 1, length: 0)
        )
    }

    static func exitFormulaBlockOnBlankFormulaLine(in text: String, selectedRange: NSRange) -> MarkdownEditResult? {
        guard selectedRange.length == 0 else { return nil }

        let nsText = text as NSString
        let location = min(max(selectedRange.location, 0), nsText.length)
        guard let blockRange = fencedFormulaBlockRange(containing: location, in: nsText),
              let closingFenceRange = closingFormulaFenceLineRange(in: nsText, blockRange: blockRange) else {
            return nil
        }

        let currentLineFullRange = nsText.lineRange(for: NSRange(location: location, length: 0))
        let currentLineContentRange = contentRangeExcludingLineEnding(from: currentLineFullRange, in: nsText)
        guard currentLineContentRange.location > blockRange.location,
              currentLineContentRange.location < closingFenceRange.location else {
            return nil
        }

        let currentLine = nsText.substring(with: currentLineContentRange)
        guard currentLine.trimmingCharacters(in: .whitespaces).isEmpty,
              hasEarlierFormulaContentLine(in: nsText, blockRange: blockRange, before: currentLineContentRange.location) else {
            return nil
        }

        let textAfterRemovingBlankLine = nsText.replacingCharacters(in: currentLineFullRange, with: "")
        let removedLength = currentLineFullRange.length
        let shiftedClosingFenceLocation = closingFenceRange.location
            - (currentLineFullRange.location < closingFenceRange.location ? removedLength : 0)
        let result = textAfterRemovingBlankLine as NSString
        let closingLineFullRange = result.lineRange(
            for: NSRange(location: min(shiftedClosingFenceLocation, result.length), length: 0)
        )
        let closingLineContentRange = contentRangeExcludingLineEnding(from: closingLineFullRange, in: result)

        if NSMaxRange(closingLineFullRange) > NSMaxRange(closingLineContentRange) {
            return MarkdownEditResult(
                text: textAfterRemovingBlankLine,
                selectedRange: NSRange(location: NSMaxRange(closingLineFullRange), length: 0)
            )
        }

        let finalText = result.replacingCharacters(in: NSRange(location: NSMaxRange(closingLineFullRange), length: 0), with: "\n")
        return MarkdownEditResult(
            text: finalText,
            selectedRange: NSRange(location: NSMaxRange(closingLineFullRange) + 1, length: 0)
        )
    }

    static func collapseEmptyCodeBlockOnBackspace(in text: String, selectedRange: NSRange) -> MarkdownEditResult? {
        guard selectedRange.length == 0 else { return nil }

        let nsText = text as NSString
        let location = min(max(selectedRange.location, 0), nsText.length)
        guard let blockRange = fencedCodeBlockRange(containing: location, in: nsText),
              let closingFenceRange = closingFenceLineRange(in: nsText, blockRange: blockRange),
              isEmptyCodeBlock(in: nsText, blockRange: blockRange, closingFenceRange: closingFenceRange),
              isInsideEmptyCodeContentLine(in: nsText, location: location, blockRange: blockRange, closingFenceRange: closingFenceRange) else {
            return nil
        }

        let removalRange = blockRemovalRange(in: nsText, blockRange: blockRange)
        let newText = nsText.replacingCharacters(in: removalRange, with: "")
        return MarkdownEditResult(
            text: newText,
            selectedRange: NSRange(location: blockRange.location, length: 0)
        )
    }

    static func collapseEmptyFormulaBlockOnBackspace(in text: String, selectedRange: NSRange) -> MarkdownEditResult? {
        guard selectedRange.length == 0 else { return nil }

        let nsText = text as NSString
        let location = min(max(selectedRange.location, 0), nsText.length)
        guard let blockRange = fencedFormulaBlockRange(containing: location, in: nsText),
              let closingFenceRange = closingFormulaFenceLineRange(in: nsText, blockRange: blockRange),
              isEmptyFormulaBlock(in: nsText, blockRange: blockRange, closingFenceRange: closingFenceRange),
              isInsideEmptyFormulaContentLine(in: nsText, location: location, blockRange: blockRange, closingFenceRange: closingFenceRange) else {
            return nil
        }

        let removalRange = blockRemovalRange(in: nsText, blockRange: blockRange)
        let newText = nsText.replacingCharacters(in: removalRange, with: "")
        return MarkdownEditResult(
            text: newText,
            selectedRange: NSRange(location: blockRange.location, length: 0)
        )
    }

    private static func blockHasClosingFence(in text: NSString, blockRange: NSRange) -> Bool {
        closingFenceLineRange(in: text, blockRange: blockRange) != nil
    }

    private static func closingFenceLineRange(in text: NSString, blockRange: NSRange) -> NSRange? {
        var closingLineRange: NSRange?
        for lineRange in MarkdownStyleResolver.lineRanges(in: text) where blockRangeContains(lineRange, blockRange: blockRange) {
            guard lineRange.location > blockRange.location,
                  isCodeFenceLine(text.substring(with: lineRange)) else {
                continue
            }
            closingLineRange = lineRange
        }
        return closingLineRange
    }

    private static func closingFormulaFenceLineRange(in text: NSString, blockRange: NSRange) -> NSRange? {
        var closingLineRange: NSRange?
        for lineRange in MarkdownStyleResolver.lineRanges(in: text) where blockRangeContains(lineRange, blockRange: blockRange) {
            guard lineRange.location > blockRange.location,
                  isFormulaFenceLine(text.substring(with: lineRange)) else {
                continue
            }
            closingLineRange = lineRange
        }
        return closingLineRange
    }

    private static func hasEarlierContentLine(in text: NSString, blockRange: NSRange, before location: Int) -> Bool {
        for lineRange in MarkdownStyleResolver.lineRanges(in: text) where blockRangeContains(lineRange, blockRange: blockRange) {
            guard lineRange.location > blockRange.location,
                  lineRange.location < location,
                  !isCodeFenceLine(text.substring(with: lineRange)) else {
                continue
            }
            return true
        }
        return false
    }

    private static func hasEarlierFormulaContentLine(in text: NSString, blockRange: NSRange, before location: Int) -> Bool {
        for lineRange in MarkdownStyleResolver.lineRanges(in: text) where blockRangeContains(lineRange, blockRange: blockRange) {
            guard lineRange.location > blockRange.location,
                  lineRange.location < location,
                  !isFormulaFenceLine(text.substring(with: lineRange)) else {
                continue
            }
            return true
        }
        return false
    }

    private static func isEmptyCodeBlock(in text: NSString, blockRange: NSRange, closingFenceRange: NSRange) -> Bool {
        for lineRange in MarkdownStyleResolver.lineRanges(in: text) where blockRangeContains(lineRange, blockRange: blockRange) {
            guard lineRange.location > blockRange.location,
                  lineRange.location < closingFenceRange.location,
                  !isCodeFenceLine(text.substring(with: lineRange)) else {
                continue
            }
            if !text.substring(with: lineRange).trimmingCharacters(in: .whitespaces).isEmpty {
                return false
            }
        }
        return true
    }

    private static func isEmptyFormulaBlock(in text: NSString, blockRange: NSRange, closingFenceRange: NSRange) -> Bool {
        for lineRange in MarkdownStyleResolver.lineRanges(in: text) where blockRangeContains(lineRange, blockRange: blockRange) {
            guard lineRange.location > blockRange.location,
                  lineRange.location < closingFenceRange.location,
                  !isFormulaFenceLine(text.substring(with: lineRange)) else {
                continue
            }
            if !text.substring(with: lineRange).trimmingCharacters(in: .whitespaces).isEmpty {
                return false
            }
        }
        return true
    }

    private static func isInsideEmptyCodeContentLine(
        in text: NSString,
        location: Int,
        blockRange: NSRange,
        closingFenceRange: NSRange
    ) -> Bool {
        let lineRange = text.lineRange(for: NSRange(location: location, length: 0))
        let lineContentRange = contentRangeExcludingLineEnding(from: lineRange, in: text)
        guard lineContentRange.location > blockRange.location,
              lineContentRange.location < closingFenceRange.location else {
            return false
        }
        return text.substring(with: lineContentRange).trimmingCharacters(in: .whitespaces).isEmpty
    }

    private static func isInsideEmptyFormulaContentLine(
        in text: NSString,
        location: Int,
        blockRange: NSRange,
        closingFenceRange: NSRange
    ) -> Bool {
        let lineRange = text.lineRange(for: NSRange(location: location, length: 0))
        let lineContentRange = contentRangeExcludingLineEnding(from: lineRange, in: text)
        guard lineContentRange.location > blockRange.location,
              lineContentRange.location < closingFenceRange.location else {
            return false
        }
        return text.substring(with: lineContentRange).trimmingCharacters(in: .whitespaces).isEmpty
    }

    private static func blockRemovalRange(in text: NSString, blockRange: NSRange) -> NSRange {
        let blockEnd = NSMaxRange(blockRange)
        if blockEnd < text.length,
           CharacterSet.newlines.contains(UnicodeScalar(text.character(at: blockEnd)) ?? "\0") {
            return NSRange(location: blockRange.location, length: blockRange.length + 1)
        }
        return blockRange
    }

    private static func blockRangeContains(_ lineRange: NSRange, blockRange: NSRange) -> Bool {
        lineRange.location >= blockRange.location && NSMaxRange(lineRange) <= NSMaxRange(blockRange)
    }

    private static func isCodeFenceLine(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        return trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~")
    }

    private static func isFormulaFenceLine(_ line: String) -> Bool {
        line.trimmingCharacters(in: .whitespaces) == "$$"
    }

    private static func fencedCodeBlockRange(containing location: Int, in text: NSString) -> NSRange? {
        var blockStart: Int?

        for lineRange in MarkdownStyleResolver.lineRanges(in: text) {
            let line = text.substring(with: lineRange)
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let isFence = trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~")

            guard isFence else { continue }

            if let start = blockStart {
                let blockRange = NSRange(location: start, length: NSMaxRange(lineRange) - start)
                if location >= blockRange.location && location <= NSMaxRange(blockRange) {
                    return blockRange
                }
                blockStart = nil
            } else {
                blockStart = lineRange.location
            }
        }

        if let start = blockStart {
            let blockRange = NSRange(location: start, length: text.length - start)
            if location >= blockRange.location && location <= NSMaxRange(blockRange) {
                return blockRange
            }
        }

        return nil
    }

    private static func fencedFormulaBlockRange(containing location: Int, in text: NSString) -> NSRange? {
        var blockStart: Int?

        for lineRange in MarkdownStyleResolver.lineRanges(in: text) {
            guard isFormulaFenceLine(text.substring(with: lineRange)) else { continue }

            if let start = blockStart {
                let blockRange = NSRange(location: start, length: NSMaxRange(lineRange) - start)
                if location >= blockRange.location && location <= NSMaxRange(blockRange) {
                    return blockRange
                }
                blockStart = nil
            } else {
                blockStart = lineRange.location
            }
        }

        return nil
    }

    private static func contentRangeExcludingLineEnding(from lineRange: NSRange, in text: NSString) -> NSRange {
        var end = min(NSMaxRange(lineRange), text.length)
        while end > lineRange.location,
              CharacterSet.newlines.contains(UnicodeScalar(text.character(at: end - 1)) ?? "\0") {
            end -= 1
        }
        return NSRange(location: lineRange.location, length: end - lineRange.location)
    }
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
            let isActive = activeLocation.map { containsInsertionLocation($0, in: match.range) } ?? false
            guard isActive else {
                excludedInlineRanges.append(match.range)
                continue
            }

            let innerRange = match.range(at: 1)
            spans.append(MarkdownStyleSpan(kind: .inlineFormula, range: innerRange))
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

        return formulaRanges
    }

    private static func appendCodeBlockSpans(
        fenceRanges: [NSRange],
        contentRanges: [NSRange],
        blockRange: NSRange,
        activeLocation: Int?,
        into spans: inout [MarkdownStyleSpan]
    ) {
        let styledContentRanges = blockStyledContentRanges(contentRanges: contentRanges, blockRange: blockRange)
        spans.append(MarkdownStyleSpan(
            kind: .blockBackground,
            range: blockContentBackgroundRange(contentRanges: styledContentRanges, blockRange: blockRange)
        ))
        for fenceRange in fenceRanges {
            spans.append(MarkdownStyleSpan(kind: .blockFenceDelimiter, range: fenceRange))
        }
        for contentRange in styledContentRanges {
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
        let styledContentRanges = blockStyledContentRanges(contentRanges: contentRanges, blockRange: blockRange)
        spans.append(MarkdownStyleSpan(
            kind: .blockBackground,
            range: blockContentBackgroundRange(contentRanges: styledContentRanges, blockRange: blockRange)
        ))
        for fenceRange in fenceRanges {
            spans.append(MarkdownStyleSpan(kind: .blockFenceDelimiter, range: fenceRange))
        }
        for contentRange in styledContentRanges {
            spans.append(MarkdownStyleSpan(kind: .formulaBlock, range: contentRange))
        }
    }

    private static func blockStyledContentRanges(contentRanges: [NSRange], blockRange: NSRange) -> [NSRange] {
        contentRanges.map { range in
            guard range.length == 0, range.location < NSMaxRange(blockRange) else { return range }
            return NSRange(location: range.location, length: 1)
        }
    }

    private static func blockContentBackgroundRange(contentRanges: [NSRange], blockRange: NSRange) -> NSRange {
        guard let firstRange = contentRanges.first else { return blockRange }
        let start = firstRange.location
        let end = contentRanges.reduce(start) { max($0, NSMaxRange($1)) }
        if end > start {
            return NSRange(location: start, length: end - start)
        }
        if start < NSMaxRange(blockRange) {
            return NSRange(location: start, length: 1)
        }
        return NSRange(location: start, length: 0)
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

    static func lineRanges(in text: NSString) -> [NSRange] {
        var ranges: [NSRange] = []
        text.enumerateSubstrings(
            in: NSRange(location: 0, length: text.length),
            options: [.byLines, .substringNotRequired]
        ) { _, range, _, _ in
            ranges.append(range)
        }
        return ranges
    }

    static func regexMatches(_ pattern: String, in text: NSString, range: NSRange) -> [NSTextCheckingResult] {
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

enum MarkdownFormulaRenderResolver {
    static func renderSpans(in text: String, activeLocation: Int? = nil) -> [MarkdownFormulaRenderSpan] {
        let nsText = text as NSString
        let fullRange = NSRange(location: 0, length: nsText.length)
        guard fullRange.length > 0 else { return [] }

        let formulaBlocks = formulaBlockInfos(in: nsText)
        let codeBlockRanges = fencedCodeBlockRanges(in: nsText)
        var spans = formulaBlocks.compactMap { info -> MarkdownFormulaRenderSpan? in
            guard !isActive(activeLocation, in: info.sourceRange) else { return nil }
            let latex = info.contentRanges
                .map { nsText.substring(with: $0) }
                .joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !latex.isEmpty else { return nil }
            return MarkdownFormulaRenderSpan(
                sourceRange: info.sourceRange,
                layoutRange: info.layoutRange,
                latex: latex,
                isBlock: true
            )
        }

        let excludedRanges = codeBlockRanges + formulaBlocks.map(\.sourceRange)
        for match in MarkdownStyleResolver.regexMatches("(?<!\\$)\\$([^$\\n]+?)\\$(?!\\$)", in: nsText, range: fullRange) {
            guard !excludedRanges.contains(where: { intersects($0, match.range) }),
                  !isActive(activeLocation, in: match.range) else {
                continue
            }

            let latex = nsText.substring(with: match.range(at: 1)).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !latex.isEmpty else { continue }
            spans.append(MarkdownFormulaRenderSpan(
                sourceRange: match.range,
                layoutRange: match.range,
                latex: latex,
                isBlock: false
            ))
        }

        return spans.sorted { $0.sourceRange.location < $1.sourceRange.location }
    }

    private struct FormulaBlockInfo {
        let sourceRange: NSRange
        let layoutRange: NSRange
        let contentRanges: [NSRange]
    }

    private static func formulaBlockInfos(in text: NSString) -> [FormulaBlockInfo] {
        var infos: [FormulaBlockInfo] = []
        var blockStart: NSRange?
        var contentRanges: [NSRange] = []

        for lineRange in MarkdownStyleResolver.lineRanges(in: text) {
            let line = text.substring(with: lineRange)
            let isFence = line.trimmingCharacters(in: .whitespaces) == "$$"

            if isFence {
                if let start = blockStart {
                    let sourceRange = NSRange(location: start.location, length: NSMaxRange(lineRange) - start.location)
                    let layoutRange = blockContentBackgroundRange(contentRanges: contentRanges, blockRange: sourceRange)
                    infos.append(FormulaBlockInfo(
                        sourceRange: sourceRange,
                        layoutRange: layoutRange,
                        contentRanges: contentRanges
                    ))
                    blockStart = nil
                    contentRanges = []
                } else {
                    blockStart = lineRange
                    contentRanges = []
                }
                continue
            }

            if blockStart != nil {
                contentRanges.append(lineRange)
            }
        }

        return infos
    }

    private static func fencedCodeBlockRanges(in text: NSString) -> [NSRange] {
        var ranges: [NSRange] = []
        var blockStart: NSRange?

        for lineRange in MarkdownStyleResolver.lineRanges(in: text) {
            let line = text.substring(with: lineRange)
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let isFence = trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~")

            guard isFence else { continue }
            if let start = blockStart {
                ranges.append(NSRange(location: start.location, length: NSMaxRange(lineRange) - start.location))
                blockStart = nil
            } else {
                blockStart = lineRange
            }
        }

        return ranges
    }

    private static func blockContentBackgroundRange(contentRanges: [NSRange], blockRange: NSRange) -> NSRange {
        guard let firstRange = contentRanges.first else { return blockRange }
        let start = firstRange.location
        let end = contentRanges.reduce(start) { max($0, NSMaxRange($1)) }
        if end > start {
            return NSRange(location: start, length: end - start)
        }
        if start < NSMaxRange(blockRange) {
            return NSRange(location: start, length: 1)
        }
        return NSRange(location: start, length: 0)
    }

    private static func isActive(_ activeLocation: Int?, in range: NSRange) -> Bool {
        guard let activeLocation else { return false }
        return activeLocation >= range.location && activeLocation <= NSMaxRange(range)
    }

    private static func intersects(_ first: NSRange, _ second: NSRange) -> Bool {
        NSIntersectionRange(first, second).length > 0
    }
}

enum MarkdownTextStyler {
    static func apply(
        to textView: NSTextView,
        glyphHider: MarkdownLayoutManager? = nil,
        formulaOverlayController: MarkdownFormulaOverlayController? = nil
    ) {
        guard !textView.hasMarkedText(), let textStorage = textView.textStorage else {
            updateTypingAttributes(for: textView)
            return
        }

        let nsText = textView.string as NSString
        let fullRange = NSRange(location: 0, length: nsText.length)
        guard fullRange.length > 0 else {
            glyphHider?.update(hiddenRanges: [], blockBackgroundRanges: [])
            formulaOverlayController?.clear()
            updateTypingAttributes(for: textView)
            return
        }

        let selectedRanges = textView.selectedRanges
        let selectedLocation = selectedRanges.first?.rangeValue.location ?? textView.selectedRange().location
        let spans = MarkdownStyleResolver.spans(in: textView.string, activeLocation: selectedLocation)
        let formulaRenderSpans = MarkdownFormulaRenderResolver.renderSpans(
            in: textView.string,
            activeLocation: selectedLocation
        )
        let hiddenRanges = spans.compactMap { span -> NSRange? in
            isHiddenMarkdownStyle(span.kind) ? span.range : nil
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
        for span in formulaRenderSpans where NSMaxRange(span.sourceRange) <= textStorage.length {
            textStorage.addAttributes(formulaRenderSourceAttributes(), range: span.sourceRange)
        }
        textStorage.endEditing()
        textView.layoutManager?.invalidateGlyphs(forCharacterRange: fullRange, changeInLength: 0, actualCharacterRange: nil)
        textView.layoutManager?.invalidateLayout(forCharacterRange: fullRange, actualCharacterRange: nil)

        if !selectedRangesEqual(textView.selectedRanges, selectedRanges) {
            textView.selectedRanges = selectedRanges
        }
        formulaOverlayController?.update(in: textView, spans: formulaRenderSpans)
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

    private static func selectedRangesEqual(_ first: [NSValue], _ second: [NSValue]) -> Bool {
        guard first.count == second.count else { return false }
        return zip(first, second).allSatisfy { $0.rangeValue == $1.rangeValue }
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
            paragraph.minimumLineHeight = 38
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
        case .blockFenceDelimiter:
            let paragraph = NSMutableParagraphStyle()
            paragraph.lineSpacing = 0
            paragraph.paragraphSpacing = 0
            paragraph.minimumLineHeight = blockFenceSpacerHeight
            paragraph.maximumLineHeight = blockFenceSpacerHeight
            return [
                .font: NSFont.systemFont(ofSize: 0.1),
                .foregroundColor: NSColor.clear,
                .paragraphStyle: paragraph
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
    static let blockOuterVerticalSpacing: CGFloat = 8
    private static let blockFenceSpacerHeight = blockBackgroundVerticalPadding + blockOuterVerticalSpacing
    static let blockContentIndent: CGFloat = 24

    private static func inlineFormulaBackgroundColor() -> NSColor {
        NSColor.textColor.withAlphaComponent(0.08)
    }

    private static func formulaRenderSourceAttributes() -> [NSAttributedString.Key: Any] {
        [
            .foregroundColor: NSColor.clear,
            .backgroundColor: NSColor.clear
        ]
    }

    private static func markerColor() -> NSColor {
        NSColor.secondaryLabelColor
    }

    private static func isHiddenMarkdownStyle(_ kind: MarkdownStyleKind) -> Bool {
        switch kind {
        case .markdownDelimiter, .blockFenceDelimiter:
            return true
        default:
            return false
        }
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

final class MarkdownLayoutManager: NSLayoutManager, NSLayoutManagerDelegate {
    private var hiddenCharacterIndexes = Set<Int>()
    private var blockBackgroundRanges: [NSRange] = []

    override init() {
        super.init()
        delegate = self
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        delegate = self
    }

    func update(hiddenRanges: [NSRange], blockBackgroundRanges: [NSRange]) {
        hiddenCharacterIndexes = Set(hiddenRanges.flatMap { range in
            range.location..<(range.location + range.length)
        })
        self.blockBackgroundRanges = blockBackgroundRanges
            .filter { $0.location != NSNotFound && $0.length > 0 }
            .sorted { $0.location < $1.location }
    }

    func isHiddenCharacter(at index: Int) -> Bool {
        hiddenCharacterIndexes.contains(index)
    }

    func isBlockBackgroundCharacter(at index: Int) -> Bool {
        blockBackgroundRanges.contains { NSLocationInRange(index, $0) }
    }

    override func drawBackground(forGlyphRange glyphsToShow: NSRange, at origin: NSPoint) {
        drawBlockBackgrounds(forGlyphRange: glyphsToShow, at: origin)
        super.drawBackground(forGlyphRange: glyphsToShow, at: origin)
    }

    private func drawBlockBackgrounds(forGlyphRange glyphsToShow: NSRange, at origin: NSPoint) {
        guard !blockBackgroundRanges.isEmpty else { return }
        MarkdownTextStyler.fullBlockBackgroundColor().setFill()

        for rect in blockBackgroundRects(forGlyphRange: glyphsToShow, at: origin) {
            NSBezierPath(
                roundedRect: rect,
                xRadius: MarkdownTextStyler.blockBackgroundCornerRadius,
                yRadius: MarkdownTextStyler.blockBackgroundCornerRadius
            ).fill()
        }
    }

    func blockBackgroundRects(forGlyphRange glyphsToShow: NSRange, at origin: NSPoint) -> [NSRect] {
        guard !blockBackgroundRanges.isEmpty else { return [] }
        var rects: [NSRect] = []

        for characterRange in blockBackgroundRanges {
            var effectiveCharacterRange = NSRange(location: 0, length: 0)
            let blockGlyphRange = glyphRange(
                forCharacterRange: characterRange,
                actualCharacterRange: &effectiveCharacterRange
            )
            let visibleGlyphRange = NSIntersectionRange(blockGlyphRange, glyphsToShow)
            guard visibleGlyphRange.length > 0 else { continue }

            if let rect = backgroundRect(
                for: visibleGlyphRange,
                origin: origin
            ) {
                rects.append(rect)
            }
        }

        return rects
    }

    private func backgroundRect(
        for glyphRange: NSRange,
        origin: NSPoint
    ) -> NSRect? {
        var unionRect: NSRect?

        enumerateLineFragments(forGlyphRange: glyphRange) { lineRect, _, textContainer, _, _ in
            let fragmentPadding = textContainer.lineFragmentPadding
            let horizontalInset = MarkdownTextStyler.blockBackgroundHorizontalInset
            let containerWidth = textContainer.containerSize.width.isFinite
                ? textContainer.containerSize.width
                : lineRect.width
            let rect = NSRect(
                x: origin.x + lineRect.origin.x + fragmentPadding + horizontalInset,
                y: origin.y + lineRect.origin.y,
                width: max(containerWidth - fragmentPadding * 2 - horizontalInset * 2, 0),
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

#if canImport(SwiftMath)
private final class MarkdownFormulaOverlayHost: NSView {
    let label: MTMathUILabel

    init(frame: NSRect, label: MTMathUILabel) {
        self.label = label
        super.init(frame: frame)
        label.frame = bounds
        label.autoresizingMask = [.width, .height]
        addSubview(label)
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }
}
#endif

final class MarkdownFormulaOverlayController {
#if canImport(SwiftMath)
    private var formulaViews: [NSView] = []
#endif

    func clear() {
#if canImport(SwiftMath)
        formulaViews.forEach { $0.removeFromSuperview() }
        formulaViews.removeAll()
#endif
    }

    func update(in textView: NSTextView, spans: [MarkdownFormulaRenderSpan]) {
#if canImport(SwiftMath)
        clear()
        guard !spans.isEmpty,
              let layoutManager = textView.layoutManager,
              let textContainer = textView.textContainer else {
            return
        }

        layoutManager.ensureLayout(for: textContainer)
        for span in spans {
            guard let frame = formulaFrame(for: span, in: textView, layoutManager: layoutManager, textContainer: textContainer),
                  frame.width > 1,
                  frame.height > 1 else {
                continue
            }

            let label = MTMathUILabel(frame: NSRect(origin: .zero, size: frame.size))
            label.latex = span.latex
            label.labelMode = span.isBlock ? .display : .text
            label.textAlignment = span.isBlock ? .center : .left
            label.fontSize = span.isBlock ? 22 : 16
            label.textColor = .labelColor
            label.contentInsets = MTEdgeInsets()
            label.autoresizingMask = []
            let host = MarkdownFormulaOverlayHost(frame: frame, label: label)
            textView.addSubview(host)
            formulaViews.append(host)
        }
#endif
    }

#if canImport(SwiftMath)
    private func formulaFrame(
        for span: MarkdownFormulaRenderSpan,
        in textView: NSTextView,
        layoutManager: NSLayoutManager,
        textContainer: NSTextContainer
    ) -> NSRect? {
        if span.isBlock {
            return blockFormulaFrame(
                for: span.layoutRange,
                in: textView,
                layoutManager: layoutManager,
                textContainer: textContainer
            )
        }
        return inlineFormulaFrame(
            for: span.layoutRange,
            latex: span.latex,
            in: textView,
            layoutManager: layoutManager,
            textContainer: textContainer
        )
    }

    private func blockFormulaFrame(
        for characterRange: NSRange,
        in textView: NSTextView,
        layoutManager: NSLayoutManager,
        textContainer: NSTextContainer
    ) -> NSRect? {
        guard let sourceRect = rect(for: characterRange, in: textView, layoutManager: layoutManager, textContainer: textContainer) else {
            return nil
        }

        let containerWidth = textContainer.containerSize.width.isFinite
            ? textContainer.containerSize.width
            : textView.bounds.width
        let horizontalInset = MarkdownTextStyler.blockBackgroundHorizontalInset + MarkdownTextStyler.blockContentIndent
        let origin = textView.textContainerOrigin
        let width = max(containerWidth - textContainer.lineFragmentPadding * 2 - horizontalInset * 2, 1)
        let height = max(sourceRect.height, 38)
        return NSRect(
            x: origin.x + textContainer.lineFragmentPadding + horizontalInset,
            y: sourceRect.midY - height / 2,
            width: width,
            height: height
        )
    }

    private func inlineFormulaFrame(
        for characterRange: NSRange,
        latex: String,
        in textView: NSTextView,
        layoutManager: NSLayoutManager,
        textContainer: NSTextContainer
    ) -> NSRect? {
        guard let sourceRect = rect(for: characterRange, in: textView, layoutManager: layoutManager, textContainer: textContainer) else {
            return nil
        }

        let sizingLabel = MTMathUILabel()
        sizingLabel.latex = latex
        sizingLabel.labelMode = .text
        sizingLabel.fontSize = 16
        let naturalSize = sizingLabel.fittingSize
        let width = max(naturalSize.width, sourceRect.width, 1)
        let height = max(naturalSize.height, sourceRect.height, 1)
        return NSRect(
            x: sourceRect.minX,
            y: sourceRect.midY - height / 2,
            width: width,
            height: height
        )
    }

    private func rect(
        for characterRange: NSRange,
        in textView: NSTextView,
        layoutManager: NSLayoutManager,
        textContainer: NSTextContainer
    ) -> NSRect? {
        guard characterRange.location != NSNotFound,
              characterRange.length > 0,
              NSMaxRange(characterRange) <= textView.string.utf16.count else {
            return nil
        }

        var effectiveRange = NSRange(location: 0, length: 0)
        let glyphRange = layoutManager.glyphRange(
            forCharacterRange: characterRange,
            actualCharacterRange: &effectiveRange
        )
        guard glyphRange.length > 0 else { return nil }

        var unionRect: NSRect?
        layoutManager.enumerateLineFragments(forGlyphRange: glyphRange) { _, _, textContainer, lineGlyphRange, _ in
            let intersection = NSIntersectionRange(glyphRange, lineGlyphRange)
            guard intersection.length > 0 else { return }
            let rect = layoutManager.boundingRect(forGlyphRange: intersection, in: textContainer)
            unionRect = unionRect.map { NSUnionRect($0, rect) } ?? rect
        }

        guard var rect = unionRect else { return nil }
        let origin = textView.textContainerOrigin
        rect.origin.x += origin.x
        rect.origin.y += origin.y
        return rect
    }
#endif
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
                        .padding(.top, MarkdownTextView.placeholderTopPadding)
                        .padding(.leading, MarkdownTextView.placeholderLeadingPadding)
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
    static let textContainerInset = NSSize(width: 12, height: 32)
    static let placeholderTopPadding: CGFloat = 32
    static let placeholderLeadingPadding: CGFloat = 18

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

        let textStorage = NSTextStorage()
        let layoutManager = context.coordinator.glyphHider
        let textContainer = NSTextContainer(containerSize: NSSize(
            width: scrollView.contentSize.width,
            height: CGFloat.greatestFiniteMagnitude
        ))
        textContainer.widthTracksTextView = true
        textStorage.addLayoutManager(layoutManager)
        layoutManager.addTextContainer(textContainer)

        let textView = NSTextView(frame: .zero, textContainer: textContainer)
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
        textView.textContainerInset = MarkdownTextView.textContainerInset
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isAutomaticDataDetectionEnabled = false
        textView.isContinuousSpellCheckingEnabled = false
        textView.usesFindPanel = true
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = textContainer.containerSize
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
        context.coordinator.refreshMarkdown(in: textView)
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }

        if textView.string != text, !textView.hasMarkedText() {
            let selectedRanges = textView.selectedRanges
            textView.string = text
            textView.selectedRanges = selectedRanges
            context.coordinator.refreshMarkdown(in: textView)
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
        let glyphHider = MarkdownLayoutManager()
        let formulaOverlayController = MarkdownFormulaOverlayController()
        var lastFocusRequestID = 0
        private var isRefreshingMarkdown = false

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
            refreshMarkdown(in: textView)
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            guard !isRefreshingMarkdown else { return }
            refreshMarkdown(in: textView)
        }

        func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            let edit: MarkdownEditResult?
            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                edit = MarkdownCodeBlockEditing.exitCodeBlockOnBlankCodeLine(
                    in: textView.string,
                    selectedRange: textView.selectedRange()
                ) ?? MarkdownCodeBlockEditing.exitFormulaBlockOnBlankFormulaLine(
                    in: textView.string,
                    selectedRange: textView.selectedRange()
                )
            } else if commandSelector == #selector(NSResponder.deleteBackward(_:)) {
                edit = MarkdownCodeBlockEditing.collapseEmptyCodeBlockOnBackspace(
                    in: textView.string,
                    selectedRange: textView.selectedRange()
                ) ?? MarkdownCodeBlockEditing.collapseEmptyFormulaBlockOnBackspace(
                    in: textView.string,
                    selectedRange: textView.selectedRange()
                )
            } else if commandSelector == #selector(NSResponder.insertNewlineIgnoringFieldEditor(_:)) {
                edit = MarkdownCodeBlockEditing.exitCodeBlock(
                    in: textView.string,
                    selectedRange: textView.selectedRange()
                )
            } else {
                return false
            }

            guard let edit else { return false }
            apply(edit, to: textView)
            return true
        }

        func textView(
            _ textView: NSTextView,
            shouldChangeTextIn affectedCharRange: NSRange,
            replacementString: String?
        ) -> Bool {
            if let replacementString,
               let edit = MarkdownCodeBlockEditing.expandOpeningFence(
                in: textView.string,
                affectedRange: affectedCharRange,
                replacementString: replacementString
               ) ?? MarkdownCodeBlockEditing.expandOpeningFormulaFence(
                in: textView.string,
                affectedRange: affectedCharRange,
                replacementString: replacementString
               ) {
                apply(edit, to: textView)
                return false
            }

            MarkdownTextStyler.updateTypingAttributes(for: textView)
            return true
        }

        private func apply(_ edit: MarkdownEditResult, to textView: NSTextView) {
            textView.string = edit.text
            text = edit.text
            textView.setSelectedRange(edit.selectedRange)
            refreshMarkdown(in: textView)
        }

        func refreshMarkdown(in textView: NSTextView) {
            guard !isRefreshingMarkdown else { return }
            isRefreshingMarkdown = true
            defer { isRefreshingMarkdown = false }

            MarkdownTextStyler.apply(
                to: textView,
                glyphHider: glyphHider,
                formulaOverlayController: formulaOverlayController
            )
        }
    }
}
