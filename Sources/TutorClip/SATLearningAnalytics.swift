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
    var stage: SATMasteryStage
    var hasIncorrectEvidence: Bool
    var recommendedDifficulty: SATDifficulty
}

enum SATMasteryStage: String, Codable, Equatable {
    case unseen
    case learning
    case initiallyMastered
    case stablyMastered
    case dueForReview
}

enum SATLearningAnalytics {
    static func knowledgePointProfiles(from evidence: [SATMasteryEvidence], now: Date = Date()) -> [SATKnowledgePointProfile] {
        SATKnowledgeCatalog.knowledgePoints.map { point in
            let allSignals = evidence.filter { $0.knowledgePointIDs.contains(point.id) }
            let records = allSignals.filter(\.countsTowardMastery)
            let strongRecords = records.filter { $0.strength(for: point.id) >= 0.75 }
            let independentCorrect = strongRecords.filter { $0.wasCorrect && !$0.usedHint }.count
            let variedDifficultyCount = Set(strongRecords.filter { $0.wasCorrect && !$0.usedHint }.map(\.difficulty).filter { $0 != .unknown }).count
            let purposes = Set(strongRecords.filter { $0.wasCorrect && !$0.usedHint }.compactMap(\.teachingPurpose))
            let variationCount = Set(strongRecords.filter { $0.wasCorrect && !$0.usedHint }.compactMap(\.variationKey)).count
            let stateSnapshots = allSignals.filter { $0.isStateSnapshot == true }
            let latestState = stateSnapshots.max { $0.answeredAt < $1.answeredAt }
            let isDue = (strongRecords + stateSnapshots)
                .max(by: { $0.answeredAt < $1.answeredAt })?.nextReviewAt.map { $0 <= now } ?? false
            var stage = masteryStage(
                attemptCount: records.count,
                independentCorrect: independentCorrect,
                variedDifficultyCount: variedDifficultyCount,
                isDue: isDue,
                complexity: SATKnowledgeGraph.complexity(of: point.id),
                purposes: purposes,
                variationCount: variationCount
            )
            let stateNeedsLearning = latestState?.studyStatus == .needsReview || latestState?.studyStatus == .mistake
            if stage == .unseen, stateNeedsLearning { stage = .learning }
            if stage == .unseen, latestState?.masteryState == .pendingVerification {
                stage = .initiallyMastered
            }
            return profile(
                point: point,
                attemptCount: records.count,
                independentCorrect: independentCorrect,
                mastery: evidenceMastery(records, knowledgePointID: point.id),
                stage: stage,
                hasIncorrect: records.contains { !$0.wasCorrect } || stateNeedsLearning
            )
        }
    }

    static func knowledgePointProfiles(from sessions: [TutorSession], now: Date = Date()) -> [SATKnowledgePointProfile] {
        SATKnowledgeCatalog.knowledgePoints.map { point in
            let metadata = sessions.map(\.learningMetadata).filter { $0.knowledgePointIDs.contains(point.id) }
            let primaryMetadata = metadata.filter { $0.knowledgePointIDs.first == point.id }
            let attempts = metadata.flatMap(\.attempts)
            let primaryAttempts = primaryMetadata.flatMap(\.attempts)
            let independentCorrect = primaryAttempts.filter { $0.wasCorrect && !$0.usedHint }.count
            let mastery = primaryMetadata.isEmpty ? 0 : primaryMetadata.map(\.mastery).reduce(0, +) / Double(primaryMetadata.count)
            let independentMetadata = primaryMetadata.filter { item in
                item.attempts.contains { $0.wasCorrect && !$0.usedHint && $0.countsTowardMastery }
            }
            let variedDifficultyCount = Set(independentMetadata.map(\.difficulty).filter { $0 != .unknown }).count
            let hasIncorrect = attempts.contains { !$0.wasCorrect && $0.countsTowardMastery }
            let latestMetadata = metadata.max { left, right in
                (left.lastReviewedAt ?? .distantPast) < (right.lastReviewedAt ?? .distantPast)
            }
            let isDue = latestMetadata?.nextReviewAt.map { $0 <= now } ?? false
            let purposes = Set(independentMetadata.compactMap(\.teachingPurpose))
            let variationCount = Set(independentMetadata.map {
                [$0.variationTopic, $0.variationStructure].filter { !$0.isEmpty }.joined(separator: "|")
            }.filter { !$0.isEmpty }).count
            let stage = masteryStage(attemptCount: attempts.count, independentCorrect: independentCorrect, variedDifficultyCount: variedDifficultyCount, isDue: isDue, complexity: SATKnowledgeGraph.complexity(of: point.id), purposes: purposes, variationCount: variationCount)
            return profile(point: point, attemptCount: attempts.count, independentCorrect: independentCorrect, mastery: mastery, stage: stage, hasIncorrect: hasIncorrect)
        }
    }

