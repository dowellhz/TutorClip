import AppKit
import SwiftUI

struct SelectableMarkdownTextView: NSViewRepresentable {
    let markdown: String
    let underlinedTexts: [String]
    @Binding var selectedText: String
    @Binding var selectionRect: CGRect?

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        scrollView.contentView.postsBoundsChangedNotifications = true

        let textView = NSTextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = true
        textView.drawsBackground = false
        textView.textColor = .labelColor
        textView.font = NSFont.systemFont(ofSize: 15)
        textView.textContainerInset = NSSize(width: 14, height: 12)
        textView.minSize = NSSize(width: 0, height: 260)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(width: scrollView.contentSize.width, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.lineBreakMode = .byWordWrapping
        textView.delegate = context.coordinator

        scrollView.documentView = textView
        context.coordinator.scrollView = scrollView
        context.coordinator.textView = textView
        context.coordinator.startObservingScroll()
        context.coordinator.updateMarkdown(markdown)
        context.coordinator.updateUnderlines(underlinedTexts)
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        textView.textContainer?.containerSize = NSSize(width: scrollView.contentSize.width, height: CGFloat.greatestFiniteMagnitude)
        context.coordinator.updateMarkdown(markdown)
        context.coordinator.updateUnderlines(underlinedTexts)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(selectedText: $selectedText, selectionRect: $selectionRect)
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        @Binding var selectedText: String
        @Binding var selectionRect: CGRect?
        weak var textView: NSTextView?
        weak var scrollView: NSScrollView?
        private var renderedMarkdown = ""
        private var renderedUnderlines: [String] = []
        private var scrollObserver: NSObjectProtocol?

        init(selectedText: Binding<String>, selectionRect: Binding<CGRect?>) {
            _selectedText = selectedText
            _selectionRect = selectionRect
        }

        deinit {
            if let scrollObserver {
                NotificationCenter.default.removeObserver(scrollObserver)
            }
        }

        func startObservingScroll() {
            guard scrollObserver == nil, let scrollView else { return }
            scrollObserver = NotificationCenter.default.addObserver(
                forName: NSView.boundsDidChangeNotification,
                object: scrollView.contentView,
                queue: .main
            ) { [weak self] _ in
                self?.updateSelection()
            }
        }

        func updateMarkdown(_ markdown: String) {
            guard markdown != renderedMarkdown, let textView else { return }
            renderedMarkdown = markdown
            RuntimeLog.writeTextMetrics("question-markdown-input", markdown)
            let attributed = SelectableQuestionTextRenderer.attributedString(from: markdown.isEmpty ? "..." : markdown)
            textView.textStorage?.setAttributedString(attributed)
            RuntimeLog.writeTextMetrics("question-markdown-rendered-string", textView.string)
            updateSelection()
        }

        func updateUnderlines(_ texts: [String]) {
            guard let textView, texts != renderedUnderlines else { return }
            renderedUnderlines = texts
            let storage = textView.textStorage
            let fullRange = NSRange(location: 0, length: (textView.string as NSString).length)
            storage?.removeAttribute(.underlineStyle, range: fullRange)
            let source = textView.string as NSString
            for text in texts where !text.isEmpty {
                if let found = UnderlineTextMatcher.uniqueRange(of: text, in: source) {
                    storage?.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: found)
                }
            }
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            updateSelection()
        }

        private func updateSelection() {
            guard let textView, let scrollView else {
                selectedText = ""
                selectionRect = nil
                return
            }
            let range = textView.selectedRange()
            guard range.length > 0,
                  let swiftRange = Range(range, in: textView.string) else {
                selectedText = ""
                selectionRect = nil
                return
            }
            selectedText = String(textView.string[swiftRange])
            selectionRect = visibleSelectionRect(for: range, in: textView, scrollView: scrollView)
        }

        private func visibleSelectionRect(for range: NSRange, in textView: NSTextView, scrollView: NSScrollView) -> CGRect? {
            guard let layoutManager = textView.layoutManager,
                  let textContainer = textView.textContainer else {
                return nil
            }
            layoutManager.ensureLayout(for: textContainer)
            let glyphRange = layoutManager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
            var rect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)
            rect.origin.x += textView.textContainerOrigin.x
            rect.origin.y += textView.textContainerOrigin.y

            let visibleRect = textView.visibleRect
            let clipped = rect.intersection(visibleRect)
            guard !clipped.isNull, !clipped.isEmpty else { return nil }
            return CGRect(
                x: clipped.minX - visibleRect.minX,
                y: clipped.minY - visibleRect.minY,
                width: clipped.width,
                height: clipped.height
            ).intersection(CGRect(origin: .zero, size: scrollView.contentSize))
        }

    }
}

enum UnderlineTextMatcher {
    static func uniqueRange(of text: String, in source: NSString) -> NSRange? {
        let options: NSString.CompareOptions = [.caseInsensitive, .diacriticInsensitive]
        let whole = NSRange(location: 0, length: source.length)
        let first = source.range(of: text, options: options, range: whole)
        guard first.location != NSNotFound else { return nil }
        let nextLocation = first.location + first.length
        let remaining = NSRange(location: nextLocation, length: source.length - nextLocation)
        return source.range(of: text, options: options, range: remaining).location == NSNotFound
            ? first
            : nil
    }
}

