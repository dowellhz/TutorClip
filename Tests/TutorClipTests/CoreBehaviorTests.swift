import AppKit
import SQLite3
import XCTest
@testable import TutorClip

final class CoreBehaviorTests: XCTestCase {
    func testOCRConfidenceWarningIgnoresFewLowTitleLines() {
        let normalDocument = Array(repeating: Float(0.60), count: 53) + [0.24, 0.31]
        XCTAssertFalse(OCRConfidenceAssessment.shouldWarn(confidences: normalDocument))

        let broadlyUncertain = Array(repeating: Float(0.58), count: 10) + Array(repeating: Float(0.32), count: 5)
        XCTAssertTrue(OCRConfidenceAssessment.shouldWarn(confidences: broadlyUncertain))

        let lowMedian = Array(repeating: Float(0.42), count: 8)
        XCTAssertTrue(OCRConfidenceAssessment.shouldWarn(confidences: lowMedian))
    }

    func testOnboardingStateDefaultsToIncompleteAndPersistsCompletion() throws {
        let fresh = try JSONDecoder.tutorClip.decode(AppSettings.self, from: Data("{}".utf8))
        XCTAssertFalse(fresh.hasCompletedOnboarding)

        var completed = fresh
        completed.hasCompletedOnboarding = true
        let restored = try JSONDecoder.tutorClip.decode(
            AppSettings.self,
            from: JSONEncoder.tutorClip.encode(completed)
        )
        XCTAssertTrue(restored.hasCompletedOnboarding)
    }

    func testStructuredTableIsSentAsProtectedTabSeparatedContext() {
        var document = OCRDocument.empty()
        document.fullText = "A small SAT table"
        document.editedText = document.fullText
        document.tables = [OCRTable(
            id: UUID(),
            boundingBox: CodableRect(CGRect(x: 0, y: 0, width: 1, height: 1)),
            rows: [
                [cell("Year", row: 0, column: 0), cell("Value", row: 0, column: 1)],
                [cell("2025", row: 1, column: 0), cell("42", row: 1, column: 1)]
            ]
        )]
        document.documentTitle = OCRDocumentTitle(text: "Language Rates", boundingBox: CodableRect(.zero))
        let summary = PromptBuilder().structuredSummary(for: document)
        XCTAssertTrue(summary.contains("STRUCTURED_TABLE_1"))
        XCTAssertTrue(summary.contains("Year\tValue\n2025\t42"))
        XCTAssertTrue(summary.contains("END_STRUCTURED_TABLE_1"))

        let formattingMessages = PromptBuilder().formatOCRPrompt(document: document)
        let formattingPrompt = formattingMessages.map(\.content).joined(separator: "\n")
        XCTAssertTrue(formattingPrompt.contains("STRUCTURED_TABLE_1"))
        XCTAssertTrue(formattingPrompt.contains("Year\tValue\n2025\t42"))
        XCTAssertTrue(formattingPrompt.contains("标准 GFM Markdown 表格"))
        XCTAssertTrue(formattingPrompt.contains("DOCUMENT_TITLE\nLanguage Rates\nEND_DOCUMENT_TITLE"))
    }

    func testFormattingStructureSummaryDoesNotSendLayoutForPlainQuestion() {
        var document = OCRDocument.empty()
        document.editedText = "Plain SAT question"
        document.lines = [OCRLine(id: UUID(), text: "Plain SAT question", boundingBox: CodableRect(.zero), confidence: 1, tokenIds: [])]
        XCTAssertTrue(PromptBuilder().formattingStructureSummary(for: document).isEmpty)
        let prompt = PromptBuilder().userPrompt(action: .explainAll, document: document, selectedText: nil, customQuestion: nil, category: .reading, language: .chinese)
        XCTAssertFalse(prompt.contains("OCR 结构摘要"))
    }

    func testGFMTableDetectorRecognizesValidTableWithoutMistakingPlainPipes() {
        let table = """
        Passage text.

        | Language | Rate |
        | --- | ---: |
        | Serbian | 7.2 |
        """
        XCTAssertTrue(GFMTableDetector.containsTable(in: table))
        XCTAssertFalse(GFMTableDetector.containsTable(in: "A | B is ordinary prose."))
        XCTAssertFalse(GFMTableDetector.containsTable(in: "| A | B |\n| -- | --- |"))
    }

