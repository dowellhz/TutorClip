import Combine
import Foundation

enum DiagnosticUIProbe {
    static func runSelectionUIPolicyProbe() {
        let actions = TutorAction.selectedTextActions
        let onlyAllowedActions = actions == [.translateSelection, .vocabulary]
        let sourceActions = TutorAction.sourceLeadingActions + TutorAction.sourceTrailingActions
        let sourceOnlyAllowedActions = sourceActions == [.vocabulary, .grammar, .practiceSimilar, .translateAll, .explainAll]
        let hiddenActionsAreNotVisible = !sourceActions.contains(.formatOCR)
            && !sourceActions.contains(.checkOCR)
            && !sourceActions.contains(.explainSelection)
            && !actions.contains(.explainSelection)
        let titlesDoNotWrap = actions.allSatisfy { action in
            !action.title(language: .chinese).contains("\n")
                && !action.title(language: .english).contains("\n")
        } && sourceActions.allSatisfy { action in
            !action.title(language: .chinese).contains("\n")
                && !action.title(language: .english).contains("\n")
        }
        print("selectionActions=\(actions.map(\.rawValue).joined(separator: ","))")
        print("sourceActions=\(sourceActions.map(\.rawValue).joined(separator: ","))")
        print("selectionOnlyTranslateVocabulary=\(onlyAllowedActions)")
        print("sourceOnlyAllowedActions=\(sourceOnlyAllowedActions)")
        print("hiddenActionsAreNotVisible=\(hiddenActionsAreNotVisible)")
        print("selectionTitlesDoNotWrap=\(titlesDoNotWrap)")
        if !onlyAllowedActions || !sourceOnlyAllowedActions || !hiddenActionsAreNotVisible || !titlesDoNotWrap {
            fputs("Selection UI policy probe failed.\n", stderr)
            exit(2)
        }
    }

    static func runWindowPositioningProbe() {
        let visibleFrame = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let windowSize = CGSize(width: 700, height: 520)
        let gap: CGFloat = 16
        let roomySelection = CGRect(x: 340, y: 620, width: 360, height: 120)
        let crowdedSelection = CGRect(x: 360, y: 300, width: 720, height: 300)
        let roomyFrame = positionedFrame(size: windowSize, selection: roomySelection, visibleFrame: visibleFrame, gap: gap)
        let crowdedFrame = positionedFrame(size: windowSize, selection: crowdedSelection, visibleFrame: visibleFrame, gap: gap)
        let roomyAvoidsSelection = area(roomyFrame.intersection(roomySelection)) == 0
        let staysOnScreen = visibleFrame.contains(roomyFrame) && visibleFrame.contains(crowdedFrame)
        let crowdedOverlap = area(crowdedFrame.intersection(crowdedSelection))
        let centeredOverlap = area(CGRect(
            x: crowdedSelection.midX - windowSize.width / 2,
            y: crowdedSelection.midY - windowSize.height / 2,
            width: windowSize.width,
            height: windowSize.height
        ).intersection(crowdedSelection))
        let crowdedImprovesOverlap = crowdedOverlap < centeredOverlap
        print("roomyAvoidsSelection=\(roomyAvoidsSelection)")
        print("staysOnScreen=\(staysOnScreen)")
        print("crowdedOverlap=\(crowdedOverlap)")
        print("centeredOverlap=\(centeredOverlap)")
        print("crowdedImprovesOverlap=\(crowdedImprovesOverlap)")
        if !roomyAvoidsSelection || !staysOnScreen || !crowdedImprovesOverlap {
            fputs("Window positioning probe failed.\n", stderr)
            exit(2)
        }
    }

    static func runAnswerUIRefreshProbe() {
        let passed = MainActor.assumeIsolated {
            evaluateAnswerUIRefreshProbe()
        }
        if !passed {
            fputs("Answer UI refresh probe failed.\n", stderr)
            exit(2)
        }
    }

    static func runStudyStatusUIRefreshProbe() {
        let passed = MainActor.assumeIsolated {
            evaluateStudyStatusUIRefreshProbe()
        }
        if !passed {
            fputs("Study status UI refresh probe failed.\n", stderr)
            exit(2)
        }
    }

    static func runSourceEditResetProbe() {
        let passed = MainActor.assumeIsolated {
            evaluateSourceEditResetProbe()
        }
        if !passed {
            fputs("Source edit reset probe failed.\n", stderr)
            exit(2)
        }
    }

    private static func positionedFrame(size: CGSize, selection: CGRect, visibleFrame: CGRect, gap: CGFloat) -> CGRect {
        CGRect(
            origin: TutorWindowPositioning.origin(for: size, near: selection, in: visibleFrame, gap: gap),
            size: size
        )
    }

    private static func area(_ rect: CGRect) -> CGFloat {
        guard !rect.isNull, !rect.isEmpty else { return 0 }
        return rect.width * rect.height
    }

    @MainActor
    private static func evaluateAnswerUIRefreshProbe() -> Bool {
        let session = answerProbeSession()
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("tutorclip-answer-ui-probe-\(UUID().uuidString)", isDirectory: true)
        let historyStore = HistoryStore(baseDirectory: tempDirectory)
        let settingsStore = SettingsStore()
        let viewModel = TutorViewModel(
            session: session,
            isLoadingOCR: false,
            settingsStore: settingsStore,
            historyStore: historyStore,
            deepSeekClient: DeepSeekClient(configLoader: ConfigLoader(), settingsStore: settingsStore),
            promptBuilder: PromptBuilder(),
            onRecapture: {},
            onSettings: {},
            onClose: {}
        )
        var objectWillChangeCount = 0
        let cancellable = viewModel.objectWillChange.sink {
            objectWillChangeCount += 1
        }
        viewModel.selectAnswer("C")
        let answerApplied = session.selectedAnswer == "C"
        let studyStatusApplied = session.studyStatus == .mistake
        let resultVisible = viewModel.answerSelectionResult == .incorrect(selected: "C", correct: "B")
        let uiRefreshForwarded = objectWillChangeCount > 0
        print("answerApplied=\(answerApplied)")
        print("studyStatusApplied=\(studyStatusApplied)")
        print("answerResultVisible=\(resultVisible)")
        print("uiRefreshForwarded=\(uiRefreshForwarded)")
        cancellable.cancel()
        historyStore.close()
        try? FileManager.default.removeItem(at: tempDirectory)
        return answerApplied && studyStatusApplied && resultVisible && uiRefreshForwarded
    }

