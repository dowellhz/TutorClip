import AppKit
import Foundation
import XCTest
@testable import TutorClip

final class SettingsBehaviorTests: XCTestCase {
    func testShortcutPolicyKeepsRequiredDefaultAndRejectsUnsafeKeys() {
        XCTAssertEqual(KeyCodeDisplay.defaultKeyCode, 31)
        XCTAssertEqual(KeyCodeDisplay.defaultModifiers, 256 | 512)
        XCTAssertEqual(KeyCodeDisplay.name(for: KeyCodeDisplay.defaultKeyCode), "O")
        for keyCode: UInt32 in [36, 48, 49, 51, 53, 117] {
            XCTAssertTrue(KeyCodeDisplay.isDisallowedShortcutKey(keyCode))
        }
        XCTAssertFalse(KeyCodeDisplay.isDisallowedShortcutKey(KeyCodeDisplay.defaultKeyCode))
    }

    @MainActor
    func testHistoryClearFailureIsVisibleAndLoadingEnds() async {
        let baseURL = temporaryDirectory("history-feedback")
        defer { try? FileManager.default.removeItem(at: baseURL) }
        let viewModel = makeViewModel(baseURL: baseURL, historyName: "unopened-history")

        viewModel.clearHistory()
        for _ in 0..<200 where viewModel.isClearingHistory {
            try? await Task.sleep(nanoseconds: 1_000_000)
        }

        XCTAssertFalse(viewModel.isClearingHistory)
        XCTAssertTrue(viewModel.historyStatusIsError)
        XCTAssertFalse(viewModel.historyStatusMessage.isEmpty)
    }

