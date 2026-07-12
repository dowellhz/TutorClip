import Foundation
import XCTest
@testable import TutorClip

final class GuidedLearningBehaviorTests: XCTestCase {
    @MainActor
    func testCompleteConceptGuidanceStateChainReachesEasyPractice() {
        let (viewModel, session, baseURL) = makeViewModel(name: "complete-guidance-chain")
        defer { try? FileManager.default.removeItem(at: baseURL) }
        session.ocrDocument.editedText = "Synthetic SAT question\nA. One\nB. Two\nC. Three\nD. Four"
        session.learningMetadata.difficulty = .medium

        viewModel.setStudyStatus(.needsReview)
        XCTAssertEqual(session.learningMetadata.needsReviewFlow.stage, .chooseGap)
        XCTAssertEqual(session.learningMetadata.needsReviewFlow.questionChain.first?.role, .original)

        viewModel.selectLearningGap(.comprehension)
        XCTAssertEqual(session.learningMetadata.needsReviewFlow.stage, .planReady)
        XCTAssertEqual(session.learningMetadata.needsReviewFlow.gap, .comprehension)

        viewModel.startNeedsReviewLearning()
        XCTAssertEqual(session.learningMetadata.needsReviewFlow.stage, .foundation)
        XCTAssertEqual(viewModel.learningLoadingAction, .foundation)
        let explanation = """
        The task asks for the best description of the situation.
        LEARNING_FOCUS
        Type: task
        Text: identify what the question asks
        Objective: restate the required result
        END_LEARNING_FOCUS
        """
        _ = viewModel.applyNeedsReviewResponse(explanation, action: .guidedLearning)
        XCTAssertEqual(session.learningMetadata.needsReviewFlow.learningFocus?.type, "task")

        viewModel.cancelInFlightRequest(reason: "foundation-complete")
        viewModel.startMicroCheck()
        XCTAssertEqual(session.learningMetadata.needsReviewFlow.stage, .microCheck)
        let checkResponse = """
        MICRO_CHECK
        Question: What should the student identify?
        A. The required result
        B. A new topic
        C. The longest word
        D. The publication date
        Answer: A
        END_MICRO_CHECK
        """
        _ = viewModel.applyNeedsReviewResponse(checkResponse, action: .guidedLearning)
        XCTAssertEqual(session.learningMetadata.needsReviewFlow.microCheck?.correctAnswer, "A")

        viewModel.answerMicroCheck("A")
        XCTAssertEqual(session.learningMetadata.needsReviewFlow.stage, .easyPractice)
        XCTAssertEqual(session.learningMetadata.needsReviewFlow.completedMicroChecks.last?.wasCorrect, true)
        viewModel.cancelInFlightRequest(reason: "test-finished")
    }

    @MainActor
    func testEnglishGuidanceRequiresBarrierBeforePlanIsReady() {
        let (viewModel, session, baseURL) = makeViewModel(name: "english-guidance-chain")
        defer { try? FileManager.default.removeItem(at: baseURL) }

        viewModel.setStudyStatus(.needsReview)
        viewModel.selectLearningGap(.englishReading)
        XCTAssertEqual(session.learningMetadata.needsReviewFlow.stage, .chooseEnglishBarrier)

        viewModel.selectEnglishBarrier(.sentenceStructure)
        XCTAssertEqual(session.learningMetadata.needsReviewFlow.stage, .planReady)
        XCTAssertEqual(session.learningMetadata.needsReviewFlow.englishBarrier, .sentenceStructure)
    }

    @MainActor
    func testFoundationRegenerationClearsStaleLearningFocus() {
        let (viewModel, session, baseURL) = makeViewModel(name: "foundation-focus")
        defer { try? FileManager.default.removeItem(at: baseURL) }
        session.learningMetadata.needsReviewFlow.stage = .foundation
        session.learningMetadata.needsReviewFlow.learningFocus = SATLearningFocus(
            type: "concept", text: "stale focus", objective: "old objective"
        )

        viewModel.requestAlternativeFoundation()

        XCTAssertNil(session.learningMetadata.needsReviewFlow.learningFocus)
        XCTAssertEqual(viewModel.learningLoadingAction, .alternativeExplanation)
        viewModel.cancelInFlightRequest(reason: "test-finished")
    }

