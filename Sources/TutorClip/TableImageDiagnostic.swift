import AppKit
import Foundation

@MainActor
enum TableImageDiagnostic {
    static func runBlocking(imagePath: String, expectedAnswer: String?, expectedTitle: String?) -> Bool {
        var finished = false
        var result = false
        Task {
            defer { finished = true }
            result = await run(imagePath: imagePath, expectedAnswer: expectedAnswer, expectedTitle: expectedTitle)
        }
        while !finished {
            RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.05))
        }
        return result
    }

    private static func run(imagePath: String, expectedAnswer: String?, expectedTitle: String?) async -> Bool {
        guard let image = NSImage(contentsOfFile: imagePath) else {
            print("tableImageDiagnostic=failed reason=image-unreadable")
            return false
        }

        let document = await OCRService().recognize(image: image, language: .english)
        print("ocrTables=\(document.structuredTables.count)")
        print("ocrLines=\(document.lines.count)")
        print("ocrDocumentTitle=\(document.documentTitle?.text ?? "")")
        for (index, paragraph) in (document.paragraphs ?? []).prefix(8).enumerated() {
            print("OCR_PARAGRAPH_\(index + 1) y=\(paragraph.boundingBox.y) text=\(paragraph.text)")
        }
        for (index, line) in document.lines.prefix(12).enumerated() {
            print("OCR_LINE_\(index + 1) y=\(line.boundingBox.y) text=\(line.text)")
        }
        for (index, table) in document.structuredTables.enumerated() {
            print("TABLE_\(index + 1)_BEGIN")
            for row in table.rows {
                print(row.map(\.text).joined(separator: "\t"))
            }
            print("TABLE_\(index + 1)_END")
        }
        if ProcessInfo.processInfo.environment["TUTORCLIP_TABLE_DIAGNOSTIC_OCR_ONLY"] == "1" {
            return !document.structuredTables.isEmpty
        }

        let settingsStore = SettingsStore()
        let client = DeepSeekClient(configLoader: ConfigLoader(), settingsStore: settingsStore)
        let promptBuilder = PromptBuilder()
        do {
            var formattedRaw = ""
            try await client.stream(messages: promptBuilder.formatOCRPrompt(document: document)) { token in
                formattedRaw += token
            }
            var formatted = GeneratedQuestion.parse(formattedRaw, requireQuestionBlock: true)
            print("initialChoices=\(TutorQuestionParsing.answerChoices(from: formatted.question).joined()) sourceChoices=\(TutorQuestionParsing.answerChoices(from: document.editedText).joined())")
            formatted.question = try await TableFormattingAuditor(client: client, promptBuilder: promptBuilder)
                .audit(document: document, candidate: formatted.question)
            print("formattedHasGFMTable=\(GFMTableDetector.containsTable(in: formatted.question))")
            let titleRestored = expectedTitle.map { hasTitleBeforeTable($0, markdown: formatted.question) } ?? true
            print("formattedTitleRestored=\(titleRestored)")
            print("formattedAnswer=\(formatted.answer ?? "")")
            print("FORMATTED_QUESTION_BEGIN")
            print(formatted.question)
            print("FORMATTED_QUESTION_END")
            let verification = try await AnswerVerificationService(client: client, promptBuilder: promptBuilder)
                .verify(question: formatted.question)
            print("verifiedAnswer=\(verification?.answer ?? "")")

            var explainedDocument = document
            explainedDocument.editedText = formatted.question
            explainedDocument.fullText = formatted.question
            var explanationPrompt = promptBuilder.userPrompt(
                action: .explainAll,
                document: explainedDocument,
                selectedText: nil,
                customQuestion: nil,
                category: formatted.category ?? .reading,
                language: settingsStore.settings.appLanguage
            )
            if let verifiedAnswer = verification?.answer {
                explanationPrompt += "\n\n已由独立判题流程验证的正确答案：\(verifiedAnswer)。讲解必须以此答案为准。"
            }
            var explanationRaw = ""
            try await client.stream(messages: [
                DeepSeekMessage(role: "system", content: promptBuilder.systemPrompt(language: settingsStore.settings.appLanguage)),
                DeepSeekMessage(role: "user", content: explanationPrompt)
            ]) { token in
                explanationRaw += token
            }
            let summary = AnswerSummary.extract(from: explanationRaw).summary
            print("explanationAnswer=\(summary?.choiceLetter ?? "")")
            let expectedAnswersMatch = expectedAnswer.map {
                verification?.answer.caseInsensitiveCompare($0) == .orderedSame
                    && summary?.choiceLetter?.caseInsensitiveCompare($0) == .orderedSame
            } ?? true
            let passed = document.structuredTables.isEmpty == false
                && GFMTableDetector.containsTable(in: formatted.question)
                && titleRestored
                && expectedAnswersMatch
                && Set(TutorQuestionParsing.answerChoices(from: formatted.question)) == Set(["A", "B", "C", "D"])
            print("tableImageDiagnostic=\(passed ? "passed" : "failed")")
            return passed
        } catch {
            print("tableImageDiagnostic=failed reason=\(error.localizedDescription)")
            return false
        }
    }

    private static func hasTitleBeforeTable(_ expectedTitle: String, markdown: String) -> Bool {
        let normalized = markdown.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        let normalizedTitle = expectedTitle.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        guard let title = normalized.range(of: normalizedTitle), let table = normalized.range(of: "|") else { return false }
        return title.lowerBound < table.lowerBound
    }
}
