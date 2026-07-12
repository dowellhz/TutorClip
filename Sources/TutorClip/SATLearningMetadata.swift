import Foundation

enum SATSection: String, Codable, CaseIterable {
    case readingWriting, math, unknown
}

enum SATMasteryState: String, Codable, Equatable {
    case new, learning, pendingVerification, mastered
}

enum SATDifficulty: String, Codable, CaseIterable {
    case easy, medium, hard, unknown
}

enum SATErrorReason: String, Codable, CaseIterable, Identifiable {
    case comprehension, concept, evidence, calculation, distractor, careless, time, unknown
    var id: String { rawValue }

    func title(language: AppLanguage) -> String {
        switch self {
        case .comprehension: return language.text("没读懂题", "Comprehension")
        case .concept: return language.text("考点不会", "Concept gap")
        case .evidence: return language.text("证据定位错误", "Wrong evidence")
        case .calculation: return language.text("计算错误", "Calculation")
        case .distractor: return language.text("被干扰项误导", "Distractor")
        case .careless: return language.text("粗心", "Careless")
        case .time: return language.text("时间不足", "Time pressure")
        case .unknown: return language.text("尚未判断", "Not classified")
        }
    }
}

struct SATAnswerAttempt: Codable, Equatable, Identifiable {
    var id = UUID()
    var answeredAt = Date()
    var selectedAnswer: String?
    var correctAnswer: String?
    var wasCorrect = false
    var usedHint = false
    var durationSeconds: Int?
    var countsTowardMastery = true

    private enum CodingKeys: String, CodingKey {
        case id, answeredAt, selectedAnswer, correctAnswer, wasCorrect, usedHint, durationSeconds, countsTowardMastery
    }

    init(id: UUID = UUID(), answeredAt: Date = Date(), selectedAnswer: String?, correctAnswer: String?, wasCorrect: Bool = false, usedHint: Bool = false, durationSeconds: Int? = nil, countsTowardMastery: Bool = true) {
        self.id = id
        self.answeredAt = answeredAt
        self.selectedAnswer = selectedAnswer
        self.correctAnswer = correctAnswer
        self.wasCorrect = wasCorrect
        self.usedHint = usedHint
        self.durationSeconds = durationSeconds
        self.countsTowardMastery = countsTowardMastery
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        answeredAt = try values.decodeIfPresent(Date.self, forKey: .answeredAt) ?? Date()
        selectedAnswer = try values.decodeIfPresent(String.self, forKey: .selectedAnswer)
        correctAnswer = try values.decodeIfPresent(String.self, forKey: .correctAnswer)
        wasCorrect = try values.decodeIfPresent(Bool.self, forKey: .wasCorrect) ?? false
        usedHint = try values.decodeIfPresent(Bool.self, forKey: .usedHint) ?? false
        durationSeconds = try values.decodeIfPresent(Int.self, forKey: .durationSeconds)
        countsTowardMastery = try values.decodeIfPresent(Bool.self, forKey: .countsTowardMastery) ?? true
    }
}

struct SATReviewEvent: Codable, Equatable, Identifiable {
    var id = UUID()
    var reviewedAt = Date()
    var status: StudyStatus = .unreviewed
    var scheduledFor: Date?
}

struct SATLearningMetadata: Codable, Equatable {
    var section: SATSection = .unknown
    var domain = ""
    var skill = ""
    var questionTypeID = ""
    var knowledgePointIDs: [String] = []
    var difficulty: SATDifficulty = .unknown
    var teachingPurpose: SATTeachingPurpose?
    var variationTopic = ""
    var variationStructure = ""
    var classificationConfidence: Double = 0
    var errorReason: SATErrorReason?
    var attemptCount = 0
    var correctCount = 0
    var consecutiveCorrect = 0
    var hintUsed = false
    var pendingHintUsed = false
    var currentAttemptStartedAt: Date? = Date()
    var reviewStage = 0
    var lastReviewedAt: Date?
    var nextReviewAt: Date?
    var isAIGenerated = false
    var isAIVerified = false
    var answerConfidence: Double?
    var correctAnswerUserConfirmed = false
    var masteryState: SATMasteryState = .new
    var attempts: [SATAnswerAttempt] = []
    var answerSubmissionOpen = true
    var answerAttemptNumber = 1
    var reviews: [SATReviewEvent] = []
    var needsReviewFlow = SATNeedsReviewFlow()

