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
    var contextDocumentID: UUID? = nil
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

enum VocabularyLearningState: String, Codable, CaseIterable {
    case new, learning, mastered
}

enum VocabularyReviewRating {
    case unknown, unsure, known
}

struct VocabularyCard: Codable, Equatable, Identifiable {
    var id: UUID
    var term: String
    var meaning: String
    var note: String
    var example: String?
    var source: String
    var sourceSessionID: UUID? = nil
    var learningState: VocabularyLearningState = .new
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var nextReviewAt: Date = Date()
    var lastReviewedAt: Date? = nil
    var reviewCount: Int = 0
    var correctStreak: Int = 0
    var lapseCount: Int = 0

    init(
        id: UUID, term: String, meaning: String, note: String, example: String?, source: String,
        sourceSessionID: UUID? = nil, learningState: VocabularyLearningState = .new,
        createdAt: Date = Date(), updatedAt: Date = Date(), nextReviewAt: Date = Date(),
        lastReviewedAt: Date? = nil, reviewCount: Int = 0, correctStreak: Int = 0, lapseCount: Int = 0
    ) {
        self.id = id
        self.term = term
        self.meaning = meaning
        self.note = note
        self.example = example
        self.source = source
        self.sourceSessionID = sourceSessionID
        self.learningState = learningState
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.nextReviewAt = nextReviewAt
        self.lastReviewedAt = lastReviewedAt
        self.reviewCount = reviewCount
        self.correctStreak = correctStreak
        self.lapseCount = lapseCount
    }

    private enum CodingKeys: String, CodingKey {
        case id, term, meaning, note, example, source, sourceSessionID, learningState
        case createdAt, updatedAt, nextReviewAt, lastReviewedAt, reviewCount, correctStreak, lapseCount
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let now = Date()
        id = try values.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        term = try values.decode(String.self, forKey: .term)
        meaning = try values.decodeIfPresent(String.self, forKey: .meaning) ?? ""
        note = try values.decodeIfPresent(String.self, forKey: .note) ?? ""
        example = try values.decodeIfPresent(String.self, forKey: .example)
        source = try values.decodeIfPresent(String.self, forKey: .source) ?? ""
        sourceSessionID = try values.decodeIfPresent(UUID.self, forKey: .sourceSessionID)
        learningState = try values.decodeIfPresent(VocabularyLearningState.self, forKey: .learningState) ?? .new
        createdAt = try values.decodeIfPresent(Date.self, forKey: .createdAt) ?? now
        updatedAt = try values.decodeIfPresent(Date.self, forKey: .updatedAt) ?? createdAt
        nextReviewAt = try values.decodeIfPresent(Date.self, forKey: .nextReviewAt) ?? now
        lastReviewedAt = try values.decodeIfPresent(Date.self, forKey: .lastReviewedAt)
        reviewCount = try values.decodeIfPresent(Int.self, forKey: .reviewCount) ?? 0
        correctStreak = try values.decodeIfPresent(Int.self, forKey: .correctStreak) ?? 0
        lapseCount = try values.decodeIfPresent(Int.self, forKey: .lapseCount) ?? 0
    }

    var isDue: Bool { nextReviewAt <= Date() }

    mutating func applyReview(_ rating: VocabularyReviewRating, now: Date = Date()) {
        reviewCount += 1
        lastReviewedAt = now
        updatedAt = now
        switch rating {
        case .unknown:
            lapseCount += 1
            correctStreak = 0
            learningState = .learning
            nextReviewAt = now.addingTimeInterval(10 * 60)
        case .unsure:
            correctStreak = 0
            learningState = .learning
            nextReviewAt = now.addingTimeInterval(24 * 60 * 60)
        case .known:
            correctStreak += 1
            learningState = correctStreak >= 2 || reviewCount == 1 ? .mastered : .learning
            let days = reviewCount == 1 ? 7 : min(60, 7 * (correctStreak + 1))
            nextReviewAt = now.addingTimeInterval(Double(days) * 24 * 60 * 60)
        }
    }

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