    func testQuestionMarkdownDocumentSeparatesMultipleTablesAndIgnoresFencedExample() {
        let markdown = """
        Intro paragraph.

        | A | B |
        | --- | --- |
        | 1 | 2 |

        Between tables.

        ```
        | Not | A table |
        | --- | --- |
        ```

        | C | D |
        | --- | --- |
        | 3 | 4 |
        """
        let document = QuestionMarkdownDocument(markdown: markdown)
        XCTAssertEqual(document.blocks.compactMap(\.table).count, 2)
        XCTAssertEqual(document.blocks.compactMap(\.table).first?.rows, [["1", "2"]])
        XCTAssertTrue(document.blocks.contains { $0.table == nil && $0.markdown.contains("Not | A table") })
    }

    func testTableInteractionContextSendsOnlyRelevantRowsOrColumns() {
        let table = QuestionMarkdownTable(
            header: ["Language", "Speech", "Information"],
            rows: [["Serbian", "7.2", "39.1"], ["Spanish", "7.7", "42.0"]],
            markdown: ""
        )
        let rowCell = TableCellReference(row: 2, column: 1, text: "7.7")
        let rowSelection = TableInteractionSelection(scope: .row, cells: [rowCell], context: "")
        XCTAssertEqual(table.context(for: rowSelection), "Language\tSpeech\tInformation\nSpanish\t7.7\t42.0")

        let columns = [
            TableCellReference(row: 1, column: 1, text: "7.2"),
            TableCellReference(row: 1, column: 2, text: "39.1")
        ]
        let columnSelection = TableInteractionSelection(scope: .compareColumns, cells: columns, context: "")
        XCTAssertEqual(table.context(for: columnSelection), "Speech\tInformation\n7.2\t39.1\n7.7\t42.0")
    }

    func testMissingChoiceFallbackCopiesOnlyOmittedSourceBlocks() {
        let source = """
        Question?
        A) One
        B) Two
        C) Three wraps
        onto another line.
        D) Four
        """
        let candidate = "Question?\n\nA) One\n\nB) Two"
        let restored = MissingChoiceFallback.restore(source: source, candidate: candidate)
        XCTAssertTrue(restored.contains("C) Three wraps\nonto another line."))
        XCTAssertTrue(restored.hasSuffix("D) Four"))
        XCTAssertEqual(restored.components(separatedBy: "A) One").count - 1, 1)
    }

    private func cell(_ text: String, row: Int, column: Int) -> OCRTableCell {
        OCRTableCell(id: UUID(), text: text, rowStart: row, rowEnd: row, columnStart: column, columnEnd: column, boundingBox: CodableRect(.zero))
    }

    func testGeneratedQuestionRequiresProtocolBlock() {
        let raw = """
        QUESTION_METADATA
        Answer: B
        Type: Math
        Section: Math
        Domain: Algebra
        Skill: Linear equations in one variable
        Difficulty: medium
        Confidence: 0.92
        END_QUESTION_METADATA
        FORMATTED_QUESTION
        What is $2 + 2$?

        A. 3
        B. 4
        END_FORMATTED_QUESTION
        """

        let parsed = GeneratedQuestion.parse(raw, requireQuestionBlock: true)

        XCTAssertEqual(parsed.question, "What is $2 + 2$?\n\nA. 3\nB. 4")
        XCTAssertEqual(parsed.answer, "B")
        XCTAssertEqual(parsed.category, .math)
        XCTAssertEqual(parsed.learningMetadata.section, .math)
        XCTAssertEqual(parsed.learningMetadata.domain, "Algebra")
        XCTAssertEqual(parsed.learningMetadata.skill, "Linear equations in one variable")
        XCTAssertEqual(parsed.learningMetadata.difficulty, .medium)
        XCTAssertTrue(GeneratedQuestion.parse("unwrapped", requireQuestionBlock: true).question.isEmpty)
    }

    @MainActor
    func testApplyingGeneratedQuestionClearsStaleSessionState() {
        let session = makeSession()

        TutorSessionMutation.applyFormattedQuestion(
            "Which choice is correct?\n\nA. One\nB. Two",
            answer: "B",
            category: .reading,
            to: session
        )

        XCTAssertNil(session.screenshotInMemory)
        XCTAssertTrue(session.messages.isEmpty)
        XCTAssertNil(session.selectedAnswer)
        XCTAssertEqual(session.correctAnswer, "B")
        XCTAssertTrue(session.vocabularyCards.isEmpty)
        XCTAssertEqual(session.studyStatus, .unreviewed)
        XCTAssertEqual(session.category, .reading)
    }

    @MainActor
    func testAnswerSelectionUpdatesLearningState() {
        let session = makeSession()
        session.correctAnswer = "B. Two"
        session.learningMetadata.correctAnswerUserConfirmed = true

        XCTAssertEqual(TutorSessionMutation.selectAnswer("A", in: session), .incorrect(selected: "A", correct: "B"))
        XCTAssertEqual(session.studyStatus, .mistake)
        XCTAssertEqual(TutorSessionMutation.selectAnswer("B", in: session), .locked("A"))
        TutorSessionMutation.beginUnscoredRetry(in: session)
        XCTAssertEqual(TutorSessionMutation.selectAnswer("B", in: session), .correct("B"))
        XCTAssertEqual(session.studyStatus, .mistake)
        XCTAssertEqual(session.learningMetadata.attempts.filter(\.countsTowardMastery).count, 1)
    }