    var mastery: Double {
        let scoredAttempts = attempts.filter(\.countsTowardMastery)
        let total = attempts.isEmpty ? attemptCount : scoredAttempts.count
        guard total > 0 else { return 0 }
        let correct = attempts.isEmpty ? correctCount : scoredAttempts.filter(\.wasCorrect).count
        let accuracy = Double(correct) / Double(total)
        let independentCorrect = scoredAttempts.suffix(5).filter { $0.wasCorrect && !$0.usedHint }.count
        let stability = min(Double(independentCorrect) / 3, 1)
        return min((accuracy * 0.7 + stability * 0.3) * 100, 100)
    }

    var isDue: Bool {
        guard let nextReviewAt else { return false }
        return nextReviewAt <= Date()
    }

    var canAutoGradeAnswer: Bool {
        correctAnswerUserConfirmed || (isAIVerified && (answerConfidence ?? 0) >= 0.8)
    }


    init() {}

    init(isAIGenerated: Bool) {
        self.isAIGenerated = isAIGenerated
    }

    init(questionMetadata: QuestionMetadata, isAIGenerated: Bool) {
        classificationConfidence = questionMetadata.confidence
        if questionMetadata.confidence >= 0.6 {
            section = questionMetadata.section
            domain = questionMetadata.domain
            skill = questionMetadata.skill
            if SATKnowledgeCatalog.questionType(id: questionMetadata.questionTypeID) != nil {
                questionTypeID = questionMetadata.questionTypeID
                knowledgePointIDs = SATKnowledgeCatalog.validKnowledgePointIDs(questionMetadata.knowledgePointIDs, questionTypeID: questionTypeID)
            }
            difficulty = questionMetadata.difficulty
        }
        self.isAIGenerated = isAIGenerated
        answerConfidence = questionMetadata.answerConfidence
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        section = try values.decodeIfPresent(SATSection.self, forKey: .section) ?? .unknown
        domain = try values.decodeIfPresent(String.self, forKey: .domain) ?? ""
        skill = try values.decodeIfPresent(String.self, forKey: .skill) ?? ""
        questionTypeID = try values.decodeIfPresent(String.self, forKey: .questionTypeID) ?? ""
        knowledgePointIDs = try values.decodeIfPresent([String].self, forKey: .knowledgePointIDs) ?? []
        difficulty = try values.decodeIfPresent(SATDifficulty.self, forKey: .difficulty) ?? .unknown
        teachingPurpose = try values.decodeIfPresent(SATTeachingPurpose.self, forKey: .teachingPurpose)
        variationTopic = try values.decodeIfPresent(String.self, forKey: .variationTopic) ?? ""
        variationStructure = try values.decodeIfPresent(String.self, forKey: .variationStructure) ?? ""
        classificationConfidence = try values.decodeIfPresent(Double.self, forKey: .classificationConfidence) ?? 0
        errorReason = try values.decodeIfPresent(SATErrorReason.self, forKey: .errorReason)
        attemptCount = try values.decodeIfPresent(Int.self, forKey: .attemptCount) ?? 0
        correctCount = try values.decodeIfPresent(Int.self, forKey: .correctCount) ?? 0
        consecutiveCorrect = try values.decodeIfPresent(Int.self, forKey: .consecutiveCorrect) ?? 0
        hintUsed = try values.decodeIfPresent(Bool.self, forKey: .hintUsed) ?? false
        pendingHintUsed = try values.decodeIfPresent(Bool.self, forKey: .pendingHintUsed) ?? false
        currentAttemptStartedAt = try values.decodeIfPresent(Date.self, forKey: .currentAttemptStartedAt) ?? Date()
        reviewStage = try values.decodeIfPresent(Int.self, forKey: .reviewStage) ?? 0
        lastReviewedAt = try values.decodeIfPresent(Date.self, forKey: .lastReviewedAt)
        nextReviewAt = try values.decodeIfPresent(Date.self, forKey: .nextReviewAt)
        isAIGenerated = try values.decodeIfPresent(Bool.self, forKey: .isAIGenerated) ?? false
        isAIVerified = try values.decodeIfPresent(Bool.self, forKey: .isAIVerified) ?? false
        answerConfidence = try values.decodeIfPresent(Double.self, forKey: .answerConfidence)
        correctAnswerUserConfirmed = try values.decodeIfPresent(Bool.self, forKey: .correctAnswerUserConfirmed) ?? false
        masteryState = try values.decodeIfPresent(SATMasteryState.self, forKey: .masteryState) ?? .new
        attempts = try values.decodeIfPresent([SATAnswerAttempt].self, forKey: .attempts) ?? []
        answerSubmissionOpen = try values.decodeIfPresent(Bool.self, forKey: .answerSubmissionOpen) ?? attempts.isEmpty
        answerAttemptNumber = try values.decodeIfPresent(Int.self, forKey: .answerAttemptNumber) ?? max(1, attempts.count)
        reviews = try values.decodeIfPresent([SATReviewEvent].self, forKey: .reviews) ?? []
        needsReviewFlow = try values.decodeIfPresent(SATNeedsReviewFlow.self, forKey: .needsReviewFlow) ?? SATNeedsReviewFlow()
    }
}

