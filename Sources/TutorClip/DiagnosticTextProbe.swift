import AppKit
import Foundation

extension DiagnosticCLI {
    static func runMarkdownPipelineProbe() {
        let raw = """
        FORMATTED_QUESTION
        ### SAT Notes Question

        While researching a topic, a student has taken the following notes:

        **Context:** the student is comparing rail tunnel lengths.

        • The Seikan Tunnel is a rail tunnel in Japan.
        • It is roughly 33 miles long.

        This paragraph has a soft
        line break inside one sentence.

        Which choice most effectively uses relevant information from the notes to accomplish this goal?

        A) Choice A text.

        B) Choice B text.

        C) Choice C text.

        D) Choice D text.
        END_FORMATTED_QUESTION
        QUESTION_METADATA
        Answer: B
        Type: notesSynthesis
        END_QUESTION_METADATA
        """
        let parsed = GeneratedQuestion.parse(raw)
        print("chars=\(parsed.question.count)")
        print("lines=\(parsed.question.components(separatedBy: .newlines).count)")
        print("paragraphs=\(parsed.question.components(separatedBy: "\n\n").count)")
        print("answer=\(parsed.answer ?? "nil")")
        print("category=\(parsed.category?.rawValue ?? "nil")")
        let hasChoiceBreaks = parsed.question.contains("\n\nA)") && parsed.question.contains("\n\nB)")
        let renderedText = SelectableQuestionTextRenderer.attributedString(from: parsed.question).string
        let renderedHasChoiceLines = renderedText.contains("\nA)") && renderedText.contains("\nB)")
        let markdownMarkersRendered = renderedText.contains("###") || renderedText.contains("**")
        let softBreakCollapsed = renderedText.contains("soft line break")
            && !renderedText.contains("soft\nline break")
        let paragraphSpacing = renderedParagraphSpacing(for: parsed.question)
        print("hasChoiceBreaks=\(hasChoiceBreaks)")
        print("renderedLines=\(renderedText.components(separatedBy: .newlines).count)")
        print("renderedHasChoiceLines=\(renderedHasChoiceLines)")
        print("markdownMarkersRendered=\(markdownMarkersRendered)")
        print("softBreakCollapsed=\(softBreakCollapsed)")
        print("renderedParagraphSpacing=\(paragraphSpacing)")
        if parsed.answer != "B"
            || parsed.category != .notesSynthesis
            || !hasChoiceBreaks
            || !renderedHasChoiceLines
            || markdownMarkersRendered
            || !softBreakCollapsed
            || paragraphSpacing != 0 {
            fputs("Markdown pipeline probe failed.\n", stderr)
            exit(2)
        }
    }

    static func runSelectionPromptProbe() {
        var document = OCRDocument.empty()
        document.editedText = """
        This is a synthetic SAT passage.

        A) Synthetic answer.
        """
        let builder = PromptBuilder()
        let selected = "microstructures in their feathers"
        let translatePrompt = builder.userPrompt(
            action: .translateSelection,
            document: document,
            selectedText: selected,
            customQuestion: nil,
            category: .reading,
            language: .chinese
        )
        let vocabularyPrompt = builder.userPrompt(
            action: .vocabulary,
            document: document,
            selectedText: selected,
            customQuestion: nil,
            category: .reading,
            language: .chinese
        )
        let prompts = [translatePrompt, vocabularyPrompt]
        let selectionOnly = prompts.allSatisfy { prompt in
            prompt.contains(selected)
                && !prompt.contains("OCR 全文")
                && !prompt.contains("A) Synthetic answer")
        }
        let avoidsAnswering = prompts.allSatisfy { prompt in
            prompt.contains("不要回答题目")
                && !prompt.contains("正确答案：")
                && !prompt.contains("为什么其他选项不对")
        }
        print("selectionOnly=\(selectionOnly)")
        print("avoidsAnswering=\(avoidsAnswering)")
        if !selectionOnly || !avoidsAnswering {
            fputs("Selection prompt probe failed.\n", stderr)
            exit(2)
        }
    }

    static func runDefaultSettingsProbe() {
        let settings = AppSettings()
        let shortcutIsDefault = settings.shortcutKeyCode == KeyCodeDisplay.defaultKeyCode
            && settings.shortcutModifiers == KeyCodeDisplay.defaultModifiers
            && settings.shortcutDisplay == "Shift + Command + O"
        let languageIsDefault = settings.appLanguage == .chinese
        print("shortcutDisplay=\(settings.shortcutDisplay)")
        print("shortcutIsDefault=\(shortcutIsDefault)")
        print("languageIsDefaultChinese=\(languageIsDefault)")
        if !shortcutIsDefault || !languageIsDefault {
            fputs("Default settings probe failed.\n", stderr)
            exit(2)
        }
    }

