import Foundation

enum SATLearningNextStep: Equatable {
    case scheduleVerification(Date)
    case teachFoundation
    case analyzeMistake
    case stableMastery(Date)
}

enum SATLearningStateMachine {
    static func apply(status: StudyStatus, metadata: inout SATLearningMetadata, now: Date = Date()) -> SATLearningNextStep? {
        SATReviewScheduler.apply(status: status, to: &metadata, now: now)
        switch status {
        case .known:
            if metadata.consecutiveCorrect >= 3, let next = metadata.nextReviewAt {
                metadata.masteryState = .mastered
                return .stableMastery(next)
            }
            metadata.masteryState = .pendingVerification
            return metadata.nextReviewAt.map(SATLearningNextStep.scheduleVerification)
        case .needsReview:
            metadata.masteryState = .learning
            return .teachFoundation
        case .mistake:
            metadata.masteryState = .learning
            return .analyzeMistake
        case .unreviewed:
            metadata.masteryState = .new
            return nil
        }
    }

    static func recordAnswer(selected: String, correct: String, usedHint: Bool, durationSeconds: Int?, countsTowardMastery: Bool = true, metadata: inout SATLearningMetadata, now: Date = Date()) -> Bool {
        let isCorrect = selected == correct
        SATReviewScheduler.recordAnswer(
            selectedAnswer: selected,
            correctAnswer: correct,
            correct: isCorrect,
            hintUsed: usedHint,
            durationSeconds: durationSeconds,
            countsTowardMastery: countsTowardMastery,
            metadata: &metadata,
            now: now
        )
        guard countsTowardMastery else { return isCorrect }
        if isCorrect {
            metadata.masteryState = metadata.consecutiveCorrect >= 3 && !usedHint ? .mastered : .pendingVerification
        } else {
            metadata.masteryState = .learning
        }
        return isCorrect
    }
}
