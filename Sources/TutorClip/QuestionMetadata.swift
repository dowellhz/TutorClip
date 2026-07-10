import Foundation

struct QuestionMetadata: Equatable {
    var answer: String?
    var category: SessionCategory?

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
                category: category(from: field("Type", in: block))
            ),
            body.trimmingCharacters(in: .whitespacesAndNewlines)
        )
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
}
