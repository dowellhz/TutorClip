import XCTest
@testable import TutorClip

final class SATLearningTests: XCTestCase {
    func testLegacyMasteryEvidenceWithoutSnapshotFlagStillDecodes() throws {
        let evidence = SATMasteryEvidence(
            id: UUID(), sessionID: UUID(), knowledgePointIDs: ["RW.SEC.FSS.SUBJECT_VERB"],
            difficulty: .easy, teachingPurpose: .diagnostic, answeredAt: Date(),
            wasCorrect: true, usedHint: false, countsTowardMastery: true,
            errorReason: nil, nextReviewAt: nil
        )
        let encoded = try JSONEncoder.tutorClip.encode(evidence)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        object.removeValue(forKey: "isStateSnapshot")
        let legacyPayload = try JSONSerialization.data(withJSONObject: object)
        let decoded = try JSONDecoder.tutorClip.decode(SATMasteryEvidence.self, from: legacyPayload)
        XCTAssertNil(decoded.isStateSnapshot)
        XCTAssertEqual(decoded.id, evidence.id)
    }

    func testReadingWritingKnowledgeCatalogHasStableCompleteMappings() {
        XCTAssertGreaterThanOrEqual(SATKnowledgeCatalog.questionTypes.count, 11)
        XCTAssertGreaterThan(SATKnowledgeCatalog.knowledgePoints.count, 80)
        XCTAssertFalse(SATKnowledgeCatalog.questionTypes.contains { $0.id.hasPrefix("MATH.") })
        XCTAssertFalse(SATKnowledgeCatalog.knowledgePoints.contains { $0.id.hasPrefix("MATH.") })
        XCTAssertTrue(SATKnowledgeCatalog.knowledgePoints.allSatisfy { point in
            SATKnowledgeCatalog.questionType(id: point.questionTypeID) != nil
        })
        XCTAssertEqual(Set(SATKnowledgeCatalog.knowledgePoints.map(\.id)).count, SATKnowledgeCatalog.knowledgePoints.count)
    }

    @MainActor
    func testSimpleKnowledgeCanReachInitialMasteryWithOneIndependentCorrect() {
        let session = makeSession(skill: "Form, Structure, and Sense", status: .known, due: .distantFuture)
        session.learningMetadata.questionTypeID = "RW.SEC.FSS"
        session.learningMetadata.knowledgePointIDs = ["RW.SEC.FSS.SUBJECT_VERB"]
        session.learningMetadata.difficulty = .easy
        SATReviewScheduler.recordAnswer(selectedAnswer: "A", correctAnswer: "A", correct: true, hintUsed: false, metadata: &session.learningMetadata)
        let profile = SATLearningAnalytics.knowledgePointProfiles(from: [session]).first { $0.id == "RW.SEC.FSS.SUBJECT_VERB" }
        XCTAssertEqual(profile?.stage, .initiallyMastered)
    }

    @MainActor
    func testTeachingSchedulerPrioritizesRecentLearningError() {
        let session = makeSession(skill: "Form, Structure, and Sense", status: .mistake, due: .distantFuture)
        session.learningMetadata.questionTypeID = "RW.SEC.FSS"
        session.learningMetadata.knowledgePointIDs = ["RW.SEC.FSS.SUBJECT_VERB"]
        SATReviewScheduler.recordAnswer(selectedAnswer: "A", correctAnswer: "B", correct: false, hintUsed: false, metadata: &session.learningMetadata)
        let decision = TeachingScheduler().nextDecision(sessions: [session])
        XCTAssertEqual(decision?.knowledgePointID, "RW.SEC.FSS.SUBJECT_VERB")
        XCTAssertEqual(decision?.purpose, .guidedRecovery)
    }

