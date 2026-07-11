import Foundation

struct GeneratedQuestion {
    var question: String
    var answer: String?
    var category: SessionCategory?
    var learningMetadata: SATLearningMetadata

    static func parse(_ raw: String, requireQuestionBlock: Bool = false) -> GeneratedQuestion {
        let metadataParsed = QuestionMetadata.extract(from: stripCodeFences(raw))
        let text = metadataParsed.body
        let question: String
        if let start = text.range(of: "FORMATTED_QUESTION"),
           let end = text.range(of: "END_FORMATTED_QUESTION", range: start.upperBound..<text.endIndex) {
            question = cleanQuestionBlock(String(text[start.upperBound..<end.lowerBound]))
        } else if requireQuestionBlock {
            question = ""
        } else {
            question = cleanQuestionBlock(text)
        }
        RuntimeLog.writeTextMetrics("generated-question-parsed", question)

        return GeneratedQuestion(
            question: question,
            answer: metadataParsed.metadata.answer,
            category: metadataParsed.metadata.category,
            learningMetadata: SATLearningMetadata(questionMetadata: metadataParsed.metadata, isAIGenerated: true)
        )
    }

    private static func stripCodeFences(_ raw: String) -> String {
        raw
            .replacingOccurrences(of: "```markdown", with: "")
            .replacingOccurrences(of: "```text", with: "")
            .replacingOccurrences(of: "```", with: "")
    }

    private static func cleanQuestionBlock(_ raw: String) -> String {
        let placeholderLines: Set<String> = [
            "整理后的 Markdown 题目正文",
            "the new practice question in clean Markdown, including passage/stimulus, question stem, and A/B/C/D choices"
        ]
        let lines = raw.components(separatedBy: .newlines).filter { line in
            !placeholderLines.contains(line.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return trimEmptyBoundaryLines(lines).joined(separator: "\n")
    }

    private static func trimEmptyBoundaryLines(_ lines: [String]) -> [String] {
        var start = lines.startIndex
        var end = lines.endIndex
        while start < end, lines[start].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            start = lines.index(after: start)
        }
        while end > start {
            let previous = lines.index(before: end)
            guard lines[previous].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { break }
            end = previous
        }
        return Array(lines[start..<end])
    }
}
