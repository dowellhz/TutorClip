import XCTest
@testable import TutorClip

final class SATLearningTests: XCTestCase {
    func testReadingWritingKnowledgeCatalogHasStableCompleteMappings() {
        XCTAssertEqual(SATKnowledgeCatalog.questionTypes.count, 11)
        XCTAssertGreaterThan(SATKnowledgeCatalog.knowledgePoints.count, 80)
        XCTAssertTrue(SATKnowledgeCatalog.knowledgePoints.allSatisfy { point in
            SATKnowledgeCatalog.questionType(id: point.questionTypeID) != nil
        })
        XCTAssertEqual(Set(SATKnowledgeCatalog.knowledgePoints.map(\.id)).count, SATKnowledgeCatalog.knowledgePoints.count)
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
    func testReviewQueueAndSkillProfiles() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let mistake = makeSession(skill: "Linear equations", status: .mistake, due: now.addingTimeInterval(-100))
        let review = makeSession(skill: "Transitions", status: .needsReview, due: now.addingTimeInterval(-10))
        SATReviewScheduler.recordAnswer(selectedAnswer: "A", correctAnswer: "B", correct: false, hintUsed: false, metadata: &mistake.learningMetadata)
        SATReviewScheduler.recordAnswer(selectedAnswer: "B", correctAnswer: "B", correct: true, hintUsed: false, metadata: &review.learningMetadata)
        mistake.learningMetadata.nextReviewAt = now.addingTimeInterval(-100)
        review.learningMetadata.nextReviewAt = now.addingTimeInterval(-10)
        XCTAssertEqual(SATLearningAnalytics.reviewQueue(from: [mistake, review], now: now).map(\.studyStatus), [.needsReview, .mistake])
        XCTAssertEqual(SATLearningAnalytics.skillProfiles(from: [review, mistake]).first?.skill, "Linear equations")
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
}
