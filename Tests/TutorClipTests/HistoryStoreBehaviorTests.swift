import Foundation
import XCTest
@testable import TutorClip

final class HistoryStoreBehaviorTests: XCTestCase {
    @MainActor
    func testQuestionSnapshotViewingIsReadOnlyStateAndClearsSelection() {
        let baseURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("tutorclip-snapshot-xctest-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: baseURL) }
        let session = TutorSession.newSession(screenshot: nil)
        session.ocrDocument.editedText = "Current question\nA. One\nB. Two"
        let viewModel = TutorViewModel(
            session: session,
            isLoadingOCR: false,
            settingsStore: SettingsStore(baseDirectory: baseURL.appendingPathComponent("settings")),
            historyStore: HistoryStore(baseDirectory: baseURL.appendingPathComponent("history")),
            deepSeekClient: NoOpDeepSeekStreamer(),
            promptBuilder: PromptBuilder(),
            onRecapture: {}, onSettings: {}, onClose: {}
        )
        viewModel.selectedText = "stale selection"
        viewModel.selectedTextRect = CGRect(x: 1, y: 1, width: 2, height: 2)
        let snapshot = SATQuestionSnapshot(
            role: .original, text: "Original question", correctAnswer: "A",
            category: .reading, difficulty: .medium
        )
        viewModel.viewQuestionSnapshot(snapshot)
        XCTAssertTrue(viewModel.isViewingQuestionSnapshot)
        XCTAssertEqual(viewModel.visibleQuestionText, "Original question")
        XCTAssertTrue(viewModel.selectedText.isEmpty)
        XCTAssertNil(viewModel.selectedTextRect)
        viewModel.viewQuestionSnapshot(nil)
        XCTAssertFalse(viewModel.isViewingQuestionSnapshot)
        XCTAssertEqual(viewModel.visibleQuestionText, session.ocrDocument.editedText)
    }

    func testEmptyEvidenceStartsBroadDiagnostic() {
        let decision = TeachingScheduler().nextDecision(evidence: [], now: Date(timeIntervalSince1970: 1_700_000_000))
        XCTAssertEqual(decision?.purpose, .diagnostic)
        XCTAssertEqual(decision?.reason, "broad-initial-diagnostic")
    }

    func testInitialDiagnosticHasNaturalDailyStoppingPoint() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let point = "RW.SEC.FSS.SUBJECT_VERB"
        let evidence = (0..<8).map { index in
            SATMasteryEvidence(
                id: UUID(), sessionID: UUID(), knowledgePointIDs: [point],
                difficulty: .easy, teachingPurpose: .diagnostic,
                answeredAt: now.addingTimeInterval(Double(index)),
                wasCorrect: index.isMultiple(of: 2), usedHint: false,
                countsTowardMastery: true, errorReason: nil, nextReviewAt: .distantFuture
            )
        }
        XCTAssertNotNil(TeachingScheduler().nextDecision(evidence: Array(evidence.prefix(7)), now: now))
        XCTAssertNil(TeachingScheduler().nextDecision(evidence: evidence, now: now))
        XCTAssertNotNil(TeachingScheduler().nextDecision(
            evidence: evidence,
            respectsDailyLimit: false,
            now: now
        ))
    }

    func testSelfReportedKnownStateSchedulesIndependentVerification() {
        let point = "RW.SEC.FSS.SUBJECT_VERB"
        let state = SATMasteryEvidence(
            id: UUID(), sessionID: UUID(), knowledgePointIDs: [point],
            difficulty: .easy, teachingPurpose: .instruction, answeredAt: Date(),
            wasCorrect: false, usedHint: true, countsTowardMastery: false,
            errorReason: nil, nextReviewAt: Date(), studyStatus: .known,
            masteryState: .pendingVerification, isStateSnapshot: true
        )
        let decision = TeachingScheduler().nextDecision(evidence: [state])
        XCTAssertEqual(decision?.knowledgePointID, point)
        XCTAssertEqual(decision?.purpose, .verification)
    }