    @MainActor
    func testLearningOnlyPayloadOmitsQuestionAndConversationDetails() throws {
        let session = makeSession(skill: "Transitions", status: .known, due: .distantFuture)
        var document = OCRDocument.empty()
        document.fullText = "private question text"
        document.editedText = "private question text"
        session.ocrDocument = document
        session.messages = [ChatMessage(
            id: UUID(),
            sessionId: session.id,
            role: .user,
            content: "private chat",
            createdAt: Date()
        )]
        session.selectedAnswer = "B"
        let payload = try XCTUnwrap(HistorySavePayload(session: session, includeDetails: false, includeLearning: true))
        XCTAssertFalse(payload.ocrJSON.contains("private question text"))
        XCTAssertFalse(payload.messagesJSON.contains("private chat"))
        XCTAssertEqual(payload.selectedAnswer, "B")
    }

    @MainActor
    func testDetailedHistoryWithoutLearningOmitsMasteryEvidence() throws {
        let session = makeSession(skill: "Transitions", status: .known, due: .distantFuture)
        SATReviewScheduler.recordAnswer(selectedAnswer: "B", correctAnswer: "B", correct: true, hintUsed: false, metadata: &session.learningMetadata)
        let payload = try XCTUnwrap(HistorySavePayload(session: session, includeDetails: true, includeLearning: false))
        let learning = try JSONDecoder.tutorClip.decode(SATLearningMetadata.self, from: Data(payload.learningJSON.utf8))
        XCTAssertTrue(learning.attempts.isEmpty)
        XCTAssertNil(payload.selectedAnswer)
        XCTAssertNil(payload.correctAnswer)
    }

    func testGeneratedPracticeContractRequiresTeachingAndDistractorFields() {
        let raw = """
        FORMATTED_QUESTION
        Question\nA. One\nB. Two\nC. Three\nD. Four
        END_FORMATTED_QUESTION
        QUESTION_METADATA
        TeachingPurpose: diagnostic
        Prerequisites: none
        DistractorA: correct
        DistractorB: arithmetic slip
        DistractorC: wrong model
        DistractorD: sign error
        ExplanationBasis: substitute each value
        END_QUESTION_METADATA
        """
        XCTAssertTrue(GeneratedQuestion.parse(raw, requireQuestionBlock: true).contract.isComplete)
        XCTAssertFalse(GeneratedQuestion.parse("FORMATTED_QUESTION\nQ\nEND_FORMATTED_QUESTION").contract.isComplete)
    }

    func testLatestEvidenceControlsDueState() {
        let point = "RW.SEC.FSS.SUBJECT_VERB"
        let old = SATMasteryEvidence(id: UUID(), sessionID: UUID(), knowledgePointIDs: [point], difficulty: .easy, teachingPurpose: .diagnostic, answeredAt: Date(timeIntervalSince1970: 100), wasCorrect: true, usedHint: false, countsTowardMastery: true, errorReason: nil, nextReviewAt: Date(timeIntervalSince1970: 200))
        let recent = SATMasteryEvidence(id: UUID(), sessionID: UUID(), knowledgePointIDs: [point], difficulty: .medium, teachingPurpose: .verification, answeredAt: Date(timeIntervalSince1970: 300), wasCorrect: true, usedHint: false, countsTowardMastery: true, errorReason: nil, nextReviewAt: Date(timeIntervalSince1970: 500))
        let profile = SATLearningAnalytics.knowledgePointProfiles(from: [old, recent], now: Date(timeIntervalSince1970: 400)).first { $0.id == point }
        XCTAssertEqual(profile?.stage, .stablyMastered)
    }