    @MainActor
    func testDiagnosticsRejectsCancelledRunAndKeepsLatestResult() async throws {
        let baseURL = temporaryDirectory("diagnostics")
        defer { try? FileManager.default.removeItem(at: baseURL) }
        var invocation = 0
        let viewModel = SettingsViewModel(
            settingsStore: SettingsStore(baseDirectory: baseURL.appendingPathComponent("settings")),
            configLoader: ConfigLoader(),
            historyStore: HistoryStore(baseDirectory: baseURL.appendingPathComponent("history")),
            onShortcutChanged: {},
            diagnosticsRunner: { _, _, _ in
                invocation += 1
                let current = invocation
                try? await Task.sleep(nanoseconds: current == 1 ? 80_000_000 : 5_000_000)
                return [DiagnosticItem(title: current == 1 ? "stale" : "latest", state: .pass, detail: "synthetic")]
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
        let baseURL = temporaryDirectory("diagnostics-cancel")
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
        let placeholder = viewModel.diagnostics
        viewModel.cancelDiagnostics()
        await Task.yield()
        XCTAssertFalse(viewModel.isRunningDiagnostics)
        XCTAssertEqual(viewModel.diagnostics, placeholder)
    }

    @MainActor
    func testSettingsStoreReportsPersistenceSuccessAndFailure() throws {
        let baseURL = temporaryDirectory("settings")
        defer { try? FileManager.default.removeItem(at: baseURL) }
        let store = SettingsStore(baseDirectory: baseURL)
        XCTAssertTrue(store.update { $0.historyEnabled = false })
        XCTAssertNil(store.persistenceError)
        XCTAssertFalse(SettingsStore(baseDirectory: baseURL).settings.historyEnabled)
        let settingsURL = baseURL.appendingPathComponent("settings.json")
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: settingsURL.path)
        _ = SettingsStore(baseDirectory: baseURL)
        let permissions = try FileManager.default.attributesOfItem(atPath: settingsURL.path)[.posixPermissions] as? NSNumber
        XCTAssertEqual(permissions?.intValue, 0o600)

        let blockedURL = baseURL.appendingPathComponent("not-a-directory")
        try Data("blocked".utf8).write(to: blockedURL)
        let blockedStore = SettingsStore(baseDirectory: blockedURL)
        let original = blockedStore.settings
        XCTAssertFalse(blockedStore.update { $0.historyEnabled = false })
        XCTAssertNotNil(blockedStore.persistenceError)
        XCTAssertEqual(blockedStore.settings, original)
    }

    @MainActor
    func testLaunchAtLoginFailureRollsBackOnlyThatSetting() {
        let baseURL = temporaryDirectory("launch")
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
    }

    @MainActor
    func testReviewWorkspaceAppliesSearchReasonSourceAndDateFilters() async {
        let baseURL = temporaryDirectory("review-filters")
        defer { try? FileManager.default.removeItem(at: baseURL) }
        let history = HistoryStore(baseDirectory: baseURL.appendingPathComponent("history"))
        history.open()
        let matching = TutorSession.newSession(screenshot: nil)
        matching.title = "Target transition review"
        matching.studyStatus = .mistake
        matching.learningMetadata.nextReviewAt = Date().addingTimeInterval(-60)
        matching.learningMetadata.errorReason = .concept
        matching.learningMetadata.isAIGenerated = true
        matching.updatedAt = Date()
        let other = TutorSession.newSession(screenshot: nil)
        other.title = "Other captured review"
        other.studyStatus = .needsReview
        other.learningMetadata.nextReviewAt = Date().addingTimeInterval(-60)
        other.learningMetadata.errorReason = .careless
        other.updatedAt = Date().addingTimeInterval(-10 * 86_400)
        for session in [matching, other] {
            let saved = await withCheckedContinuation { continuation in
                history.save(
                    session: session,
                    detailedHistoryEnabled: true,
                    learningProgressEnabled: true
                ) { continuation.resume(returning: $0) }
            }
            XCTAssertTrue(saved)
        }
        let settingsStore = SettingsStore(baseDirectory: baseURL.appendingPathComponent("settings"))
        let viewModel = HistoryViewModel(
            settingsStore: settingsStore,
            historyStore: history,
            onOpen: { _ in }
        )
        viewModel.query = "Target"
        viewModel.errorReasonFilter = .concept
        viewModel.sourceFilter = .aiGenerated
        viewModel.recentDays = 7
        XCTAssertEqual(viewModel.reviewQueue.map(\.id), [matching.id])
        viewModel.snooze(matching)
        XCTAssertEqual(viewModel.operationStatusMessage, "正在推迟…")
        XCTAssertTrue(viewModel.isSnoozing(matching))
        for _ in 0..<20 where viewModel.operationStatusMessage == "正在推迟…" {
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertEqual(viewModel.operationStatusMessage, "已推迟到明天。")
        XCTAssertFalse(viewModel.isSnoozing(matching))
        XCTAssertTrue(viewModel.reviewQueue.isEmpty)
        let unchangedDate = Date().addingTimeInterval(-120)
        matching.learningMetadata.nextReviewAt = unchangedDate
        XCTAssertTrue(settingsStore.update { $0.learningProgressEnabled = false })
        viewModel.snooze(matching)
        XCTAssertEqual(matching.learningMetadata.nextReviewAt, unchangedDate)
        XCTAssertTrue(viewModel.operationStatusIsError)
        history.close()
    }

    @MainActor
    func testClassificationCorrectionDropsIncompatibleKnowledgeTarget() throws {
        let baseURL = temporaryDirectory("classification-correction")
        defer { try? FileManager.default.removeItem(at: baseURL) }
        let point = try XCTUnwrap(SATKnowledgeCatalog.knowledgePoints.first)
        let type = try XCTUnwrap(SATKnowledgeCatalog.questionType(id: point.questionTypeID))
        let settings = SettingsStore(baseDirectory: baseURL.appendingPathComponent("settings"))
        XCTAssertTrue(settings.update {
            $0.historyEnabled = false
            $0.learningProgressEnabled = false
        })
        let session = TutorSession.newSession(screenshot: nil)
        session.learningMetadata.section = .readingWriting
        session.learningMetadata.domain = type.domain
        session.learningMetadata.skill = type.skill
        session.learningMetadata.questionTypeID = type.id
        session.learningMetadata.knowledgePointIDs = [point.id]
        let viewModel = TutorViewModel(
            session: session,
            isLoadingOCR: false,
            settingsStore: settings,
            historyStore: HistoryStore(baseDirectory: baseURL.appendingPathComponent("history")),
            deepSeekClient: SettingsNoOpDeepSeekStreamer(),
            promptBuilder: PromptBuilder(),
            onRecapture: {}, onSettings: {}, onClose: {}
        )
        viewModel.updateSATDomain(type.domain)
        XCTAssertEqual(session.learningMetadata.knowledgePointIDs, [point.id])
        viewModel.updateSATSkill("Corrected skill")
        XCTAssertTrue(session.learningMetadata.questionTypeID.isEmpty)
        XCTAssertTrue(session.learningMetadata.knowledgePointIDs.isEmpty)
    }

    @MainActor
    func testClosingEmptyWorkspaceDoesNotCreateHistoryRecord() async {
        let baseURL = temporaryDirectory("empty-workspace")
        defer { try? FileManager.default.removeItem(at: baseURL) }
        let history = HistoryStore(baseDirectory: baseURL.appendingPathComponent("history"))
        history.open()
        let viewModel = TutorViewModel(
            session: TutorSession.newSession(screenshot: nil),
            isLoadingOCR: false,
            settingsStore: SettingsStore(baseDirectory: baseURL.appendingPathComponent("settings")),
            historyStore: history,
            deepSeekClient: SettingsNoOpDeepSeekStreamer(),
            promptBuilder: PromptBuilder(),
            onRecapture: {}, onSettings: {}, onClose: {}
        )
        viewModel.closeAndPersistIfNeeded()
        try? await Task.sleep(nanoseconds: 30_000_000)
        XCTAssertTrue(history.sessions.isEmpty)
        history.close()
    }

    @MainActor
    func testReplacingDifferentSessionPersistsPreviousContent() async {
        let baseURL = temporaryDirectory("session-replacement")
        defer { try? FileManager.default.removeItem(at: baseURL) }
        let history = HistoryStore(baseDirectory: baseURL.appendingPathComponent("history"))
        history.open()
        let original = TutorSession.newSession(screenshot: nil)
        original.ocrDocument.editedText = "Synthetic previous question"
        let replacement = TutorSession.newSession(screenshot: nil)
        let viewModel = TutorViewModel(
            session: original, isLoadingOCR: false,
            settingsStore: SettingsStore(baseDirectory: baseURL.appendingPathComponent("settings")),
            historyStore: history,
            deepSeekClient: SettingsNoOpDeepSeekStreamer(), promptBuilder: PromptBuilder(),
            onRecapture: {}, onSettings: {}, onClose: {}
        )
        viewModel.persistBeforeReplacingSession(with: replacement.id)
        viewModel.replaceSession(replacement, isLoadingOCR: false)
        for _ in 0..<20 where history.sessions.first(where: { $0.id == original.id }) == nil {
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertEqual(history.sessions.first { $0.id == original.id }?.ocrDocument.editedText, "Synthetic previous question")
        XCTAssertEqual(viewModel.session.id, replacement.id)
        history.close()
    }

    @MainActor
    func testSameSessionOCRRefreshPreservesInMemoryScreenshot() {
        let baseURL = temporaryDirectory("same-session-ocr")
        defer { try? FileManager.default.removeItem(at: baseURL) }
        let session = TutorSession.newSession(screenshot: NSImage(size: NSSize(width: 20, height: 20)))
        let viewModel = TutorViewModel(
            session: session, isLoadingOCR: true,
            settingsStore: SettingsStore(baseDirectory: baseURL.appendingPathComponent("settings")),
            historyStore: HistoryStore(baseDirectory: baseURL.appendingPathComponent("history")),
            deepSeekClient: SettingsNoOpDeepSeekStreamer(), promptBuilder: PromptBuilder(),
            onRecapture: {}, onSettings: {}, onClose: {}
        )

        viewModel.replaceSession(session, isLoadingOCR: false)

        XCTAssertNotNil(viewModel.session.screenshotInMemory)
        XCTAssertFalse(viewModel.isLoadingOCR)
    }

    @MainActor
    func testLowConfidenceAnswerResultDoesNotRevealUnconfirmedAnswer() {
        let baseURL = temporaryDirectory("unconfirmed-answer")
        defer { try? FileManager.default.removeItem(at: baseURL) }
        let session = TutorSession.newSession(screenshot: nil)
        session.correctAnswer = "B"
        session.learningMetadata.isAIVerified = true
        session.learningMetadata.answerConfidence = 0.5
        session.selectedAnswer = "A"
        let viewModel = TutorViewModel(
            session: session, isLoadingOCR: false,
            settingsStore: SettingsStore(baseDirectory: baseURL.appendingPathComponent("settings")),
            historyStore: HistoryStore(baseDirectory: baseURL.appendingPathComponent("history")),
            deepSeekClient: SettingsNoOpDeepSeekStreamer(), promptBuilder: PromptBuilder(),
            onRecapture: {}, onSettings: {}, onClose: {}
        )
        XCTAssertEqual(viewModel.answerSelectionResult, .selected("A"))
        session.learningMetadata.correctAnswerUserConfirmed = true
        XCTAssertEqual(viewModel.answerSelectionResult, .incorrect(selected: "A", correct: "B"))
    }

    @MainActor
    func testChoosingErrorReasonDoesNotDuplicateExistingMistakeReview() {
        let baseURL = temporaryDirectory("mistake-reason")
        defer { try? FileManager.default.removeItem(at: baseURL) }
        let settings = SettingsStore(baseDirectory: baseURL.appendingPathComponent("settings"))
        XCTAssertTrue(settings.update {
            $0.historyEnabled = false
            $0.learningProgressEnabled = false
        })
        let session = TutorSession.newSession(screenshot: nil)
        SATReviewScheduler.recordAnswer(
            selectedAnswer: "A", correctAnswer: "B", correct: false,
            hintUsed: false, metadata: &session.learningMetadata
        )
        session.studyStatus = .mistake
        XCTAssertEqual(session.learningMetadata.reviews.count, 1)
        let viewModel = TutorViewModel(
            session: session, isLoadingOCR: false, settingsStore: settings,
            historyStore: HistoryStore(baseDirectory: baseURL.appendingPathComponent("history")),
            deepSeekClient: SettingsNoOpDeepSeekStreamer(), promptBuilder: PromptBuilder(),
            onRecapture: {}, onSettings: {}, onClose: {}
        )
        viewModel.setErrorReason(.concept)
        XCTAssertEqual(session.learningMetadata.reviews.count, 1)
        XCTAssertEqual(session.learningMetadata.errorReason, .concept)
    }

    @MainActor
    func testVocabularyStorePreservesSensesAndSupportsEditDelete() async {
        let baseURL = temporaryDirectory("vocabulary-senses")
        defer { try? FileManager.default.removeItem(at: baseURL) }
        let store = MasteryEvidenceStore(baseDirectory: baseURL)
        await withCheckedContinuation { continuation in store.open { continuation.resume() } }
        let first = VocabularyCard(
            id: UUID(), term: "command", meaning: "掌握", note: "", example: nil, source: "command of evidence"
        )
        let second = VocabularyCard(
            id: UUID(), term: "command", meaning: "命令", note: "", example: nil, source: "give a command"
        )
        for card in [first, second] {
            _ = await withCheckedContinuation { continuation in
                store.saveVocabularyCard(card) { continuation.resume(returning: $0) }
            }
        }
        XCTAssertEqual(store.vocabularyCards.count, 2)

        var edited = first
        edited.note = "熟练掌握"
        edited.sourceSessionID = UUID()
        edited.applyReview(.known, now: Date(timeIntervalSince1970: 20_000))
        let saved = await withCheckedContinuation { continuation in
            store.saveVocabularyCard(edited) { continuation.resume(returning: $0) }
        }
        XCTAssertTrue(saved)
        XCTAssertEqual(store.vocabularyCards.first { $0.id == first.id }?.note, "熟练掌握")
        let deleted = await withCheckedContinuation { continuation in
            store.deleteVocabularyCard(id: second.id) { continuation.resume(returning: $0) }
        }
        XCTAssertTrue(deleted)
        XCTAssertEqual(store.vocabularyCards.map(\.id), [first.id])
        await withCheckedContinuation { continuation in store.close { continuation.resume() } }

        let reloaded = MasteryEvidenceStore(baseDirectory: baseURL)
        await withCheckedContinuation { continuation in reloaded.open { continuation.resume() } }
        let persisted = reloaded.vocabularyCards.first
        XCTAssertEqual(persisted?.id, first.id)
        XCTAssertEqual(persisted?.learningState, .mastered)
        XCTAssertEqual(persisted?.reviewCount, 1)
        XCTAssertEqual(persisted?.sourceSessionID, edited.sourceSessionID)
        await withCheckedContinuation { continuation in reloaded.close { continuation.resume() } }
    }

    @MainActor
    func testHistoryCloseAndWaitFlushesQueuedSessionWrite() async {
        let baseURL = temporaryDirectory("termination-flush")
        defer { try? FileManager.default.removeItem(at: baseURL) }
        let store = HistoryStore(baseDirectory: baseURL)
        await withCheckedContinuation { continuation in store.open { continuation.resume() } }
        let session = TutorSession.newSession(screenshot: nil)
        session.ocrDocument.editedText = "Synthetic challenge question retained at app termination."

        store.save(session: session, enabled: true)
        store.closeAndWait()

        let reopened = HistoryStore(baseDirectory: baseURL)
        await withCheckedContinuation { continuation in reopened.open { continuation.resume() } }
        XCTAssertEqual(reopened.sessions.first?.id, session.id)
        XCTAssertEqual(reopened.sessions.first?.ocrDocument.editedText, session.ocrDocument.editedText)
        reopened.closeAndWait()
    }

    @MainActor
    private func makeViewModel(baseURL: URL, historyName: String) -> SettingsViewModel {
        SettingsViewModel(
            settingsStore: SettingsStore(baseDirectory: baseURL.appendingPathComponent("settings")),
            configLoader: ConfigLoader(),
            historyStore: HistoryStore(baseDirectory: baseURL.appendingPathComponent(historyName)),
            onShortcutChanged: {}
        )
    }

    private func temporaryDirectory(_ name: String) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("tutorclip-\(name)-xctest-\(UUID().uuidString)", isDirectory: true)
    }
}

private enum SyntheticLaunchAtLoginError: LocalizedError {
    case failed
    var errorDescription: String? { "synthetic launch update failed" }
}

@MainActor
private final class SettingsNoOpDeepSeekStreamer: DeepSeekStreaming {
    func stream(messages: [DeepSeekMessage], onToken: @escaping @MainActor (String) -> Void) async throws {}
}
