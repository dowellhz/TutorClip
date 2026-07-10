import MarkdownUI
import SwiftUI

struct ChatMessageContentText: View {
    let message: ChatMessage
    private static var loggedMessageIDs = Set<UUID>()

    var body: some View {
        if message.role == .user {
            Text(message.content)
                .font(.system(size: 15, weight: .medium))
                .lineLimit(1)
                .truncationMode(.tail)
        } else {
            markdownText
        }
    }

    private var markdownText: some View {
        Markdown(markdownContent)
            // Tutor responses are text-only. Asset providers prevent model-authored
            // Markdown image URLs from triggering unapproved third-party requests.
            .markdownImageProvider(.asset)
            .markdownInlineImageProvider(.asset)
            .markdownTextStyle {
                FontSize(message.actionType?.isTranslation == true ? 14 : 15)
            }
            .markdownSoftBreakMode(message.actionType?.isTranslation == true ? .space : .lineBreak)
            .markdownBlockStyle(\.paragraph) { configuration in
                configuration.label
                    .relativeLineSpacing(.em(0.18))
                    .markdownMargin(top: 0, bottom: 10)
            }
            .markdownBlockStyle(\.heading1) { configuration in
                configuration.label
                    .markdownTextStyle {
                        FontWeight(.semibold)
                    }
                    .markdownMargin(top: 0, bottom: 8)
            }
            .markdownBlockStyle(\.heading2) { configuration in
                configuration.label
                    .markdownTextStyle {
                        FontWeight(.semibold)
                    }
                    .markdownMargin(top: 0, bottom: 8)
            }
            .markdownBlockStyle(\.heading3) { configuration in
                configuration.label
                    .markdownTextStyle {
                        FontWeight(.semibold)
                    }
                    .markdownMargin(top: 0, bottom: 8)
            }
    }

    private var markdownContent: String {
        let content = message.content.isEmpty ? "..." : message.content
        logMarkdownOnce(content)
        return LatexDisplayNormalizer.displayString(from: content)
    }

    private func logMarkdownOnce(_ markdown: String) {
        guard !message.content.isEmpty else { return }
        guard Self.loggedMessageIDs.insert(message.id).inserted else { return }
        RuntimeLog.writeTextBlock("chat-markdown-rendered action=\(message.actionType?.rawValue ?? "none") message=\(message.id.uuidString)", markdown)
    }
}

private extension TutorAction {
    var isTranslation: Bool {
        self == .translateAll || self == .translateSelection
    }
}