    @MainActor
    func testQuickCheckCanStartWhenModelOmittedLearningFocusProtocol() {
        let (viewModel, session, baseURL) = makeViewModel(name: "missing-learning-focus")
        defer { try? FileManager.default.removeItem(at: baseURL) }
        session.learningMetadata.needsReviewFlow.stage = .foundation
        session.learningMetadata.needsReviewFlow.gap = .concept
        session.messages = [
            ChatMessage(
                id: UUID(), sessionId: session.id, role: .assistant,
                content: "A synthetic explanation of the exact concept just taught.",
                createdAt: Date(), actionType: .guidedLearning
            )
        ]
        XCTAssertNil(session.learningMetadata.needsReviewFlow.learningFocus)

        viewModel.startMicroCheck()

        XCTAssertEqual(session.learningMetadata.needsReviewFlow.stage, .microCheck)
        XCTAssertEqual(viewModel.learningLoadingAction, .microCheck)
        XCTAssertEqual(
            session.learningMetadata.needsReviewFlow.learningFocus?.text,
            "A synthetic explanation of the exact concept just taught."
        )
        XCTAssertNil(viewModel.errorMessage)
        viewModel.cancelInFlightRequest(reason: "test-finished")
    }

    @MainActor
    func testGuidedPracticeLaunchDoesNotRewriteSourceQuestionEvidenceType() {
        let (viewModel, session, baseURL) = makeViewModel(name: "guided-practice-purpose")
        defer { try? FileManager.default.removeItem(at: baseURL) }
        session.learningMetadata.teachingPurpose = .instruction
        session.learningMetadata.difficulty = .hard
        session.learningMetadata.needsReviewFlow = SATNeedsReviewFlow(
            stage: .easyPractice, originalDifficulty: .hard
        )

        viewModel.startFoundationPractice()
        XCTAssertEqual(session.learningMetadata.teachingPurpose, .instruction)
        XCTAssertEqual(session.learningMetadata.difficulty, .hard)
        viewModel.cancelInFlightRequest(reason: "test-easy-finished")

        session.learningMetadata.needsReviewFlow.stage = .pendingVerification
        viewModel.startImmediateVerification()
        XCTAssertEqual(session.learningMetadata.teachingPurpose, .instruction)
        XCTAssertEqual(session.learningMetadata.difficulty, .hard)
        viewModel.cancelInFlightRequest(reason: "test-verification-finished")
    }

    @MainActor
    func testVerificationAnswerCompletesGuidedLoop() {
        let (viewModel, session, baseURL) = makeViewModel(name: "guided-verification-result")
        defer { try? FileManager.default.removeItem(at: baseURL) }
        prepareVerifiedAnswer("B", in: session)
        session.learningMetadata.teachingPurpose = .verification
        session.learningMetadata.needsReviewFlow.stage = .pendingVerification
        session.learningMetadata.needsReviewFlow.questionChain = [
            SATQuestionSnapshot(
                role: .verification, text: "Synthetic verification question",
                correctAnswer: "B", category: .reading, difficulty: .medium
            )
        ]

        viewModel.selectAnswer("B")

        XCTAssertEqual(session.learningMetadata.needsReviewFlow.stage, .scheduled)
        XCTAssertTrue(viewModel.learningFeedback?.contains("验证通过") == true)
    }

    @MainActor
    func testEnglishAssistedOriginalAnswerAdvancesToIndependentVerification() {
        let (viewModel, session, baseURL) = makeViewModel(name: "english-assisted-result")
        defer { try? FileManager.default.removeItem(at: baseURL) }
        prepareVerifiedAnswer("A", in: session)
        session.learningMetadata.pendingHintUsed = true
        session.learningMetadata.needsReviewFlow.stage = .originalQuestion

        viewModel.selectAnswer("A")

        XCTAssertEqual(session.learningMetadata.needsReviewFlow.stage, .pendingVerification)
        XCTAssertEqual(session.learningMetadata.masteryState, .pendingVerification)
    }