    func testNewerStateSnapshotSupersedesOldWrongAttemptForScheduling() {
        let point = "RW.SEC.FSS.SUBJECT_VERB"
        let wrong = SATMasteryEvidence(
            id: UUID(), sessionID: UUID(), knowledgePointIDs: [point],
            difficulty: .easy, teachingPurpose: .diagnostic,
            answeredAt: Date(timeIntervalSince1970: 200), wasCorrect: false,
            usedHint: false, countsTowardMastery: true, errorReason: .concept,
            nextReviewAt: Date(timeIntervalSince1970: 200)
        )
        let resolved = SATMasteryEvidence(
            id: UUID(), sessionID: wrong.sessionID, knowledgePointIDs: [point],
            difficulty: .easy, teachingPurpose: .instruction,
            answeredAt: Date(timeIntervalSince1970: 300), wasCorrect: false,
            usedHint: true, countsTowardMastery: false, errorReason: nil,
            nextReviewAt: .distantFuture, studyStatus: .known,
            masteryState: .mastered, isStateSnapshot: true
        )
        let filler = (0..<7).map { index in
            SATMasteryEvidence(
                id: UUID(), sessionID: UUID(), knowledgePointIDs: [point],
                difficulty: .easy, teachingPurpose: .diagnostic,
                answeredAt: Date(timeIntervalSince1970: Double(110 + index)),
                wasCorrect: true, usedHint: false, countsTowardMastery: true,
                errorReason: nil, nextReviewAt: .distantFuture
            )
        }
        let decision = TeachingScheduler().nextDecision(
            evidence: filler + [wrong, resolved], now: Date(timeIntervalSince1970: 400)
        )
        XCTAssertNotEqual(decision?.knowledgePointID, point)
        XCTAssertNotEqual(decision?.purpose, .guidedRecovery)
    }

    func testComplexKnowledgeRequiresTransferPurpose() {
        let point = "RW.EI.RS.FAITHFUL_SYNTHESIS"
        let first = masteryEvidence(point: point, difficulty: .easy, purpose: .diagnostic, time: 100)
        let second = masteryEvidence(point: point, difficulty: .medium, purpose: .consolidation, time: 200)
        var profile = SATLearningAnalytics.knowledgePointProfiles(from: [first, second], now: Date(timeIntervalSince1970: 250)).first { $0.id == point }
        XCTAssertEqual(profile?.stage, .initiallyMastered)

        let third = masteryEvidence(point: point, difficulty: .hard, purpose: .transfer, time: 300)
        profile = SATLearningAnalytics.knowledgePointProfiles(from: [first, second, third], now: Date(timeIntervalSince1970: 350)).first { $0.id == point }
        XCTAssertEqual(profile?.stage, .stablyMastered)
    }

    func testSecondaryKnowledgeSignalsDoNotGrantMastery() {
        let primary = "RW.SEC.FSS.SUBJECT_VERB"
        let secondary = "RW.SEC.FSS.MODIFIER_PLACEMENT"
        var records: [SATMasteryEvidence] = []
        for index in 0..<3 {
            let difficulty: SATDifficulty = index == 0 ? .easy : .medium
            let purpose: SATTeachingPurpose = index == 0 ? .diagnostic : .verification
            let record = SATMasteryEvidence(
                id: UUID(),
                sessionID: UUID(),
                knowledgePointIDs: [primary, secondary],
                knowledgePointWeights: [primary: 1, secondary: 0.25],
                difficulty: difficulty,
                teachingPurpose: purpose,
                answeredAt: Date(timeIntervalSince1970: Double(index + 1) * 100),
                wasCorrect: true,
                usedHint: false,
                countsTowardMastery: true,
                errorReason: nil,
                nextReviewAt: .distantFuture
            )
            records.append(record)
        }
        let profiles = SATLearningAnalytics.knowledgePointProfiles(from: records)
        XCTAssertEqual(profiles.first { $0.id == primary }?.stage, .stablyMastered)
        XCTAssertEqual(profiles.first { $0.id == secondary }?.stage, .learning)
        XCTAssertEqual(profiles.first { $0.id == secondary }?.independentCorrectCount, 0)
        let questionTypeID = try! XCTUnwrap(SATKnowledgeCatalog.knowledgePoint(id: primary)?.questionTypeID)
        let questionType = try! XCTUnwrap(SATKnowledgeCatalog.questionType(id: questionTypeID))
        let skills = SATLearningAnalytics.skillProfiles(from: records)
        let skill = skills.first { $0.domain == questionType.domain && $0.skill == questionType.skill }
        XCTAssertEqual(skill?.section, .readingWriting)
        XCTAssertEqual(skill?.attemptCount, 3)
        XCTAssertEqual(skill?.correctCount, 3)
        XCTAssertEqual(Set(skills.map(\.id)).count, skills.count)
        XCTAssertTrue(skills.contains { $0.attemptCount == 0 && $0.mastery == 0 })
    }

