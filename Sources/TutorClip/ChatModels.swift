import Foundation

struct ChatMessage: Codable, Identifiable, Equatable {
    enum Role: String, Codable {
        case user
        case assistant
        case system
    }

    var id: UUID
    var sessionId: UUID
    var role: Role
    var content: String
    var createdAt: Date
    var actionType: TutorAction?
}

struct AnswerSummary: Equatable {
    var answer: String
    var reason: String
    var evidence: String

    var choiceLetter: String? {
        let uppercased = answer.uppercased()
        return uppercased.first { "ABCD".contains($0) }.map(String.init)
    }

    static func extract(from content: String) -> (summary: AnswerSummary?, body: String) {
        guard let start = content.range(of: "ANSWER_SUMMARY"),
              let end = content.range(of: "END_ANSWER_SUMMARY", range: start.upperBound..<content.endIndex) else {
            return (nil, content)
        }

        let block = String(content[start.upperBound..<end.lowerBound])
        let answer = field("Answer", in: block)
        let reason = field("Reason", in: block)
        let evidence = field("Evidence", in: block)
        var body = content
        body.removeSubrange(start.lowerBound..<end.upperBound)
        let cleanedBody = body.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !answer.isEmpty || !reason.isEmpty || !evidence.isEmpty else {
            return (nil, cleanedBody)
        }
        return (
            AnswerSummary(answer: answer.isEmpty ? "?" : answer, reason: reason, evidence: evidence),
            cleanedBody
        )
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

struct VocabularyCard: Codable, Equatable, Identifiable {
    var id: UUID
    var term: String
    var meaning: String
    var note: String
    var example: String?
    var source: String

    static func extract(from content: String) -> (cards: [VocabularyCard], body: String) {
        guard let start = content.range(of: "VOCAB_CARDS"),
              let end = content.range(of: "END_VOCAB_CARDS", range: start.upperBound..<content.endIndex) else {
            return ([], content)
        }

        let block = String(content[start.upperBound..<end.lowerBound])
        let cards = block.split(whereSeparator: \.isNewline).compactMap { line -> VocabularyCard? in
            parseLine(String(line))
        }
        var body = content
        body.removeSubrange(start.lowerBound..<end.upperBound)
        return (cards, body.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private static func parseLine(_ line: String) -> VocabularyCard? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let cleaned = trimmed.hasPrefix("-") ? String(trimmed.dropFirst()).trimmingCharacters(in: .whitespacesAndNewlines) : trimmed
        var fields: [String: String] = [:]
        for segment in cleaned.components(separatedBy: "|") {
            let parts = segment.split(separator: ":", maxSplits: 1).map(String.init)
            guard parts.count == 2 else { continue }
            fields[parts[0].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()] = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard let term = fields["term"], !term.isEmpty else { return nil }
        return VocabularyCard(
            id: UUID(),
            term: term,
            meaning: fields["meaning"] ?? "",
            note: fields["note"] ?? "",
            example: fields["example"],
            source: fields["source"] ?? ""
        )
    }
}