    static func reviewQueue(from sessions: [TutorSession], now: Date = Date()) -> [TutorSession] {
        sessions.filter { session in
            guard session.learningMetadata.section != .math, session.category != .math else { return false }
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
        let supported = sessions.filter {
            $0.learningMetadata.section == .readingWriting && !$0.learningMetadata.skill.isEmpty
        }
        let grouped = Dictionary(grouping: supported) {
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

    static func skillProfiles(from evidence: [SATMasteryEvidence]) -> [SATSkillProfile] {
        let attempts = evidence.filter { record in
            record.countsTowardMastery
                && record.knowledgePointIDs.first.map { record.strength(for: $0) >= 0.75 } == true
        }
        let knowledgeProfiles = Dictionary(uniqueKeysWithValues:
            knowledgePointProfiles(from: evidence).map { ($0.id, $0) }
        )
        let skillDefinitions = Dictionary(grouping: SATKnowledgeCatalog.questionTypes) { type in
            let section: SATSection = .readingWriting
            return "\(section.rawValue)|\(type.domain)|\(type.skill)"
        }
        return skillDefinitions.values.compactMap { types in
            guard let representative = types.first else { return nil }
            let section: SATSection = .readingWriting
            let typeIDs = Set(types.map(\.id))
            let pointIDs = Set(SATKnowledgeCatalog.knowledgePoints.filter {
                typeIDs.contains($0.questionTypeID)
            }.map(\.id))
            let records = attempts.filter { record in
                record.knowledgePointIDs.first.map(pointIDs.contains) == true
            }
            let masteryValues = pointIDs.compactMap { knowledgeProfiles[$0]?.mastery }
            let reasons = records.compactMap(\.errorReason)
            let commonReason = Dictionary(grouping: reasons, by: { $0 })
                .max { $0.value.count < $1.value.count }?.key
            return SATSkillProfile(
                section: section,
                domain: representative.domain,
                skill: representative.skill,
                questionCount: Set(records.map(\.sessionID)).count,
                attemptCount: records.count,
                correctCount: records.filter(\.wasCorrect).count,
                mistakeCount: records.filter { !$0.wasCorrect }.count,
                mastery: masteryValues.isEmpty ? 0 : masteryValues.reduce(0, +) / Double(masteryValues.count),
                commonErrorReason: commonReason
            )
        }.sorted {
            if $0.mastery != $1.mastery { return $0.mastery < $1.mastery }
            return $0.id.localizedStandardCompare($1.id) == .orderedAscending
        }
    }

    private static func priority(_ status: StudyStatus) -> Int {
        switch status {
        case .needsReview: return 0
        case .mistake: return 1
        case .known: return 2
        case .unreviewed: return 3
        }
    }

    private static func masteryStage(attemptCount: Int, independentCorrect: Int, variedDifficultyCount: Int, isDue: Bool, complexity: SATKnowledgeComplexity, purposes: Set<SATTeachingPurpose>, variationCount: Int) -> SATMasteryStage {
        if isDue, independentCorrect > 0 { return .dueForReview }
        let hasTransferEvidence = purposes.contains(.verification) || purposes.contains(.transfer)
        if complexity == .complex,
           independentCorrect >= 3,
           variedDifficultyCount >= 2 || variationCount >= 2,
           purposes.count >= 2,
           hasTransferEvidence { return .stablyMastered }
        if complexity != .complex,
           independentCorrect >= 2,
           variedDifficultyCount >= 2 || variationCount >= 2 { return .stablyMastered }
        if independentCorrect >= 1, complexity == .simple || independentCorrect >= 2 { return .initiallyMastered }
        return attemptCount > 0 ? .learning : .unseen
    }

    private static func profile(point: SATKnowledgePointDefinition, attemptCount: Int, independentCorrect: Int, mastery: Double, stage: SATMasteryStage, hasIncorrect: Bool) -> SATKnowledgePointProfile {
        let state: SATMasteryState
        switch stage {
        case .unseen: state = .new
        case .learning: state = .learning
        case .initiallyMastered, .dueForReview: state = .pendingVerification
        case .stablyMastered: state = .mastered
        }
        let difficulty: SATDifficulty = stage == .stablyMastered ? .hard : (stage == .initiallyMastered ? .medium : .easy)
        return SATKnowledgePointProfile(definition: point, attemptCount: attemptCount, independentCorrectCount: independentCorrect, mastery: mastery, state: state, stage: stage, hasIncorrectEvidence: hasIncorrect, recommendedDifficulty: difficulty)
    }

    private static func evidenceMastery(_ evidence: [SATMasteryEvidence], knowledgePointID: String) -> Double {
        guard !evidence.isEmpty else { return 0 }
        let totalWeight = evidence.reduce(0) { $0 + $1.strength(for: knowledgePointID) }
        guard totalWeight > 0 else { return 0 }
        let correctWeight = evidence.filter(\.wasCorrect).reduce(0) { $0 + $1.strength(for: knowledgePointID) }
        let independent = evidence.filter {
            $0.wasCorrect && !$0.usedHint && $0.strength(for: knowledgePointID) >= 0.75
        }.count
        return min((correctWeight / totalWeight * 0.7 + min(Double(independent) / 2, 1) * 0.3) * 100, 100)
    }
}