    func testDifferentVariationTagsProvideVariedMasteryEvidence() {
        let point = "RW.SEC.FSS.SUBJECT_VERB"
        var first = masteryEvidence(point: point, difficulty: .medium, purpose: .diagnostic, time: 100)
        var second = masteryEvidence(point: point, difficulty: .medium, purpose: .verification, time: 200)
        first.variationKey = "natural science|evidence pattern"
        second.variationKey = "history|sentence construction"
        let profile = SATLearningAnalytics.knowledgePointProfiles(
            from: [first, second],
            now: Date(timeIntervalSince1970: 300)
        )
            .first { $0.id == point }
        XCTAssertEqual(profile?.stage, .stablyMastered)
    }

    func testQuestionMetadataAcceptsOnlyCatalogKnowledgePointsForType() {
        let raw = """
        QUESTION_METADATA
        Answer: B
        Type: grammar
        Section: Reading and Writing
        Domain: Standard English Conventions
        Skill: Boundaries
        QuestionTypeID: RW.SEC.BND
        KnowledgePoints: RW.SEC.BND.COMMA_SPLICE, MADE.UP.ID, RW.SEC.FSS.SUBJECT_VERB
        Difficulty: medium
        Confidence: 0.9
        END_QUESTION_METADATA
        """
        let extracted = QuestionMetadata.extract(from: raw).metadata
        let learning = SATLearningMetadata(questionMetadata: extracted, isAIGenerated: false)
        XCTAssertEqual(learning.questionTypeID, "RW.SEC.BND")
        XCTAssertEqual(learning.knowledgePointIDs, ["RW.SEC.BND.COMMA_SPLICE"])
    }

    func testMicroCheckProtocolExtractsQuestionChoicesAndHidesWrapper() {
        let raw = """
        Here is a quick check.
        MICRO_CHECK
        Question: Which transition shows contrast?
        A. Therefore
        B. However
        C. Similarly
        D. For example
        Answer: B
        END_MICRO_CHECK
        """
        let extracted = SATMicroCheck.extract(from: raw)
        XCTAssertEqual(extracted.check?.correctAnswer, "B")
        XCTAssertEqual(extracted.check?.choices.count, 4)
        XCTAssertFalse(extracted.body.contains("MICRO_CHECK"))
    }

    func testMicroCheckProtocolAcceptsMechanicalMarkdownAndPunctuationVariants() {
        let raw = """
        MICRO_CHECK
        Question：原句中什么时候测量心率？
        - **A)** 只在实验前
        - **B：** 只在实验后
        - **C:** 实验前后都测量
        - **D、** 没有测量
        Answer：**C**
        END_MICRO_CHECK
        """
        let extracted = SATMicroCheck.extract(from: raw)
        XCTAssertEqual(extracted.check?.correctAnswer, "C")
        XCTAssertEqual(extracted.check?.choices.count, 4)
        XCTAssertEqual(extracted.check?.question, "原句中什么时候测量心率？")
    }

    func testLearningFocusProtocolExtractsAndHidesWrapper() {
        let raw = """
        先找句子主干，再处理修饰语。
        LEARNING_FOCUS
        Type: sentence
        Text: exposure to natural sounds reduces stress
        Objective: 能说出主语、谓语和比较关系
        END_LEARNING_FOCUS
        """
        let extracted = SATLearningFocus.extract(from: raw)
        XCTAssertEqual(extracted.focus?.type, "sentence")
        XCTAssertEqual(extracted.focus?.objective, "能说出主语、谓语和比较关系")
        XCTAssertFalse(extracted.body.contains("LEARNING_FOCUS"))
    }