    static func runNotesQuestionFormattingProbe() {
        let raw = """
        FORMATTED_QUESTION
        While researching a topic, a student has taken the following notes:

        • The Seikan Tunnel is a rail tunnel in Japan.

        • It connects the island of Honshu to the island of Hokkaido.

        • It is roughly 33 miles long.

        • The Channel Tunnel is a rail tunnel in Europe.

        The student wants to compare the lengths of the two rail tunnels.

        Which choice most effectively uses relevant information from the notes to accomplish this goal?

        A) Choice A text.

        B) Choice B text.

        C) Choice C text.

        D) Choice D text.
        END_FORMATTED_QUESTION
        QUESTION_METADATA
        Answer: B
        Type: notesSynthesis
        END_QUESTION_METADATA
        """
        let parsed = GeneratedQuestion.parse(raw)
        let question = parsed.question
        let bulletParagraphs = question.components(separatedBy: "\n\n").filter {
            $0.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("•")
        }
        let choicesSeparated = ["A)", "B)", "C)", "D)"].allSatisfy { marker in
            question.contains("\n\n\(marker)")
        }
        print("bulletParagraphs=\(bulletParagraphs.count)")
        print("choicesSeparated=\(choicesSeparated)")
        print("category=\(parsed.category?.rawValue ?? "nil")")
        if bulletParagraphs.count < 4 || !choicesSeparated || parsed.category != .notesSynthesis {
            fputs("Notes question formatting probe failed.\n", stderr)
            exit(2)
        }
    }

    static func runOCRFormatStateProbe() {
        let formatting = OCRFormatState.formatting.message(language: .chinese)
        let applied = OCRFormatState.applied.message(language: .chinese)
        let failed = OCRFormatState.failed("network").message(language: .english)
        print("formatting=\(formatting)")
        print("applied=\(applied)")
        print("failed=\(failed)")
        if !formatting.contains("DeepSeek")
            || !formatting.contains("整理")
            || !applied.contains("Markdown")
            || !failed.contains("Local OCR text was kept") {
            fputs("OCR format state probe failed.\n", stderr)
            exit(2)
        }
    }

    static func runLatexDisplayProbe() {
        let source = #"The equation \(3x^2 + (9p + q)x + pq = 0\) has solutions x_1 and x_2. The product is m \cdot pq. A) \frac{1}{3} B) \frac{1}{9}"#
        let escapedSource = #"C) \\frac{x+1}{12} D) \\sqrt{x_2} and m \\times n"#
        let normalized = LatexDisplayNormalizer.displayString(from: source)
        let escapedNormalized = LatexDisplayNormalizer.displayString(from: escapedSource)
        let rendered = SelectableQuestionTextRenderer.attributedString(from: source).string
        let normalizedLooksMath = normalized.contains("3x²")
            && normalized.contains("x₁")
            && normalized.contains("x₂")
            && normalized.contains("m · pq")
            && normalized.contains("⅓")
            && normalized.contains("⅑")
            && !normalized.contains(#"\frac"#)
            && !normalized.contains(#"\cdot"#)
        let escapedLooksMath = escapedNormalized.contains("(x+1)⁄12")
            && escapedNormalized.contains("√(x₂)")
            && escapedNormalized.contains("m × n")
            && !escapedNormalized.contains(#"\frac"#)
            && !escapedNormalized.contains(#"\sqrt"#)
        let renderedLooksMath = rendered.contains("3x²")
            && rendered.contains("x₁")
            && rendered.contains("x₂")
            && rendered.contains("m · pq")
            && rendered.contains("⅓")
            && rendered.contains("⅑")
        print("normalized=\(normalized)")
        print("escapedNormalized=\(escapedNormalized)")
        print("rendered=\(rendered)")
        print("normalizedLooksMath=\(normalizedLooksMath)")
        print("escapedLooksMath=\(escapedLooksMath)")
        print("renderedLooksMath=\(renderedLooksMath)")
        if !normalizedLooksMath || !escapedLooksMath || !renderedLooksMath {
            fputs("LaTeX display probe failed.\n", stderr)
            exit(2)
        }
    }

    static func runResponseProcessingProbe() {
        let explainRaw = """
        ANSWER_SUMMARY
        Answer: C
        Reason: It follows the contrast.
        Evidence: However, the evidence changes the conclusion.
        END_ANSWER_SUMMARY

        ### 1. Correct Answer

        The answer is C.
        """
        let explain = TutorResponseProcessor.process(rawContent: explainRaw, action: .explainAll)
        let vocabRaw = """
        VOCAB_CARDS
        - term: contrast | meaning: 转折关系 | note: a difference between ideas | example: The contrast clarifies the claim. | source: However
        END_VOCAB_CARDS

        ### Vocabulary

        Focus on contrast.
        """
        let vocab = TutorResponseProcessor.process(rawContent: vocabRaw, action: .vocabulary)
        print("explainAnswer=\(explain.answerSummary?.answer ?? "nil")")
        print("explainBodyContainsWrapper=\(explain.content.contains("ANSWER_SUMMARY"))")
        print("vocabCount=\(vocab.vocabularyCards.count)")
        print("vocabBodyContainsWrapper=\(vocab.content.contains("VOCAB_CARDS"))")
        if explain.answerSummary?.choiceLetter != "C"
            || explain.content.contains("ANSWER_SUMMARY")
            || vocab.vocabularyCards.count != 1
            || vocab.content.contains("VOCAB_CARDS") {
            fputs("Response processing probe failed.\n", stderr)
            exit(2)
        }
    }

    private static func renderedParagraphSpacing(for markdown: String) -> CGFloat {
        let attributed = SelectableQuestionTextRenderer.attributedString(from: markdown)
        var spacing: CGFloat = -1
        attributed.enumerateAttribute(.paragraphStyle, in: NSRange(location: 0, length: attributed.length)) { value, _, stop in
            if let style = value as? NSParagraphStyle {
                spacing = style.paragraphSpacing
                stop.pointee = true
            }
        }
        return spacing
    }
}
