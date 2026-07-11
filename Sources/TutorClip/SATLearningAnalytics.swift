import Foundation

struct SATSkillProfile: Identifiable, Equatable {
    var id: String { "\(section.rawValue)|\(domain)|\(skill)" }
    var section: SATSection
    var domain: String
    var skill: String
    var questionCount: Int
    var attemptCount: Int
    var correctCount: Int
    var mistakeCount: Int
    var mastery: Double
    var commonErrorReason: SATErrorReason?

    var accuracy: Double {
        attemptCount == 0 ? 0 : Double(correctCount) / Double(attemptCount) * 100
    }
    var recommendedDifficulty: SATDifficulty {
        if mastery < 40 { return .easy }
        if mastery < 75 { return .medium }
        return .hard
    }
}

struct SATKnowledgePointProfile: Identifiable, Equatable {
    let definition: SATKnowledgePointDefinition
    var id: String { definition.id }
    var attemptCount: Int
    var independentCorrectCount: Int
    var mastery: Double
    var state: SATMasteryState
}

enum SATLearningAnalytics {
    static func knowledgePointProfiles(from sessions: [TutorSession]) -> [SATKnowledgePointProfile] {
        SATKnowledgeCatalog.knowledgePoints.map { point in
            let metadata = sessions.map(\.learningMetadata).filter { $0.knowledgePointIDs.contains(point.id) }
            let attempts = metadata.flatMap(\.attempts)
            let independentCorrect = attempts.filter { $0.wasCorrect && !$0.usedHint }.count
            let mastery = metadata.isEmpty ? 0 : metadata.map(\.mastery).reduce(0, +) / Double(metadata.count)
            let state: SATMasteryState
            if independentCorrect >= 4 && metadata.contains(where: { $0.difficulty != .easy }) { state = .mastered }
            else if independentCorrect >= 2 { state = .pendingVerification }
            else if !attempts.isEmpty { state = .learning }
            else { state = .new }
            return SATKnowledgePointProfile(definition: point, attemptCount: attempts.count, independentCorrectCount: independentCorrect, mastery: mastery, state: state)
        }
    }

    static func reviewQueue(from sessions: [TutorSession], now: Date = Date()) -> [TutorSession] {
        sessions.filter { session in
            guard let date = session.learningMetadata.nextReviewAt else { return false }
            return date <= now
        }.sorted { left, right in
            let leftRank = priority(left.studyStatus)
            let rightRank = priority(right.studyStatus)
            if leftRank != rightRank { return leftRank < rightRank }
            return (left.learningMetadata.nextReviewAt ?? .distantFuture) < (right.learningMetadata.nextReviewAt ?? .distantFuture)
        }
    }

    static func skillProfiles(from sessions: [TutorSession]) -> [SATSkillProfile] {
        let grouped = Dictionary(grouping: sessions.filter { !$0.learningMetadata.skill.isEmpty }) {
            "\($0.learningMetadata.section.rawValue)|\($0.learningMetadata.domain)|\($0.learningMetadata.skill)"
        }
        return grouped.values.map { items in
            let metadata = items.map(\.learningMetadata)
            let attempts = metadata.flatMap(\.attempts)
            let reasons = items.compactMap { $0.learningMetadata.errorReason }
            let reason = Dictionary(grouping: reasons, by: { $0 }).max { $0.value.count < $1.value.count }?.key
            return SATSkillProfile(
                section: metadata[0].section,
                domain: metadata[0].domain,
                skill: metadata[0].skill,
                questionCount: items.count,
                attemptCount: attempts.count,
                correctCount: attempts.filter(\.wasCorrect).count,
                mistakeCount: items.filter { $0.studyStatus == .mistake }.count,
                mastery: metadata.map(\.mastery).reduce(0, +) / Double(metadata.count),
                commonErrorReason: reason
            )
        }.sorted { $0.mastery < $1.mastery }
    }

    private static func priority(_ status: StudyStatus) -> Int {
        switch status {
        case .needsReview: return 0
        case .mistake: return 1
        case .known: return 2
        case .unreviewed: return 3
        }
    }
}
