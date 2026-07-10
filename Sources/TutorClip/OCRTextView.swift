import AppKit
import SwiftUI

struct OCRTextView: NSViewRepresentable {
    @Binding var text: String
    @Binding var selectedText: String
    @Binding var selectionRect: CGRect?
    @Binding var highlightedText: String

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        scrollView.contentView.postsBoundsChangedNotifications = true

        let textView = NSTextView()
        textView.isEditable = true
        textView.isSelectable = true
        textView.allowsUndo = true
        textView.font = NSFont.systemFont(ofSize: 14)
        textView.textColor = .labelColor
        textView.backgroundColor = .clear
        textView.isRichText = false
        textView.string = text
        textView.delegate = context.coordinator
        textView.textContainerInset = NSSize(width: 10, height: 10)
        textView.minSize = NSSize(width: 0, height: 260)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(width: scrollView.contentSize.width, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.lineBreakMode = .byWordWrapping
        textView.typingAttributes[.paragraphStyle] = Self.wrappingParagraphStyle

        scrollView.documentView = textView
        context.coordinator.scrollView = scrollView
        context.coordinator.textView = textView
        context.coordinator.startObservingScroll()
        context.coordinator.applyHighlight(highlightedText)
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        textView.textContainer?.containerSize = NSSize(width: scrollView.contentSize.width, height: CGFloat.greatestFiniteMagnitude)
        textView.typingAttributes[.paragraphStyle] = Self.wrappingParagraphStyle
        if textView.string != text {
            textView.string = text
        }
        context.coordinator.applyHighlight(highlightedText)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(
            text: $text,
            selectedText: $selectedText,
            selectionRect: $selectionRect,
            highlightedText: $highlightedText
        )
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        @Binding var text: String
        @Binding var selectedText: String
        @Binding var selectionRect: CGRect?
        @Binding var highlightedText: String
        weak var textView: NSTextView?
        weak var scrollView: NSScrollView?
        private var scrollObserver: NSObjectProtocol?

        init(text: Binding<String>, selectedText: Binding<String>, selectionRect: Binding<CGRect?>, highlightedText: Binding<String>) {
            _text = text
            _selectedText = selectedText
            _selectionRect = selectionRect
            _highlightedText = highlightedText
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

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            text = textView.string
            updateSelection()
            applyHighlight(highlightedText)
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
            guard range.length > 0, let swiftRange = Range(range, in: textView.string) else {
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

            let local = CGRect(
                x: clipped.minX - visibleRect.minX,
                y: clipped.minY - visibleRect.minY,
                width: clipped.width,
                height: clipped.height
            )
            return local.intersection(CGRect(origin: .zero, size: scrollView.contentSize))
        }

        func applyHighlight(_ evidence: String) {
            guard let textView, let layoutManager = textView.layoutManager else { return }
            let fullRange = NSRange(location: 0, length: (textView.string as NSString).length)
            layoutManager.removeTemporaryAttribute(.backgroundColor, forCharacterRange: fullRange)
            layoutManager.removeTemporaryAttribute(.underlineStyle, forCharacterRange: fullRange)

            let ranges = Self.highlightRanges(in: textView.string, evidence: evidence)
            for range in ranges {
                layoutManager.addTemporaryAttribute(
                    .backgroundColor,
                    value: NSColor.systemTeal.withAlphaComponent(0.20),
                    forCharacterRange: range
                )
                layoutManager.addTemporaryAttribute(
                    .underlineStyle,
                    value: NSUnderlineStyle.single.rawValue,
                    forCharacterRange: range
                )
            }
        }

        private static func highlightRanges(in text: String, evidence: String) -> [NSRange] {
            let source = text as NSString
            let cleanedEvidence = cleanEvidence(evidence)
            guard !cleanedEvidence.isEmpty else { return [] }

            let exact = source.range(of: cleanedEvidence, options: [.caseInsensitive, .diacriticInsensitive])
            if exact.location != NSNotFound {
                return [exact]
            }

            let words = cleanedEvidence
                .components(separatedBy: .whitespacesAndNewlines)
                .map { trimSearchToken($0) }
                .filter { $0.count >= 2 }
            guard words.count >= 3 else { return [] }

            for windowSize in [14, 12, 10, 8, 6, 4, 3] where words.count >= windowSize {
                for start in 0...(words.count - windowSize) {
                    let phrase = words[start..<(start + windowSize)].joined(separator: " ")
                    let range = source.range(of: phrase, options: [.caseInsensitive, .diacriticInsensitive])
                    if range.location != NSNotFound {
                        return [range]
                    }
                }
            }
            return []
        }

        private static func cleanEvidence(_ evidence: String) -> String {
            evidence
                .replacingOccurrences(of: "Evidence:", with: "")
                .replacingOccurrences(of: "证据：", with: "")
                .replacingOccurrences(of: "证据:", with: "")
                .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters))
        }

        private static func trimSearchToken(_ token: String) -> String {
            token.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters))
        }
    }

    private static var wrappingParagraphStyle: NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.lineBreakMode = .byWordWrapping
        style.lineSpacing = 2
        return style
    }
}
