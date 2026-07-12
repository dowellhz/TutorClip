import Foundation

enum SATTeachingPurpose: String, Codable, Equatable, Hashable {
    case diagnostic
    case instruction
    case guidedRecovery
    case verification
    case consolidation
    case transfer
    case maintenance
}

struct TeachingDecision: Equatable {
    let knowledgePointID: String
    let purpose: SATTeachingPurpose
    let difficulty: SATDifficulty
    let reason: String
}

/// Chooses the next learning objective. It contains teaching policy only; UI,
/// networking, prompt construction, and persistence stay with their owners.
struct TeachingScheduler {
    private let initialDiagnosticTarget = 8
    private let dailyRequiredQuestionLimit = 5

    func nextDecision(
        evidence: [SATMasteryEvidence],
        manuallyMasteredIDs: Set<String> = [],
        respectsDailyLimit: Bool = true,
        now: Date = Date()
    ) -> TeachingDecision? {
        let validEvidence = evidence.filter(\.countsTowardMastery)
        var latestStateByPoint: [String: SATMasteryEvidence] = [:]
        for state in evidence where state.isStateSnapshot == true {
            for pointID in state.knowledgePointIDs
            where latestStateByPoint[pointID].map({ $0.answeredAt < state.answeredAt }) ?? true {
                latestStateByPoint[pointID] = state
            }
        }
        let latestStates = Array(latestStateByPoint.values)
        let deferredPointIDs = Set(latestStateByPoint.compactMap { pointID, state in
            state.nextReviewAt.map { $0 > now } == true ? pointID : nil
        })
        if respectsDailyLimit && hasCompletedRequiredPractice(validEvidence, now: now) { return nil }
        if let state = latestStates.filter({
            ($0.studyStatus == .needsReview || $0.studyStatus == .mistake)
                && ($0.nextReviewAt.map { $0 <= now } ?? true)
                && $0.knowledgePointIDs.first.map { !manuallyMasteredIDs.contains($0) } == true
        }).max(by: { $0.answeredAt < $1.answeredAt }),
           let pointID = state.knowledgePointIDs.first {
            return TeachingDecision(
                knowledgePointID: pointID,
                purpose: .guidedRecovery,
                difficulty: .easy,
                reason: "saved-learning-state-\(state.studyStatus?.rawValue ?? "unknown")"
            )
        }
        if let state = latestStates.filter({
            $0.masteryState == .pendingVerification
                && ($0.nextReviewAt.map { $0 <= now } ?? true)
                && $0.knowledgePointIDs.first.map { !manuallyMasteredIDs.contains($0) } == true
        }).max(by: { $0.answeredAt < $1.answeredAt }),
           let pointID = state.knowledgePointIDs.first {
            return TeachingDecision(
                knowledgePointID: pointID,
                purpose: .verification,
                difficulty: .medium,
                reason: "saved-pending-verification"
            )
        }
        if validEvidence.count < initialDiagnosticTarget {
            let profiles = SATLearningAnalytics.knowledgePointProfiles(from: evidence, now: now)
            let testedTypes = Set(evidence.flatMap(\.knowledgePointIDs).compactMap(SATKnowledgeCatalog.knowledgePoint).map(\.questionTypeID))
            let candidates = profiles.filter {
                $0.stage == .unseen
                    && !manuallyMasteredIDs.contains($0.id)
                    && !deferredPointIDs.contains($0.id)
                    && !testedTypes.contains($0.definition.questionTypeID)
            }
            if let target = candidates.min(by: { dailyTieBreak($0.id, now: now) < dailyTieBreak($1.id, now: now) }) {
                return TeachingDecision(
                    knowledgePointID: target.id,
                    purpose: .diagnostic,
                    difficulty: .easy,
                    reason: "broad-initial-diagnostic"
                )
            }
        }
        let latestStateDateByPoint = latestStateByPoint.mapValues(\.answeredAt)
        let unsupersededAttempts = validEvidence.filter { attempt in
            !attempt.knowledgePointIDs.contains {
                latestStateDateByPoint[$0].map { $0 > attempt.answeredAt } == true
            }
        }
        if let latestWrong = unsupersededAttempts
            .max(by: { $0.answeredAt < $1.answeredAt }),
           !latestWrong.wasCorrect,
           let pointID = latestWrong.knowledgePointIDs.first,
           !manuallyMasteredIDs.contains(pointID) {
            let difficulty: SATDifficulty = latestWrong.errorReason == .careless ? .medium : .easy
            return TeachingDecision(
                knowledgePointID: pointID,
                purpose: .guidedRecovery,
                difficulty: difficulty,
                reason: "recent-error-\(latestWrong.errorReason?.rawValue ?? "unknown")"
            )
        }
        return nextDecision(
            profiles: SATLearningAnalytics.knowledgePointProfiles(from: evidence, now: now),
            manuallyMasteredIDs: manuallyMasteredIDs.union(deferredPointIDs),
            now: now
        )
    }