    @MainActor
    func testHistoryMigrationUpgradesLegacySchemaAndIsIdempotent() async throws {
        let baseURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("tutorclip-xctest-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: baseURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: baseURL) }
        try createLegacyHistoryDatabase(at: baseURL.appendingPathComponent("history.sqlite"))

        let firstStore = HistoryStore(baseDirectory: baseURL)
        firstStore.open()
        let firstSaveSucceeded = await save(makeSession(), in: firstStore)
        XCTAssertTrue(firstSaveSucceeded)
        firstStore.close()

        let reopenedStore = HistoryStore(baseDirectory: baseURL)
        reopenedStore.open()
        let secondSaveSucceeded = await save(makeSession(), in: reopenedStore)
        XCTAssertTrue(secondSaveSucceeded)
        XCTAssertFalse(reopenedStore.sessions.isEmpty)
        reopenedStore.close()
    }

    @MainActor
    func testHistoryRoundTripPreservesLearningEvents() async throws {
        let baseURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("tutorclip-learning-roundtrip-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: baseURL) }
        let session = makeSession()
        session.learningMetadata.section = .math
        session.learningMetadata.domain = "Algebra"
        session.learningMetadata.skill = "Linear equations"
        SATReviewScheduler.recordAnswer(
            selectedAnswer: "B",
            correctAnswer: "B",
            correct: true,
            hintUsed: false,
            metadata: &session.learningMetadata
        )

        let store = HistoryStore(baseDirectory: baseURL)
        store.open()
        let saved = await save(session, in: store)
        XCTAssertTrue(saved)
        store.close()

        let reopened = HistoryStore(baseDirectory: baseURL)
        reopened.open()
        try await Task.sleep(nanoseconds: 100_000_000)
        let loaded = reopened.sessions.first
        XCTAssertEqual(loaded?.learningMetadata.section, .math)
        XCTAssertEqual(loaded?.learningMetadata.skill, "Linear equations")
        XCTAssertEqual(loaded?.learningMetadata.attempts.count, 1)
        XCTAssertEqual(loaded?.learningMetadata.reviews.count, 1)
        reopened.close()
    }

    @MainActor
    func testReplacingSessionCancelsFormattingAndRejectsStaleResult() async throws {
        let baseURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("tutorclip-request-xctest-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: baseURL) }
        let streamer = DelayedDeepSeekStreamer()
        let original = makeSession()
        original.ocrDocument.editedText = "Original synthetic question"
        let viewModel = TutorViewModel(
            session: original,
            isLoadingOCR: false,
            settingsStore: SettingsStore(baseDirectory: baseURL.appendingPathComponent("settings")),
            historyStore: HistoryStore(baseDirectory: baseURL.appendingPathComponent("history")),
            deepSeekClient: streamer,
            promptBuilder: PromptBuilder(),
            onRecapture: {},
            onSettings: {},
            onClose: {}
        )

        viewModel.formatOCR()
        for _ in 0..<20 where !streamer.didStart {
            await Task.yield()
        }
        XCTAssertTrue(streamer.didStart)

        let replacement = TutorSession.newSession(screenshot: nil)
        replacement.ocrDocument.editedText = "Replacement question"
        viewModel.replaceSession(replacement, isLoadingOCR: false)
        try await Task.sleep(nanoseconds: 20_000_000)

        XCTAssertTrue(streamer.didCancel)
        XCTAssertEqual(viewModel.session.id, replacement.id)
        XCTAssertEqual(viewModel.session.ocrDocument.editedText, "Replacement question")
        XCTAssertFalse(viewModel.isStreaming)
        XCTAssertEqual(viewModel.ocrFormatState, .idle)
    }

    @MainActor
    func testOCRLifecycleRejectsResultFromReplacedSession() async throws {
        let lifecycle = OCRRequestLifecycle()
        let oldSessionID = UUID()
        let newSessionID = UUID()
        var appliedSessionIDs: [UUID] = []

        lifecycle.start(sessionID: oldSessionID) {
            do {
                try await Task.sleep(nanoseconds: 80_000_000)
            } catch {
                // Simulate Vision finishing even after the surrounding task is cancelled.
            }
            return OCRDocument.empty()
        } onResult: { _ in
            appliedSessionIDs.append(oldSessionID)
        }
        lifecycle.start(sessionID: newSessionID) {
            await Task.yield()
            return OCRDocument.empty()
        } onResult: { _ in
            appliedSessionIDs.append(newSessionID)
        }

        try await Task.sleep(nanoseconds: 120_000_000)
        XCTAssertEqual(appliedSessionIDs, [newSessionID])
    }

    @MainActor
    private func makeSession() -> TutorSession {
        let session = TutorSession.newSession(screenshot: NSImage(size: NSSize(width: 8, height: 8)))
        session.messages = [
            ChatMessage(id: UUID(), sessionId: session.id, role: .assistant, content: "Synthetic response", createdAt: Date(), actionType: .explainAll)
        ]
        session.selectedAnswer = "A"
        session.vocabularyCards = [
            VocabularyCard(id: UUID(), term: "synthetic", meaning: "人工构造", note: "test", example: nil, source: "fixture")
        ]
        session.studyStatus = .mistake
        return session
    }

    @MainActor
    func testAnswerVerificationRequiresIndependentAgreement() async throws {
        let agreeing = SequenceDeepSeekStreamer(responses: [
            "ANSWER_VERIFICATION\nAnswer: A\nConfidence: 0.94\nEvidence: 1900 values are similar and 1950 values diverge.\nEND_ANSWER_VERIFICATION",
            "ANSWER_VERIFICATION\nAnswer: A\nConfidence: 0.91\nEvidence: France and US separate most between 1900 and 1950.\nEND_ANSWER_VERIFICATION"
        ])
        let accepted = try await AnswerVerificationService(client: agreeing, promptBuilder: PromptBuilder())
            .verify(question: "Question?\n\nA) One\n\nB) Two")
        XCTAssertEqual(accepted?.answer, "A")

        let conflicting = SequenceDeepSeekStreamer(responses: [
            "ANSWER_VERIFICATION\nAnswer: A\nConfidence: 0.94\nEvidence: Evidence A.\nEND_ANSWER_VERIFICATION",
            "ANSWER_VERIFICATION\nAnswer: B\nConfidence: 0.93\nEvidence: Evidence B.\nEND_ANSWER_VERIFICATION"
        ])
        let rejected = try await AnswerVerificationService(client: conflicting, promptBuilder: PromptBuilder())
            .verify(question: "Question?\n\nA) One\n\nB) Two")
        XCTAssertNil(rejected)
    }

    @MainActor
    private func save(_ session: TutorSession, in store: HistoryStore) async -> Bool {
        await withCheckedContinuation { continuation in
            store.save(session: session, enabled: true) { success in
                continuation.resume(returning: success)
            }
        }
    }

    @MainActor
    private func clear(_ store: HistoryStore) async -> Bool {
        await withCheckedContinuation { continuation in
            store.clear { success in
                continuation.resume(returning: success)
            }
        }
    }

    private func createLegacyHistoryDatabase(at url: URL) throws {
        var database: OpaquePointer?
        guard sqlite3_open(url.path, &database) == SQLITE_OK else {
            throw HistoryMigrationTestError.cannotOpenDatabase
        }
        defer { sqlite3_close(database) }
        let sql = """
        CREATE TABLE sessions (
            id TEXT PRIMARY KEY,
            title TEXT NOT NULL,
            created_at REAL NOT NULL,
            updated_at REAL NOT NULL,
            category TEXT NOT NULL,
            ocr_json TEXT NOT NULL,
            messages_json TEXT NOT NULL
        );
        """
        guard sqlite3_exec(database, sql, nil, nil, nil) == SQLITE_OK else {
            throw HistoryMigrationTestError.cannotCreateLegacySchema
        }
    }
}

private enum HistoryMigrationTestError: Error {
    case cannotOpenDatabase
    case cannotCreateLegacySchema
}

@MainActor
private final class DelayedDeepSeekStreamer: DeepSeekStreaming {
    private(set) var didStart = false
    private(set) var didCancel = false

    func stream(messages: [DeepSeekMessage], onToken: @escaping @MainActor (String) -> Void) async throws {
        didStart = true
        do {
            try await Task.sleep(nanoseconds: 500_000_000)
            onToken("FORMATTED_QUESTION\nStale result\nEND_FORMATTED_QUESTION")
        } catch is CancellationError {
            didCancel = true
            throw CancellationError()
        }
    }
}

@MainActor
private final class SequenceDeepSeekStreamer: DeepSeekStreaming {
    private var responses: [String]

    init(responses: [String]) {
        self.responses = responses
    }

    func stream(messages: [DeepSeekMessage], onToken: @escaping @MainActor (String) -> Void) async throws {
        guard !responses.isEmpty else { return }
        onToken(responses.removeFirst())
    }
}