enum SelectableQuestionTextRenderer {
    static func attributedString(from markdown: String) -> NSAttributedString {
        let result = NSMutableAttributedString()
        let normalized = questionDisplayMarkdown(from: markdown)
        let lines = normalized.components(separatedBy: .newlines)
        for (index, line) in lines.enumerated() {
            let displayText = displayLine(from: line)
            result.append(inlineAttributedStringWithUnderlines(from: displayText))
            if index < lines.count - 1 {
                result.append(NSAttributedString(string: "\n", attributes: baseAttributes()))
            }
        }
        applyBaseStyle(to: result)
        return result
    }

    private static func questionDisplayMarkdown(from markdown: String) -> String {
        markdown
            .components(separatedBy: "\n\n")
            .map { block in
                let lines = block.components(separatedBy: .newlines)
                if lines.contains(where: isStructureLine) {
                    return lines.joined(separator: "\n")
                }
                return lines
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                    .filter { !$0.isEmpty }
                    .joined(separator: " ")
            }
            .joined(separator: "\n\n")
    }

    private static func isStructureLine(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard let first = trimmed.first else { return false }
        if first == "•" || first == "-" { return true }
        guard ["A", "B", "C", "D"].contains(first) else { return false }
        let rest = trimmed.dropFirst()
        return rest.first == ")" || rest.first == "." || rest.first?.isWhitespace == true
    }

    private static func inlineAttributedString(from markdown: String) -> NSAttributedString {
        do {
            return try NSAttributedString(
                markdown: markdown,
                options: AttributedString.MarkdownParsingOptions(
                    interpretedSyntax: .inlineOnlyPreservingWhitespace,
                    failurePolicy: .returnPartiallyParsedIfPossible
                ),
                baseURL: nil
            )
        } catch {
            MarkdownFallbackDiagnostics.logOnce(markdown: markdown, error: error)
            let readableFallback = markdown
                .replacingOccurrences(of: "**", with: "")
                .replacingOccurrences(of: "`", with: "")
            return NSAttributedString(string: readableFallback, attributes: baseAttributes())
        }
    }

    private static func inlineAttributedStringWithUnderlines(from markdown: String) -> NSAttributedString {
        let segments = QuestionUnderlineMarkup.segments(in: markdown)
        let markdownWithoutUnderlineTags = segments.map(\.text).joined()
        let result = inlineAttributedString(from: markdownWithoutUnderlineTags).mutableCopy() as! NSMutableAttributedString
        let renderedSource = result.string as NSString
        var searchLocation = 0

        for segment in segments where segment.isUnderlined {
            let target = inlineAttributedString(from: segment.text).string
            guard !target.isEmpty, searchLocation <= renderedSource.length else { continue }
            let searchRange = NSRange(location: searchLocation, length: renderedSource.length - searchLocation)
            let found = renderedSource.range(of: target, range: searchRange)
            guard found.location != NSNotFound else { continue }
            result.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: found)
            searchLocation = found.location + found.length
        }
        return result
    }

    private static func displayLine(from line: String) -> String {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix(">") {
            return trimmed.drop(while: { $0 == ">" || $0.isWhitespace })
                .trimmingCharacters(in: .whitespaces)
        }
        guard trimmed.hasPrefix("#") else { return line }
        var index = trimmed.startIndex
        while index < trimmed.endIndex, trimmed[index] == "#" {
            index = trimmed.index(after: index)
        }
        guard index < trimmed.endIndex, trimmed[index].isWhitespace else { return line }
        return String(trimmed[index...]).trimmingCharacters(in: .whitespaces)
    }

    private static func baseAttributes(
        font: NSFont = NSFont.systemFont(ofSize: 15),
        paragraphSpacing: CGFloat = 0
    ) -> [NSAttributedString.Key: Any] {
        [
            .foregroundColor: NSColor.labelColor,
            .font: font,
            .paragraphStyle: paragraphStyle(spacingAfter: paragraphSpacing)
        ]
    }

    private static func paragraphStyle(spacingAfter: CGFloat) -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.lineBreakMode = .byWordWrapping
        style.lineSpacing = 3
        style.paragraphSpacing = spacingAfter
        return style
    }

    private static func applyBaseStyle(to attributed: NSMutableAttributedString) {
        let fullRange = NSRange(location: 0, length: attributed.length)
        attributed.addAttribute(.paragraphStyle, value: paragraphStyle(spacingAfter: 0), range: fullRange)
        attributed.enumerateAttribute(.font, in: fullRange) { value, range, _ in
            guard value == nil else { return }
            attributed.addAttribute(.font, value: NSFont.systemFont(ofSize: 15), range: range)
        }
        attributed.addAttribute(.foregroundColor, value: NSColor.labelColor, range: fullRange)
    }
}

private enum MarkdownFallbackDiagnostics {
    private static let lock = NSLock()
    private static var loggedHashes: Set<UInt64> = []

    static func logOnce(markdown: String, error: Error) {
        let hash = stableHash(markdown)
        lock.lock()
        let isNew = loggedHashes.insert(hash).inserted
        lock.unlock()
        guard isNew else { return }
        RuntimeLog.write("question-markdown-plain-fallback hash=\(String(hash, radix: 16)) error=\(error.localizedDescription)")
    }

    private static func stableHash(_ text: String) -> UInt64 {
        text.utf8.reduce(1_469_598_103_934_665_603) { hash, byte in
            (hash ^ UInt64(byte)) &* 1_099_511_628_211
        }
    }
}