    func testSnoozedLearningStateIsNotScheduledBeforeReviewDate() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let point = "RW.SEC.FSS.SUBJECT_VERB"
        let state = SATMasteryEvidence(
            id: UUID(), sessionID: UUID(), knowledgePointIDs: [point],
            difficulty: .easy, teachingPurpose: .guidedRecovery, answeredAt: now,
            wasCorrect: false, usedHint: true, countsTowardMastery: false,
            errorReason: .concept, nextReviewAt: now.addingTimeInterval(86_400),
            studyStatus: .needsReview, masteryState: .learning, isStateSnapshot: true
        )
        let beforeDue = TeachingScheduler().nextDecision(evidence: [state], now: now)
        XCTAssertNotEqual(beforeDue?.knowledgePointID, point)
        XCTAssertNotEqual(beforeDue?.purpose, .guidedRecovery)
        let whenDue = TeachingScheduler().nextDecision(evidence: [state], now: now.addingTimeInterval(86_401))
        XCTAssertEqual(whenDue?.knowledgePointID, point)
        XCTAssertEqual(whenDue?.purpose, .guidedRecovery)
    }

    func testManualMasteryOverridesSavedRecoveryAndDiagnosticBranches() {
        let point = "RW.SEC.FSS.SUBJECT_VERB"
        let state = SATMasteryEvidence(
            id: UUID(), sessionID: UUID(), knowledgePointIDs: [point],
            difficulty: .easy, teachingPurpose: .guidedRecovery, answeredAt: Date(),
            wasCorrect: false, usedHint: true, countsTowardMastery: false,
            errorReason: .concept, nextReviewAt: Date(), studyStatus: .needsReview,
            masteryState: .learning, isStateSnapshot: true
        )
        let decision = TeachingScheduler().nextDecision(
            evidence: [state], manuallyMasteredIDs: [point]
        )
        XCTAssertNotEqual(decision?.knowledgePointID, point)
        XCTAssertNotEqual(decision?.purpose, .guidedRecovery)
    }

    @MainActor
    func testPracticeValidationChecksTeacherKnowledgeTarget() async throws {
        let client = RecordingDeepSeekStreamer(response: "Valid: yes\nReason: matches")
        let raw = """
        FORMATTED_QUESTION
        Which choice is correct?\nA. One\nB. Two\nC. Three\nD. Four
        END_FORMATTED_QUESTION
        QUESTION_METADATA
        Answer: B
        Type: grammar
        Section: Reading and Writing
        Domain: Standard English Conventions
        Skill: Form, Structure, and Sense
        QuestionTypeID: RW.SEC.FSS
        KnowledgePoints: RW.SEC.FSS.SUBJECT_VERB
        Difficulty: easy
        Confidence: 1
        TeachingPurpose: diagnostic
        Prerequisites: none
        DistractorA: agreement error
        DistractorB: correct
        DistractorC: tense error
        DistractorD: modifier error
        ExplanationBasis: subject and verb agree
        END_QUESTION_METADATA
        """
        let question = GeneratedQuestion.parse(raw, requireQuestionBlock: true)
        let result = try await PracticeQuestionValidator(client: client).validate(
            question,
            expectedQuestionTypeID: "RW.SEC.FSS",
            expectedKnowledgePointIDs: ["RW.SEC.FSS.SUBJECT_VERB"]
        )
        XCTAssertTrue(result.isValid)
        let prompt = client.messages.last?.content ?? ""
        XCTAssertTrue(prompt.contains("RW.SEC.FSS"))
        XCTAssertTrue(prompt.contains("[RW.SEC.FSS.SUBJECT_VERB]"))
    }

    @MainActor
    func testMasteryEvidenceSurvivesRestartWithoutDetailedQuestionContent() async throws {
        let baseURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("tutorclip-mastery-xctest-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: baseURL) }

        let attemptID = UUID()
        let session = masterySession(attemptID: attemptID)
        let firstStore = MasteryEvidenceStore(baseDirectory: baseURL)
        await open(firstStore)
        XCTAssertEqual(try permissions(of: baseURL), 0o700)
        let recorded = await record(session, in: firstStore, enabled: true)
        XCTAssertTrue(recorded)
        XCTAssertEqual(try permissions(of: baseURL.appendingPathComponent("mastery.sqlite")), 0o600)
        XCTAssertEqual(firstStore.evidence.filter { $0.isStateSnapshot != true }.map(\.id), [attemptID])
        XCTAssertEqual(firstStore.evidence.filter { $0.isStateSnapshot == true }.count, 1)
        XCTAssertEqual(firstStore.vocabularyCards.map(\.term), ["ephemeral-vocabulary"])

        let reloadedStore = MasteryEvidenceStore(baseDirectory: baseURL)
        await open(reloadedStore)
        let attempt = reloadedStore.evidence.first { $0.isStateSnapshot != true }
        let state = reloadedStore.evidence.first { $0.isStateSnapshot == true }
        XCTAssertEqual(attempt?.id, attemptID)
        XCTAssertEqual(attempt?.teachingPurpose, .verification)
        XCTAssertEqual(state?.studyStatus, .known)
        XCTAssertEqual(state?.masteryState, .pendingVerification)
        XCTAssertEqual(attempt?.strength(for: "RW.SEC.FSS.SUBJECT_VERB"), 1)
        XCTAssertEqual(attempt?.strength(for: "RW.SEC.FSS.MODIFIER_PLACEMENT"), 0.25)
        XCTAssertEqual(attempt?.variationKey, "natural science|use a different evidence pattern")
        XCTAssertEqual(reloadedStore.vocabularyCards.map(\.term), ["ephemeral-vocabulary"])

        let database = try Data(contentsOf: baseURL.appendingPathComponent("mastery.sqlite"))
        let rawDatabase = String(decoding: database, as: UTF8.self)
        XCTAssertFalse(rawDatabase.contains("PRIVATE-QUESTION-SENTINEL"))
        XCTAssertFalse(rawDatabase.contains("PRIVATE-CHAT-SENTINEL"))
        XCTAssertFalse(rawDatabase.contains("screenshot"))
        await close(firstStore)
        await close(reloadedStore)
    }

    @MainActor
    func testDisabledLearningProgressWritesNoMasteryEvidence() async {
        let baseURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("tutorclip-disabled-mastery-xctest-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: baseURL) }
        let store = MasteryEvidenceStore(baseDirectory: baseURL)
        await open(store)
        let recorded = await record(masterySession(attemptID: UUID()), in: store, enabled: false)
        XCTAssertTrue(recorded)
        XCTAssertTrue(store.evidence.isEmpty)
        XCTAssertTrue(store.vocabularyCards.isEmpty)
        await close(store)
    }

    @MainActor
    func testDetailedHistoryRestoresLearningFlowOnlyWhenProgressIsEnabled() async {
        let baseURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("tutorclip-learning-history-xctest-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: baseURL) }
        let store = HistoryStore(baseDirectory: baseURL)
        store.open()
        let session = masterySession(attemptID: UUID())
        session.learningMetadata.questionTypeID = "RW.SEC.FSS"
        session.learningMetadata.needsReviewFlow.stage = .microCheck
        let saved = await save(session, in: store, detailed: true, learning: true)
        XCTAssertTrue(saved)
        XCTAssertEqual(store.sessions.first?.learningMetadata.needsReviewFlow.stage, .microCheck)
        XCTAssertEqual(store.sessions.first?.learningMetadata.questionTypeID, session.learningMetadata.questionTypeID)

        let privateSession = masterySession(attemptID: UUID())
        let privateSaved = await save(privateSession, in: store, detailed: true, learning: false)
        XCTAssertTrue(privateSaved)
        let restored = store.sessions.first { $0.id == privateSession.id }
        XCTAssertTrue(restored?.learningMetadata.attempts.isEmpty == true)
        XCTAssertEqual(restored?.studyStatus, .unreviewed)
        store.close()
    }

    @MainActor
    func testStudyStatusPersistsWithoutAnswerAttempt() async {
        let baseURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("tutorclip-state-only-xctest-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: baseURL) }
        let session = masterySession(attemptID: UUID())
        session.learningMetadata.attempts = []
        session.studyStatus = .needsReview
        session.learningMetadata.masteryState = .learning
        session.learningMetadata.nextReviewAt = Date().addingTimeInterval(-1)
        let store = MasteryEvidenceStore(baseDirectory: baseURL)
        await open(store)
        let recorded = await awaitRecord(session, in: store)
        XCTAssertTrue(recorded)
        XCTAssertEqual(store.evidence.count, 1)
        XCTAssertEqual(store.evidence[0].isStateSnapshot, true)
        XCTAssertEqual(store.evidence[0].studyStatus, .needsReview)
        let decision = TeachingScheduler().nextDecision(evidence: store.evidence)
        XCTAssertEqual(decision?.knowledgePointID, "RW.SEC.FSS.SUBJECT_VERB")
        XCTAssertEqual(decision?.purpose, .guidedRecovery)

        let resolved = masterySession(attemptID: UUID())
        resolved.learningMetadata.attempts = []
        resolved.studyStatus = .known
        resolved.learningMetadata.masteryState = .mastered
        let resolvedRecorded = await awaitRecord(resolved, in: store)
        XCTAssertTrue(resolvedRecorded)
        XCTAssertEqual(store.evidence.filter { $0.isStateSnapshot == true }.count, 1)
        XCTAssertEqual(store.evidence.first { $0.isStateSnapshot == true }?.masteryState, .mastered)
        await close(store)
    }

    @MainActor
    func testResetKnowledgePointsDeletesOnlyOverlappingMasteryEvidence() async {
        let baseURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("tutorclip-reset-mastery-xctest-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: baseURL) }
        let store = MasteryEvidenceStore(baseDirectory: baseURL)
        await open(store)
        let session = masterySession(attemptID: UUID())
        let recorded = await awaitRecord(session, in: store)
        XCTAssertTrue(recorded)
        XCTAssertFalse(store.evidence.isEmpty)
        let reset = await withCheckedContinuation { continuation in
            store.resetKnowledgePoints(["RW.SEC.FSS.SUBJECT_VERB"]) {
                continuation.resume(returning: $0)
            }
        }
        XCTAssertTrue(reset)
        XCTAssertTrue(store.evidence.allSatisfy { !$0.knowledgePointIDs.contains("RW.SEC.FSS.SUBJECT_VERB") })
        XCTAssertTrue(store.evidence.contains {
            $0.knowledgePointIDs == ["RW.SEC.FSS.MODIFIER_PLACEMENT"]
                && $0.strength(for: "RW.SEC.FSS.MODIFIER_PLACEMENT") == 0.25
        })
        await close(store)
    }

    @MainActor
    func testHistoryClearReportsSuccessAndDatabaseFailure() async throws {
        let baseURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("tutorclip-history-clear-xctest-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: baseURL) }

        let workingStore = HistoryStore(baseDirectory: baseURL.appendingPathComponent("working"))
        workingStore.open()
        let didSave = await save(TutorSession.newSession(screenshot: nil), in: workingStore)
        XCTAssertTrue(didSave)
        XCTAssertFalse(workingStore.sessions.isEmpty)
        let didClear = await clear(workingStore)
        XCTAssertTrue(didClear)
        XCTAssertTrue(workingStore.sessions.isEmpty)
        workingStore.close()

        let blockedURL = baseURL.appendingPathComponent("not-a-directory")
        try FileManager.default.createDirectory(at: baseURL, withIntermediateDirectories: true)
        try Data("blocked".utf8).write(to: blockedURL)
        let blockedStore = HistoryStore(baseDirectory: blockedURL)
        blockedStore.open()
        let didClearBlockedStore = await clear(blockedStore)
        XCTAssertFalse(didClearBlockedStore)
        blockedStore.close()
    }

    @MainActor
    private func save(_ session: TutorSession, in store: HistoryStore) async -> Bool {
        await withCheckedContinuation { continuation in
            store.save(session: session, enabled: true) { continuation.resume(returning: $0) }
        }
    }

    @MainActor
    private func save(_ session: TutorSession, in store: HistoryStore, detailed: Bool, learning: Bool) async -> Bool {
        await withCheckedContinuation { continuation in
            store.save(
                session: session,
                detailedHistoryEnabled: detailed,
                learningProgressEnabled: learning
            ) { continuation.resume(returning: $0) }
        }
    }

    @MainActor
    private func clear(_ store: HistoryStore) async -> Bool {
        await withCheckedContinuation { continuation in
            store.clear { continuation.resume(returning: $0) }
        }
    }

    @MainActor
    private func open(_ store: MasteryEvidenceStore) async {
        await withCheckedContinuation { continuation in
            store.open { continuation.resume() }
        }
    }

    @MainActor
    private func close(_ store: MasteryEvidenceStore) async {
        await withCheckedContinuation { continuation in
            store.close { continuation.resume() }
        }
    }

    @MainActor
    private func record(_ session: TutorSession, in store: MasteryEvidenceStore, enabled: Bool) async -> Bool {
        await withCheckedContinuation { continuation in
            store.record(session: session, enabled: enabled) { continuation.resume(returning: $0) }
        }
    }

    @MainActor
    private func awaitRecord(_ session: TutorSession, in store: MasteryEvidenceStore) async -> Bool {
        await record(session, in: store, enabled: true)
    }

    private func masterySession(attemptID: UUID) -> TutorSession {
        var metadata = SATLearningMetadata()
        metadata.section = .readingWriting
        metadata.domain = "Information and Ideas"
        metadata.skill = "Command of Evidence"
        metadata.knowledgePointIDs = ["RW.SEC.FSS.SUBJECT_VERB", "RW.SEC.FSS.MODIFIER_PLACEMENT"]
        metadata.difficulty = .medium
        metadata.teachingPurpose = .verification
        metadata.variationTopic = "natural science"
        metadata.variationStructure = "use a different evidence pattern"
        metadata.nextReviewAt = Date().addingTimeInterval(86_400)
        metadata.attempts = [SATAnswerAttempt(
            id: attemptID,
            selectedAnswer: "B",
            correctAnswer: "B",
            wasCorrect: true
        )]
        let session = TutorSession.newSession(screenshot: nil)
        session.ocrDocument.editedText = "PRIVATE-QUESTION-SENTINEL"
        session.messages = [ChatMessage(
            id: UUID(),
            sessionId: session.id,
            role: .assistant,
            content: "PRIVATE-CHAT-SENTINEL",
            createdAt: Date()
        )]
        session.learningMetadata = metadata
        session.studyStatus = .known
        session.learningMetadata.masteryState = .pendingVerification
        session.vocabularyCards = [VocabularyCard(
            id: UUID(),
            term: "ephemeral-vocabulary",
            meaning: "短暂的",
            note: "",
            example: "",
            source: ""
        )]
        return session
    }

    private func permissions(of url: URL) throws -> Int {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        return (attributes[.posixPermissions] as? NSNumber)?.intValue ?? -1
    }
}

@MainActor
private final class NoOpDeepSeekStreamer: DeepSeekStreaming {
    func stream(
        messages: [DeepSeekMessage],
        onToken: @escaping @MainActor (String) -> Void
    ) async throws {}
}

@MainActor
private final class RecordingDeepSeekStreamer: DeepSeekStreaming {
    let response: String
    private(set) var messages: [DeepSeekMessage] = []

    init(response: String) { self.response = response }

    func stream(messages: [DeepSeekMessage], onToken: @escaping @MainActor (String) -> Void) async throws {
        self.messages = messages
        onToken(response)
    }
}
