import Foundation

struct QuestionMetadata: Equatable {
    var answer: String?
    var category: SessionCategory?
    var section: SATSection = .unknown
    var domain: String = ""
    var skill: String = ""
    var questionTypeID: String = ""
    var knowledgePointIDs: [String] = []
    var difficulty: SATDifficulty = .unknown
    var confidence: Double = 0
    var answerConfidence: Double?

    static func extract(from content: String) -> (metadata: QuestionMetadata, body: String) {
        guard let start = content.range(of: "QUESTION_METADATA"),
              let end = content.range(of: "END_QUESTION_METADATA", range: start.upperBound..<content.endIndex) else {
            return (QuestionMetadata(answer: nil, category: nil), content)
        }

        let block = String(content[start.upperBound..<end.lowerBound])
        var body = content
        body.removeSubrange(start.lowerBound..<end.upperBound)
        return (
            QuestionMetadata(
                answer: choiceLetter(from: field("Answer", in: block)),
                category: category(from: field("Type", in: block)),
                section: section(from: field("Section", in: block)),
                domain: field("Domain", in: block),
                skill: field("Skill", in: block),
                questionTypeID: field("QuestionTypeID", in: block).uppercased(),
                knowledgePointIDs: listField("KnowledgePoints", in: block),
                difficulty: difficulty(from: field("Difficulty", in: block)),
                confidence: Double(field("Confidence", in: block)) ?? 0,
                answerConfidence: Double(field("AnswerConfidence", in: block))
            ),
            body.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    static func section(from value: String) -> SATSection {
        switch value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "reading and writing", "readingwriting", "reading_writing": return .readingWriting
        case "math": return .math
        default: return .unknown
        }
    }

    static func difficulty(from value: String) -> SATDifficulty {
        SATDifficulty(rawValue: value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()) ?? .unknown
    }

    static func choiceLetter(from value: String) -> String? {
        value.uppercased().first { "ABCD".contains($0) }.map(String.init)
    }

    static func category(from value: String) -> SessionCategory? {
        let label = value
            .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters))
            .lowercased()
        if label.contains("notessynthesis") || label.contains("notes_synthesis") || label.contains("notes-synthesis") {
            return .notesSynthesis
        }
        if label.contains("/") {
            let parts = label.split(separator: "/").map(String.init)
            if parts.contains("math") { return .math }
            if parts.contains("grammar") { return .grammar }
            if parts.contains("vocabulary") { return .vocabulary }
            if parts.contains("writing") { return .writing }
            if parts.contains("reading") { return .reading }
        }
        switch label {
        case "reading": return .reading
        case "writing": return .writing
        case "notessynthesis", "notes_synthesis", "notes-synthesis", "notes": return .notesSynthesis
        case "vocabulary": return .vocabulary
        case "grammar": return .grammar
        case "math": return .math
        case "unknown", "": return nil
        default: return nil
        }
    }

    private static func field(_ name: String, in block: String) -> String {
        block.split(whereSeparator: \.isNewline)
            .compactMap { line -> String? in
                let text = String(line).trimmingCharacters(in: .whitespacesAndNewlines)
                let prefix = "\(name):"
                guard text.lowercased().hasPrefix(prefix.lowercased()) else { return nil }
                return String(text.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
            }
            .first ?? ""
    }

    private static func listField(_ name: String, in block: String) -> [String] {
        field(name, in: block).split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() }
    }
}