    func testGuidedLearningPromptForbidsOriginalAnswerDisclosure() {
        let prompt = PromptBuilder().guidedLearningSystemPrompt(language: .chinese)
        XCTAssertTrue(prompt.contains("严禁公布"))
        XCTAssertTrue(prompt.contains("原题答案"))
    }

    func testNeedsReviewFlowRoundTripsThroughLearningMetadata() throws {
        var metadata = SATLearningMetadata()
        metadata.needsReviewFlow = SATNeedsReviewFlow(
            stage: .microCheck,
            gap: .application,
            learningFocus: SATLearningFocus(type: "application", text: "trigger", objective: "choose first step"),
            microCheck: SATMicroCheck(question: "Q", choices: ["A. One", "B. Two"], correctAnswer: "B"),
            microCheckAttempts: 1,
            originalDifficulty: .hard
        )
        let data = try JSONEncoder.tutorClip.encode(metadata)
        let decoded = try JSONDecoder.tutorClip.decode(SATLearningMetadata.self, from: data)
        XCTAssertEqual(decoded.needsReviewFlow, metadata.needsReviewFlow)
    }

    func testPracticeValidationRequiresExplicitValidYes() {
        XCTAssertTrue(PracticeValidationResult.parse("Valid: yes\nReason: one answer").isValid)
        XCTAssertFalse(PracticeValidationResult.parse("Valid: no\nReason: ambiguous").isValid)
        XCTAssertFalse(PracticeValidationResult.parse("Looks fine").isValid)
    }

    func testLearningMetadataDecodesLegacyEmptyJSON() throws {
        let metadata = try JSONDecoder.tutorClip.decode(SATLearningMetadata.self, from: Data("{}".utf8))
        XCTAssertEqual(metadata.section, .unknown)
        XCTAssertTrue(metadata.attempts.isEmpty)
        XCTAssertEqual(metadata.mastery, 0)
    }

    func testLowConfidenceQuestionMetadataDoesNotPolluteSkillProfile() {
        let metadata = QuestionMetadata(answer: "B", category: .math, section: .math, domain: "Algebra", skill: "Linear equations", difficulty: .medium, confidence: 0.4)
        let learning = SATLearningMetadata(questionMetadata: metadata, isAIGenerated: false)
        XCTAssertEqual(learning.section, .unknown)
        XCTAssertTrue(learning.skill.isEmpty)
        XCTAssertEqual(learning.classificationConfidence, 0.4)
    }

    func testReviewSchedulerRecordsEventsAndMastery() {
        var metadata = SATLearningMetadata()
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        SATReviewScheduler.recordAnswer(selectedAnswer: "A", correctAnswer: "B", correct: false, hintUsed: false, durationSeconds: 40, metadata: &metadata, now: start)
        SATReviewScheduler.recordAnswer(selectedAnswer: "B", correctAnswer: "B", correct: true, hintUsed: false, durationSeconds: 25, metadata: &metadata, now: start.addingTimeInterval(60))
        XCTAssertEqual(metadata.attempts.count, 2)
        XCTAssertEqual(metadata.reviews.count, 2)
        XCTAssertGreaterThan(metadata.mastery, 0)
        XCTAssertEqual(metadata.attempts.last?.durationSeconds, 25)
    }

    func testFirstIndependentCorrectSchedulesOneDayAndHintDoesNotAdvance() {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        var independent = SATLearningMetadata()
        SATReviewScheduler.recordAnswer(selectedAnswer: "B", correctAnswer: "B", correct: true, hintUsed: false, metadata: &independent, now: start)
        XCTAssertEqual(independent.nextReviewAt, start.addingTimeInterval(86_400))
        XCTAssertEqual(independent.reviewStage, 1)

        var hinted = SATLearningMetadata()
        SATReviewScheduler.recordAnswer(selectedAnswer: "B", correctAnswer: "B", correct: true, hintUsed: true, metadata: &hinted, now: start)
        XCTAssertEqual(hinted.nextReviewAt, start)
        XCTAssertEqual(hinted.reviewStage, 0)
    }

