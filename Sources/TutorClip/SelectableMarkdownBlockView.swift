import AppKit
import SwiftUI

struct SelectableMarkdownBlockView: NSViewRepresentable {
    let markdown: String
    let underlinedTexts: [String]
    let onSelectionChange: (String, CGRect?) -> Void

    func makeNSView(context: Context) -> NSTextView {
        let textView = NSTextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = true
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 14, height: 4)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.lineBreakMode = .byWordWrapping
        textView.delegate = context.coordinator
        context.coordinator.textView = textView
        updateContent(in: textView, coordinator: context.coordinator)
        return textView
    }

    func updateNSView(_ textView: NSTextView, context: Context) {
        updateContent(in: textView, coordinator: context.coordinator)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSTextView, context: Context) -> CGSize? {
        let width = max(proposal.width ?? 420, 1)
        guard let container = nsView.textContainer, let layoutManager = nsView.layoutManager else { return nil }
        container.containerSize = NSSize(width: width - nsView.textContainerInset.width * 2, height: .greatestFiniteMagnitude)
        layoutManager.ensureLayout(for: container)
        let used = layoutManager.usedRect(for: container)
        return CGSize(width: width, height: ceil(used.height + nsView.textContainerInset.height * 2))
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onSelectionChange: onSelectionChange)
    }

    private func updateContent(in textView: NSTextView, coordinator: Coordinator) {
        guard coordinator.renderedMarkdown != markdown || coordinator.renderedUnderlines != underlinedTexts else { return }
        coordinator.renderedMarkdown = markdown
        coordinator.renderedUnderlines = underlinedTexts
        let attributed = SelectableQuestionTextRenderer.attributedString(from: markdown.isEmpty ? "..." : markdown).mutableCopy() as! NSMutableAttributedString
        let source = attributed.string as NSString
        for text in underlinedTexts where !text.isEmpty {
            if let found = UnderlineTextMatcher.uniqueRange(of: text, in: source) {
                attributed.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: found)
            }
        }
        textView.textStorage?.setAttributedString(attributed)
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        weak var textView: NSTextView?
        var renderedMarkdown = ""
        var renderedUnderlines: [String] = []
        private let onSelectionChange: (String, CGRect?) -> Void

        init(onSelectionChange: @escaping (String, CGRect?) -> Void) {
            self.onSelectionChange = onSelectionChange
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let textView else { return }
            let range = textView.selectedRange()
            guard range.length > 0, let swiftRange = Range(range, in: textView.string) else {
                onSelectionChange("", nil)
                return
            }
            onSelectionChange(String(textView.string[swiftRange]), selectionRect(range, in: textView))
        }

        private func selectionRect(_ range: NSRange, in textView: NSTextView) -> CGRect? {
            guard let layoutManager = textView.layoutManager, let container = textView.textContainer else { return nil }
            layoutManager.ensureLayout(for: container)
            let glyphs = layoutManager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
            var rect = layoutManager.boundingRect(forGlyphRange: glyphs, in: container)
            rect.origin.x += textView.textContainerOrigin.x
            rect.origin.y += textView.textContainerOrigin.y
            return rect
        }
    }
}