enum SATReviewScheduler {
    private static let intervals: [TimeInterval] = [86_400, 3 * 86_400, 7 * 86_400, 14 * 86_400, 30 * 86_400]

    static func apply(status: StudyStatus, to metadata: inout SATLearningMetadata, now: Date = Date()) {
        metadata.lastReviewedAt = now
        switch status {
        case .known:
            let intervalIndex = min(metadata.reviewStage, intervals.count - 1)
            metadata.nextReviewAt = now.addingTimeInterval(intervals[intervalIndex])
            metadata.reviewStage = min(metadata.reviewStage + 1, intervals.count - 1)
        case .needsReview:
            metadata.reviewStage = 0
            metadata.consecutiveCorrect = 0
            metadata.nextReviewAt = now
        case .mistake:
            metadata.reviewStage = 0
            metadata.consecutiveCorrect = 0
            metadata.nextReviewAt = now.addingTimeInterval(intervals[0])
        case .unreviewed:
            metadata.nextReviewAt = nil
        }
        metadata.reviews.append(SATReviewEvent(reviewedAt: now, status: status, scheduledFor: metadata.nextReviewAt))
    }

    static func recordAnswer(selectedAnswer: String?, correctAnswer: String?, correct: Bool, hintUsed: Bool, durationSeconds: Int? = nil, countsTowardMastery: Bool = true, metadata: inout SATLearningMetadata, now: Date = Date()) {
        metadata.attemptCount += 1
        metadata.hintUsed = metadata.hintUsed || hintUsed
        metadata.attempts.append(SATAnswerAttempt(
            answeredAt: now,
            selectedAnswer: selectedAnswer,
            correctAnswer: correctAnswer,
            wasCorrect: correct,
            usedHint: hintUsed,
            durationSeconds: durationSeconds,
            countsTowardMastery: countsTowardMastery
        ))
        metadata.pendingHintUsed = false
        metadata.currentAttemptStartedAt = now
        guard countsTowardMastery else { return }
        if correct {
            metadata.correctCount += 1
            metadata.consecutiveCorrect += 1
            if hintUsed {
                metadata.lastReviewedAt = now
                metadata.nextReviewAt = now
                metadata.reviews.append(SATReviewEvent(reviewedAt: now, status: .known, scheduledFor: now))
            } else {
                apply(status: .known, to: &metadata, now: now)
            }
        } else {
            metadata.consecutiveCorrect = 0
            apply(status: .mistake, to: &metadata, now: now)
        }
    }
}