    @MainActor
    private static func evaluateStudyStatusUIRefreshProbe() -> Bool {
        let session = answerProbeSession()
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("tutorclip-study-status-ui-probe-\(UUID().uuidString)", isDirectory: true)
        let historyStore = HistoryStore(baseDirectory: tempDirectory)
        let settingsStore = SettingsStore()
        let viewModel = TutorViewModel(
            session: session,
            isLoadingOCR: false,
            settingsStore: settingsStore,
            historyStore: historyStore,
            deepSeekClient: DeepSeekClient(configLoader: ConfigLoader(), settingsStore: settingsStore),
            promptBuilder: PromptBuilder(),
            onRecapture: {},
            onSettings: {},
            onClose: {}
        )
        var objectWillChangeCount = 0
        let cancellable = viewModel.objectWillChange.sink {
            objectWillChangeCount += 1
        }
        viewModel.setStudyStatus(.known)
        let statusApplied = session.studyStatus == .known
        let uiRefreshForwarded = objectWillChangeCount > 0
        print("studyStatusApplied=\(statusApplied)")
        print("studyStatusUIRefreshForwarded=\(uiRefreshForwarded)")
        cancellable.cancel()
        historyStore.close()
        try? FileManager.default.removeItem(at: tempDirectory)
        return statusApplied && uiRefreshForwarded
    }

    @MainActor
    private static func evaluateSourceEditResetProbe() -> Bool {
        let session = answerProbeSession()
        session.messages = [
            ChatMessage(id: UUID(), sessionId: session.id, role: .user, content: "old", createdAt: Date(), actionType: .explainAll),
            ChatMessage(id: UUID(), sessionId: session.id, role: .assistant, content: "old answer", createdAt: Date(), actionType: .explainAll)
        ]
        session.selectedAnswer = "C"
        session.correctAnswer = "B"
        session.studyStatus = .mistake
        session.vocabularyCards = [
            VocabularyCard(id: UUID(), term: "old", meaning: "旧", note: "stale", example: "Old example.", source: "old")
        ]
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("tutorclip-source-edit-probe-\(UUID().uuidString)", isDirectory: true)
        let historyStore = HistoryStore(baseDirectory: tempDirectory)
        let settingsStore = SettingsStore()
        let viewModel = TutorViewModel(
            session: session,
            isLoadingOCR: false,
            settingsStore: settingsStore,
            historyStore: historyStore,
            deepSeekClient: DeepSeekClient(configLoader: ConfigLoader(), settingsStore: settingsStore),
            promptBuilder: PromptBuilder(),
            onRecapture: {},
            onSettings: {},
            onClose: {}
        )
        viewModel.selectedText = "old selection"
        viewModel.selectedTextRect = CGRect(x: 1, y: 2, width: 3, height: 4)
        viewModel.answerSummary = AnswerSummary(answer: "B", reason: "old reason", evidence: "old evidence")
        viewModel.updateOCRText("Which choice completes the text according to Standard English conventions?\n\nA) were\n\nB) was\n\nC) be\n\nD) being")

        let sourceUpdated = session.ocrDocument.editedText.contains("Standard English conventions")
        let staleChatCleared = session.messages.isEmpty
        let answerStateCleared = session.selectedAnswer == nil
            && session.correctAnswer == nil
            && viewModel.answerSummary == nil
        let learningStateCleared = session.studyStatus == .unreviewed
            && session.vocabularyCards.isEmpty
        let selectionCleared = viewModel.selectedText.isEmpty
            && viewModel.selectedTextRect == nil
        let categoryRefreshed = session.category == .grammar
        print("sourceUpdated=\(sourceUpdated)")
        print("staleChatCleared=\(staleChatCleared)")
        print("answerStateCleared=\(answerStateCleared)")
        print("learningStateCleared=\(learningStateCleared)")
        print("selectionCleared=\(selectionCleared)")
        print("categoryRefreshed=\(categoryRefreshed)")
        historyStore.close()
        try? FileManager.default.removeItem(at: tempDirectory)
        return sourceUpdated
            && staleChatCleared
            && answerStateCleared
            && learningStateCleared
            && selectionCleared
            && categoryRefreshed
    }

    @MainActor
    private static func answerProbeSession() -> TutorSession {
        let session = TutorSession(
            id: UUID(),
            title: "Answer Probe",
            createdAt: Date(),
            updatedAt: Date(),
            ocrDocument: OCRDocument(
                id: UUID(),
                fullText: "Passage\n\nWhich choice?\n\nA) One\n\nB) Two\n\nC) Three\n\nD) Four",
                editedText: "Passage\n\nWhich choice?\n\nA) One\n\nB) Two\n\nC) Three\n\nD) Four",
                detectedLanguage: "en-US",
                createdAt: Date(),
                blocks: [],
                lines: [],
                tokens: []
            ),
            messages: [],
            screenshotInMemory: nil,
            category: .reading,
            correctAnswer: "B"
        )
        session.learningMetadata.correctAnswerUserConfirmed = true
        return session
    }
}