    func nextDecision(
        sessions: [TutorSession],
        manuallyMasteredIDs: Set<String> = [],
        now: Date = Date()
    ) -> TeachingDecision? {
        let attempts = sessions.flatMap { $0.learningMetadata.attempts }.filter(\.countsTowardMastery)
        if hasCompletedRequiredPractice(attempts.map(\.answeredAt), totalCount: attempts.count, now: now) {
            return nil
        }
        return nextDecision(
            profiles: SATLearningAnalytics.knowledgePointProfiles(from: sessions, now: now),
            manuallyMasteredIDs: manuallyMasteredIDs,
            now: now
        )
    }

    private func nextDecision(
        profiles sourceProfiles: [SATKnowledgePointProfile],
        manuallyMasteredIDs: Set<String>,
        now: Date
    ) -> TeachingDecision? {
        let profiles = sourceProfiles.filter { !manuallyMasteredIDs.contains($0.id) }

        guard profiles.contains(where: { $0.stage != .stablyMastered }) else { return nil }
        guard var target = profiles.min(by: { left, right in
            let leftPriority = priority(left)
            let rightPriority = priority(right)
            if leftPriority != rightPriority { return leftPriority < rightPriority }
            return dailyTieBreak(left.id, now: now) < dailyTieBreak(right.id, now: now)
        }) else { return nil }
        let profileByID = Dictionary(uniqueKeysWithValues: profiles.map { ($0.id, $0) })
        if let unmetPrerequisite = SATKnowledgeGraph.prerequisites(of: target.id)
            .compactMap({ profileByID[$0] })
            .first(where: { $0.stage != .stablyMastered && $0.stage != .initiallyMastered }) {
            target = unmetPrerequisite
        }
        let purpose: SATTeachingPurpose
        let difficulty: SATDifficulty
        let reason: String

        switch target.stage {
        case .dueForReview:
            purpose = .maintenance
            difficulty = target.recommendedDifficulty
            reason = "due-review"
        case .unseen:
            purpose = .diagnostic
            difficulty = .easy
            reason = "uncovered-knowledge"
        case .learning:
            purpose = target.hasIncorrectEvidence ? .guidedRecovery : .instruction
            difficulty = .easy
            reason = target.hasIncorrectEvidence ? "recent-error" : "learning-in-progress"
        case .initiallyMastered:
            purpose = .verification
            difficulty = .medium
            reason = "verify-in-varied-context"
        case .stablyMastered:
            purpose = .transfer
            difficulty = .hard
            reason = "transfer-check"
        }
        return TeachingDecision(
            knowledgePointID: target.id,
            purpose: purpose,
            difficulty: difficulty,
            reason: reason
        )
    }

    private func priority(_ profile: SATKnowledgePointProfile) -> Int {
        switch profile.stage {
        case .dueForReview: return 0
        case .learning where profile.hasIncorrectEvidence: return 1
        case .learning: return 2
        case .initiallyMastered: return 3
        case .unseen: return 4
        case .stablyMastered: return 5
        }
    }

    private func dailyTieBreak(_ id: String, now: Date) -> UInt64 {
        let day = Int(now.timeIntervalSince1970 / 86_400)
        var hash: UInt64 = UInt64(bitPattern: Int64(day))
        for byte in id.utf8 {
            hash = (hash ^ UInt64(byte)) &* 1_099_511_628_211
        }
        return hash
    }

    private func hasCompletedRequiredPractice(_ evidence: [SATMasteryEvidence], now: Date) -> Bool {
        hasCompletedRequiredPractice(evidence.map(\.answeredAt), totalCount: evidence.count, now: now)
    }

    private func hasCompletedRequiredPractice(_ dates: [Date], totalCount: Int, now: Date) -> Bool {
        let calendar = Calendar.autoupdatingCurrent
        let completedToday = dates.filter { calendar.isDate($0, inSameDayAs: now) }.count
        if totalCount < initialDiagnosticTarget {
            return completedToday >= initialDiagnosticTarget
        }
        return completedToday >= dailyRequiredQuestionLimit
    }
}
