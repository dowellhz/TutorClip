import AppKit
import SQLite3
import XCTest
@testable import TutorClip

final class CoreBehaviorTests: XCTestCase {
    func testGeneratedQuestionRequiresProtocolBlock() {
        let raw = """
        QUESTION_METADATA
        Answer: B
        Type: Math
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

        XCTAssertEqual(TutorSessionMutation.selectAnswer("A", in: session), .incorrect(selected: "A", correct: "B"))
        XCTAssertEqual(session.studyStatus, .mistake)
        XCTAssertEqual(TutorSessionMutation.selectAnswer("B", in: session), .correct("B"))
        XCTAssertEqual(session.studyStatus, .known)
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
    func testHistoryClearReportsSuccessAndDatabaseFailure() async throws {
        let baseURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("tutorclip-history-clear-xctest-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: baseURL) }

        let workingStore = HistoryStore(baseDirectory: baseURL.appendingPathComponent("working"))
        workingStore.open()
        let saveSucceeded = await save(makeSession(), in: workingStore)
        XCTAssertTrue(saveSucceeded)
        XCTAssertFalse(workingStore.sessions.isEmpty)
        let clearSucceeded = await clear(workingStore)
        XCTAssertTrue(clearSucceeded)
        XCTAssertTrue(workingStore.sessions.isEmpty)
        workingStore.close()

        let blockedURL = baseURL.appendingPathComponent("not-a-directory")
        try FileManager.default.createDirectory(at: baseURL, withIntermediateDirectories: true)
        try Data("blocked".utf8).write(to: blockedURL)
        let blockedStore = HistoryStore(baseDirectory: blockedURL)
        blockedStore.open()
        let blockedClearSucceeded = await clear(blockedStore)
        XCTAssertFalse(blockedClearSucceeded)
        blockedStore.close()
    }

    @MainActor
    func testSettingsHistoryClearFailureIsVisibleAndLoadingEnds() async {
        let baseURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("tutorclip-history-feedback-xctest-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: baseURL) }
        let viewModel = SettingsViewModel(
            settingsStore: SettingsStore(baseDirectory: baseURL.appendingPathComponent("settings")),
            configLoader: ConfigLoader(),
            historyStore: HistoryStore(baseDirectory: baseURL.appendingPathComponent("unopened-history")),
            onShortcutChanged: {}
        )

        viewModel.clearHistory()
        for _ in 0..<100 where viewModel.isClearingHistory {
            await Task.yield()
        }

        XCTAssertFalse(viewModel.isClearingHistory)
        XCTAssertTrue(viewModel.historyStatusIsError)
        XCTAssertFalse(viewModel.historyStatusMessage.isEmpty)
    }

    @MainActor
    func testDiagnosticsRejectsCancelledRunAndKeepsLatestResult() async throws {
        let baseURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("tutorclip-diagnostics-xctest-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: baseURL) }
        var invocation = 0
        let viewModel = SettingsViewModel(
            settingsStore: SettingsStore(baseDirectory: baseURL.appendingPathComponent("settings")),
            configLoader: ConfigLoader(),
            historyStore: HistoryStore(baseDirectory: baseURL.appendingPathComponent("history")),
            onShortcutChanged: {},
            diagnosticsRunner: { _, _, _ in
                invocation += 1
                let currentInvocation = invocation
                do {
                    try await Task.sleep(nanoseconds: currentInvocation == 1 ? 80_000_000 : 5_000_000)
                } catch {
                    // Model a system probe that still produces a result after cancellation.
                }
                return [DiagnosticItem(title: currentInvocation == 1 ? "stale" : "latest", state: .pass, detail: "synthetic")]
            }
        )

        viewModel.runDiagnostics()
        await Task.yield()
        viewModel.runDiagnostics()
        try await Task.sleep(nanoseconds: 120_000_000)

        XCTAssertEqual(invocation, 2)
        XCTAssertEqual(viewModel.diagnostics.map(\.title), ["latest"])
        XCTAssertFalse(viewModel.isRunningDiagnostics)
    }

    @MainActor
    func testCancellingDiagnosticsEndsLoadingWithoutApplyingResult() async {
        let baseURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("tutorclip-diagnostics-cancel-xctest-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: baseURL) }
        let viewModel = SettingsViewModel(
            settingsStore: SettingsStore(baseDirectory: baseURL.appendingPathComponent("settings")),
            configLoader: ConfigLoader(),
            historyStore: HistoryStore(baseDirectory: baseURL.appendingPathComponent("history")),
            onShortcutChanged: {},
            diagnosticsRunner: { _, _, _ in
                try? await Task.sleep(nanoseconds: 80_000_000)
                return [DiagnosticItem(title: "late", state: .pass, detail: "synthetic")]
            }
        )

        viewModel.runDiagnostics()
        let runningPlaceholder = viewModel.diagnostics
        viewModel.cancelDiagnostics()
        await Task.yield()

        XCTAssertFalse(viewModel.isRunningDiagnostics)
        XCTAssertEqual(viewModel.diagnostics, runningPlaceholder)
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
    func testSettingsStoreReportsPersistenceSuccessAndFailure() throws {
        let baseURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("tutorclip-settings-xctest-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: baseURL) }

        let store = SettingsStore(baseDirectory: baseURL)
        let saved = store.update { $0.historyEnabled = false }
        XCTAssertTrue(saved)
        XCTAssertNil(store.persistenceError)
        XCTAssertFalse(SettingsStore(baseDirectory: baseURL).settings.historyEnabled)

        let blockedURL = baseURL.appendingPathComponent("not-a-directory")
        try Data("blocked".utf8).write(to: blockedURL)
        let blockedStore = SettingsStore(baseDirectory: blockedURL)
        let original = blockedStore.settings
        let failed = blockedStore.update { $0.historyEnabled = false }
        XCTAssertFalse(failed)
        XCTAssertNotNil(blockedStore.persistenceError)
        XCTAssertEqual(blockedStore.settings, original)
    }

    @MainActor
    func testLaunchAtLoginFailureRollsBackOnlyThatSetting() {
        let baseURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("tutorclip-launch-xctest-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: baseURL) }
        let settingsStore = SettingsStore(baseDirectory: baseURL.appendingPathComponent("settings"))
        let viewModel = SettingsViewModel(
            settingsStore: settingsStore,
            configLoader: ConfigLoader(),
            historyStore: HistoryStore(baseDirectory: baseURL.appendingPathComponent("history")),
            onShortcutChanged: {},
            updateLaunchAtLogin: { _ in throw SyntheticLaunchAtLoginError.failed }
        )
        viewModel.settings.historyEnabled = false
        viewModel.settings.launchAtLogin = true

        viewModel.save()

        XCTAssertFalse(viewModel.settings.launchAtLogin)
        XCTAssertFalse(settingsStore.settings.launchAtLogin)
        XCTAssertFalse(settingsStore.settings.historyEnabled)
        XCTAssertTrue(viewModel.saveStatusIsError)
        XCTAssertTrue(viewModel.saveStatusMessage.contains("failed"))
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

private enum SyntheticLaunchAtLoginError: LocalizedError {
    case failed

    var errorDescription: String? { "synthetic launch update failed" }
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