    @MainActor
    func testNextQuestionDoesNotAdvanceWhenEvidencePersistenceFails() async {
        let baseURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("tutorclip-next-question-failure-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: baseURL) }
        let settings = SettingsStore(baseDirectory: baseURL.appendingPathComponent("settings"))
        let session = TutorSession.newSession(screenshot: nil)
        session.ocrDocument.editedText = "Synthetic question\nA. One\nB. Two\nC. Three\nD. Four"
        session.learningMetadata.knowledgePointIDs = ["RW.SEC.FSS.SUBJECT_VERB"]
        session.learningMetadata.attempts = [
            SATAnswerAttempt(
                selectedAnswer: "A", correctAnswer: "A", wasCorrect: true,
                usedHint: false, countsTowardMastery: true
            )
        ]
        var nextQuestionCount = 0
        let viewModel = TutorViewModel(
            session: session, isLoadingOCR: false, settingsStore: settings,
            historyStore: HistoryStore(baseDirectory: baseURL.appendingPathComponent("history")),
            masteryEvidenceStore: MasteryEvidenceStore(baseDirectory: baseURL.appendingPathComponent("unopened-mastery")),
            deepSeekClient: GuidedNoOpStreamer(), promptBuilder: PromptBuilder(),
            onRecapture: {}, onSettings: {}, onNextQuestion: { nextQuestionCount += 1 }, onClose: {}
        )

        viewModel.continueAdaptivePractice()
        for _ in 0..<100 where viewModel.isAdvancingPractice {
            try? await Task.sleep(nanoseconds: 1_000_000)
        }

        XCTAssertFalse(viewModel.isAdvancingPractice)
        XCTAssertEqual(nextQuestionCount, 0)
        XCTAssertTrue(viewModel.errorMessage?.contains("尚未进入下一题") == true)
    }

    @MainActor
    func testNextQuestionAdvancesOnceAfterEvidencePersistenceSucceeds() async {
        let baseURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("tutorclip-next-question-success-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: baseURL) }
        let settings = SettingsStore(baseDirectory: baseURL.appendingPathComponent("settings"))
        let masteryStore = MasteryEvidenceStore(baseDirectory: baseURL.appendingPathComponent("mastery"))
        await withCheckedContinuation { continuation in
            masteryStore.open { continuation.resume() }
        }
        let session = TutorSession.newSession(screenshot: nil)
        session.ocrDocument.editedText = "Synthetic question\nA. One\nB. Two\nC. Three\nD. Four"
        session.learningMetadata.knowledgePointIDs = ["RW.SEC.FSS.SUBJECT_VERB"]
        session.learningMetadata.teachingPurpose = .verification
        session.learningMetadata.attempts = [
            SATAnswerAttempt(
                selectedAnswer: "A", correctAnswer: "A", wasCorrect: true,
                usedHint: false, countsTowardMastery: true
            )
        ]
        var nextQuestionCount = 0
        let viewModel = TutorViewModel(
            session: session, isLoadingOCR: false, settingsStore: settings,
            historyStore: HistoryStore(baseDirectory: baseURL.appendingPathComponent("history")),
            masteryEvidenceStore: masteryStore,
            deepSeekClient: GuidedNoOpStreamer(), promptBuilder: PromptBuilder(),
            onRecapture: {}, onSettings: {}, onNextQuestion: { nextQuestionCount += 1 }, onClose: {}
        )

        viewModel.continueAdaptivePractice()
        viewModel.continueAdaptivePractice()
        for _ in 0..<200 where viewModel.isAdvancingPractice {
            try? await Task.sleep(nanoseconds: 1_000_000)
        }

        XCTAssertEqual(nextQuestionCount, 1)
        XCTAssertEqual(
            masteryStore.evidence.filter { $0.isStateSnapshot != true }.count,
            1
        )
        masteryStore.close()
    }

    @MainActor
    private func makeViewModel(name: String) -> (TutorViewModel, TutorSession, URL) {
        let baseURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("tutorclip-\(name)-xctest-\(UUID().uuidString)", isDirectory: true)
        let settings = SettingsStore(baseDirectory: baseURL.appendingPathComponent("settings"))
        XCTAssertTrue(settings.update {
            $0.historyEnabled = false
            $0.learningProgressEnabled = false
        })
        let session = TutorSession.newSession(screenshot: nil)
        let viewModel = TutorViewModel(
            session: session, isLoadingOCR: false, settingsStore: settings,
            historyStore: HistoryStore(baseDirectory: baseURL.appendingPathComponent("history")),
            deepSeekClient: GuidedNoOpStreamer(), promptBuilder: PromptBuilder(),
            onRecapture: {}, onSettings: {}, onClose: {}
        )
        return (viewModel, session, baseURL)
    }

    private func prepareVerifiedAnswer(_ answer: String, in session: TutorSession) {
        session.correctAnswer = answer
        session.learningMetadata.isAIVerified = true
        session.learningMetadata.answerConfidence = 1
    }
}

@MainActor
private final class GuidedNoOpStreamer: DeepSeekStreaming {
    func stream(messages: [DeepSeekMessage], onToken: @escaping @MainActor (String) -> Void) async throws {}
}