    func testLowAnswerConfidenceRequiresConfirmation() {
        var metadata = SATLearningMetadata()
        XCTAssertFalse(metadata.canAutoGradeAnswer)
        metadata.answerConfidence = 0.5
        XCTAssertFalse(metadata.canAutoGradeAnswer)
        metadata.answerConfidence = 0.95
        XCTAssertFalse(metadata.canAutoGradeAnswer)
        metadata.isAIVerified = true
        XCTAssertTrue(metadata.canAutoGradeAnswer)
        metadata.correctAnswerUserConfirmed = true
        XCTAssertTrue(metadata.canAutoGradeAnswer)
    }

    func testLearningStateMachineSeparatesFlows() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        var known = SATLearningMetadata()
        var review = SATLearningMetadata()
        var mistake = SATLearningMetadata()
        XCTAssertNotNil(SATLearningStateMachine.apply(status: .known, metadata: &known, now: now))
        XCTAssertEqual(known.masteryState, .pendingVerification)
        XCTAssertEqual(SATLearningStateMachine.apply(status: .needsReview, metadata: &review, now: now), .teachFoundation)
        XCTAssertEqual(SATLearningStateMachine.apply(status: .mistake, metadata: &mistake, now: now), .analyzeMistake)
    }

    @MainActor
    func testUnscoredRetryStartsANewDurationClock() {
        let session = TutorSession.newSession(screenshot: nil)
        let oldStart = Date(timeIntervalSince1970: 100)
        session.learningMetadata.currentAttemptStartedAt = oldStart
        session.selectedAnswer = "A"
        TutorSessionMutation.beginUnscoredRetry(in: session)
        XCTAssertEqual(session.learningMetadata.answerAttemptNumber, 2)
        XCTAssertNil(session.selectedAnswer)
        XCTAssertGreaterThan(session.learningMetadata.currentAttemptStartedAt ?? .distantPast, oldStart)
    }

    @MainActor
    func testReviewQueueAndSkillProfiles() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let mistake = makeSession(skill: "Linear equations", status: .mistake, due: now.addingTimeInterval(-100))
        let review = makeSession(skill: "Transitions", status: .needsReview, due: now.addingTimeInterval(-10))
        SATReviewScheduler.recordAnswer(selectedAnswer: "A", correctAnswer: "B", correct: false, hintUsed: false, metadata: &mistake.learningMetadata)
        SATReviewScheduler.recordAnswer(selectedAnswer: "B", correctAnswer: "B", correct: true, hintUsed: false, metadata: &review.learningMetadata)
        mistake.learningMetadata.nextReviewAt = now.addingTimeInterval(-100)
        review.learningMetadata.nextReviewAt = now.addingTimeInterval(-10)
        XCTAssertEqual(SATLearningAnalytics.reviewQueue(from: [mistake, review], now: now).map(\.studyStatus), [.needsReview])
        XCTAssertEqual(SATLearningAnalytics.skillProfiles(from: [review, mistake]).first?.skill, "Transitions")
    }

    @MainActor
    private func makeSession(skill: String, status: StudyStatus, due: Date) -> TutorSession {
        let session = TutorSession.newSession(screenshot: nil)
        session.studyStatus = status
        session.learningMetadata.section = skill == "Transitions" ? .readingWriting : .math
        session.learningMetadata.domain = skill == "Transitions" ? "Expression of Ideas" : "Algebra"
        session.learningMetadata.skill = skill
        session.learningMetadata.nextReviewAt = due
        return session
    }

    private func masteryEvidence(point: String, difficulty: SATDifficulty, purpose: SATTeachingPurpose, time: TimeInterval) -> SATMasteryEvidence {
        SATMasteryEvidence(
            id: UUID(),
            sessionID: UUID(),
            knowledgePointIDs: [point],
            difficulty: difficulty,
            teachingPurpose: purpose,
            answeredAt: Date(timeIntervalSince1970: time),
            wasCorrect: true,
            usedHint: false,
            countsTowardMastery: true,
            errorReason: nil,
            nextReviewAt: Date(timeIntervalSince1970: time + 1_000)
        )
    }
}
