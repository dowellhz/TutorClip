import AppKit
import Combine
import Foundation

@MainActor
final class TutorViewModel: ObservableObject {
    @Published var session: TutorSession
    @Published var isLoadingOCR: Bool
    @Published var inputText: String = ""
    @Published var selectedText: String = ""
    @Published var selectedTextRect: CGRect?
    @Published var answerSummary: AnswerSummary?
    @Published var isStreaming: Bool = false
    @Published var errorMessage: String?
    @Published var viewMode: SourceViewMode = .text
    @Published var ocrFormatState: OCRFormatState = .idle
    @Published var learningFeedback: String?
    @Published var learningLoadingAction: LearningLoadingAction?
    @Published var viewedQuestionSnapshot: SATQuestionSnapshot?
    private var lastRequest: TutorRequest?
    var categorySourceAI = false
    private let practiceVariationPlanner = PracticeVariationPlanner()

    let settingsStore: SettingsStore
    let historyStore: HistoryStore
    let deepSeekClient: any DeepSeekStreaming
    let promptBuilder: PromptBuilder
    private let onRecapture: () -> Void
    private let onSettings: () -> Void
    private let onKnowledgeMap: () -> Void
    private let onClose: () -> Void
    private var settingsCancellable: AnyCancellable?
    private var sessionCancellable: AnyCancellable?
    var inFlightTask: Task<Void, Never>?
    var activeRequestID: UUID?

    init(session: TutorSession, isLoadingOCR: Bool, settingsStore: SettingsStore, historyStore: HistoryStore, deepSeekClient: any DeepSeekStreaming, promptBuilder: PromptBuilder, onRecapture: @escaping () -> Void, onSettings: @escaping () -> Void, onKnowledgeMap: @escaping () -> Void = {}, onClose: @escaping () -> Void) {
        self.session = session
        self.isLoadingOCR = isLoadingOCR
        self.settingsStore = settingsStore
        self.historyStore = historyStore
        self.deepSeekClient = deepSeekClient
        self.promptBuilder = promptBuilder
        self.onRecapture = onRecapture
        self.onSettings = onSettings
        self.onKnowledgeMap = onKnowledgeMap
        self.onClose = onClose
        settingsCancellable = settingsStore.$settings.sink { [weak self] _ in
            self?.objectWillChange.send()
        }
        bindSessionChanges()
    }

    var language: AppLanguage {
        settingsStore.settings.appLanguage
    }

    func text(_ chinese: String, _ english: String) -> String {
        language.text(chinese, english)
    }

    func recapture() {
        closeAndPersistIfNeeded()
        onRecapture()
    }

    func copyOCR() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(session.ocrDocument.editedText, forType: .string)
    }

    func updateOCRText(_ text: String) {
        guard text != session.ocrDocument.editedText else { return }
        RuntimeLog.writeTextMetrics("viewmodel-update-ocr-input", text)
        TutorSessionMutation.updateOCRText(text, in: session)
        resetSourceDerivedState()
        ocrFormatState = .idle
        RuntimeLog.writeTextMetrics("viewmodel-update-ocr-applied", session.ocrDocument.editedText)
        categorySourceAI = false
        refreshQuestionCategory()
    }

    func replaceSession(_ session: TutorSession, isLoadingOCR: Bool) {
        cancelInFlightRequest(reason: "session-replaced")
        self.session = session
        self.isLoadingOCR = isLoadingOCR
        practiceVariationPlanner.reset()
        resetTransientState()
        ocrFormatState = .idle
        bindSessionChanges()
        objectWillChange.send()
    }

    func showSettings() {
        onSettings()
    }

    func showKnowledgeMap() { onKnowledgeMap() }

    func closeWindow() {
        onClose()
    }

    func run(action: TutorAction) {
        if action == .formatOCR {
            formatOCR()
            return
        }
        if action == .practiceSimilar {
            generatePracticeQuestion()
            return
        }
        send(action: action, question: nil)
    }

    func retryLastRequest() {
        guard let lastRequest else { return }
        send(action: lastRequest.action, question: lastRequest.question)
    }

    func sendCustomQuestion() {
        let question = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty else { return }
        inputText = ""
        send(action: .customQuestion, question: question)
    }

    func closeAndPersistIfNeeded() {
        cancelInFlightRequest(reason: "window-closed")
        session.discardScreenshot()
        refreshQuestionCategory()
        historyStore.save(session: session, enabled: settingsStore.settings.historyEnabled) { [weak self] success in
            guard let self, !success else { return }
            self.errorMessage = self.text("历史数据库写入失败。", "History database write failed.")
        }
    }

    func generatePracticeQuestion() {
        guard !isStreaming else { return }
        errorMessage = nil
        lastRequest = TutorRequest(action: .practiceSimilar, question: nil)
        refreshQuestionCategory()
        let requestID = beginRequest()
        let targetQuestionTypeID = session.learningMetadata.questionTypeID
        let targetKnowledgePointIDs = session.learningMetadata.knowledgePointIDs
        let targetKnowledgePoints = targetKnowledgePointIDs.compactMap(SATKnowledgeCatalog.knowledgePoint)
        let knowledgeTarget = targetKnowledgePoints.map { "\($0.titleEN) [\($0.id)]" }.joined(separator: ", ")
        let baseUserContent = promptBuilder.userPrompt(
            action: .practiceSimilar,
            document: session.ocrDocument,
            selectedText: nil,
            customQuestion: nil,
            category: session.category,
            language: language
        ) + "\n\nTarget SAT Skill: \(session.learningMetadata.skill.isEmpty ? "infer from question" : session.learningMetadata.skill)\nTarget question type ID: \(targetQuestionTypeID.isEmpty ? "infer from question" : targetQuestionTypeID)\nTarget knowledge point (test this point only): \(knowledgeTarget.isEmpty ? "infer from question" : knowledgeTarget)\nTarget difficulty: \(session.learningMetadata.difficulty.rawValue)"
        let variation = practiceVariationPlanner.nextVariation()
        let sourceLearningFlow = session.learningMetadata.needsReviewFlow
        inFlightTask = Task { [weak self] in
            guard let self else { return }
            defer { self.finishRequest(requestID) }
            do {
                for attempt in 0..<2 {
                    var raw = ""
                    let diversity = practiceVariationPlanner.diversityInstruction(for: variation, retrying: attempt > 0)
                    let messages = [
                        DeepSeekMessage(role: "system", content: promptBuilder.practiceGenerationSystemPrompt(language: language)),
                        DeepSeekMessage(role: "user", content: baseUserContent + "\n\n" + diversity)
                    ]
                    try await deepSeekClient.stream(messages: messages, temperatureOverride: PracticeVariationPlanner.practiceTemperature) { token in
                        guard self.isCurrentRequest(requestID) else { return }
                        raw += token
                    }
                    try Task.checkCancellation()
                    guard isCurrentRequest(requestID) else { return }
                    RuntimeLog.writeTextBlock("practice-similar-raw attempt=\(attempt + 1)", raw)
                    var parsed = GeneratedQuestion.parse(raw, requireQuestionBlock: true)
                    guard !parsed.question.isEmpty else { continue }
                    let validation = try await PracticeQuestionValidator(client: deepSeekClient).validate(parsed)
                    guard validation.isValid else {
                        RuntimeLog.write("practice-similar-retrying validation=failed reason=\(validation.reason)")
                        continue
                    }
                    parsed.learningMetadata.isAIVerified = true
                    parsed.learningMetadata.answerConfidence = 1
                    if !targetQuestionTypeID.isEmpty, !targetKnowledgePointIDs.isEmpty {
                        parsed.learningMetadata.questionTypeID = targetQuestionTypeID
                        parsed.learningMetadata.knowledgePointIDs = targetKnowledgePointIDs
                    }
                    if sourceLearningFlow.stage == .easyPractice || sourceLearningFlow.stage == .pendingVerification {
                        var continuedFlow = sourceLearningFlow
                        let role: SATQuestionChainRole = sourceLearningFlow.stage == .easyPractice ? .easyPractice : .verification
                        continuedFlow.stage = .pendingVerification
                        continuedFlow.microCheck = nil
                        continuedFlow.questionChain.append(SATQuestionSnapshot(
                            role: role,
                            text: parsed.question,
                            correctAnswer: parsed.answer,
                            category: parsed.category ?? session.category,
                            difficulty: parsed.learningMetadata.difficulty
                        ))
                        parsed.learningMetadata.needsReviewFlow = continuedFlow
                        parsed.learningMetadata.pendingHintUsed = role == .easyPractice
                    }
                    guard practiceVariationPlanner.isExactDuplicate(parsed.question) else {
                        practiceVariationPlanner.record(parsed.question)
                        applyGeneratedQuestion(parsed.question, correctAnswer: parsed.answer, category: parsed.category, learningMetadata: parsed.learningMetadata)
                        RuntimeLog.write("practice-similar-applied chars=\(parsed.question.count) answer=\(parsed.answer ?? "")")
                        return
                    }
                    RuntimeLog.write("practice-similar-retrying exact-duplicate=true")
                }
                errorMessage = text("新练习题与最近题目重复，请再试一次。", "The new practice question repeated a recent question. Try again.")
                restoreDifficultyAfterFailedPractice(sourceLearningFlow)
                RuntimeLog.write("practice-similar-rejected attempts=2")
            } catch is CancellationError {
                RuntimeLog.write("practice-similar-cancelled")
            } catch {
                guard isCurrentRequest(requestID) else { return }
                errorMessage = error.localizedDescription
                restoreDifficultyAfterFailedPractice(sourceLearningFlow)
                RuntimeLog.write("practice-similar-error \(error.localizedDescription)")
            }
        }
    }

    func send(action: TutorAction, question: String?) {
        guard !isStreaming else { return }
        if action == .explainAll || action == .customQuestion || action == .guidedLearning {
            session.learningMetadata.pendingHintUsed = true
        }
        errorMessage = nil
        lastRequest = TutorRequest(action: action, question: question)
        refreshQuestionCategory()
        if action == .explainAll {
            answerSummary = nil
        }
        if action == .vocabulary {
            session.vocabularyCards = []
        }

        let request = TutorChatRequestBuilder(promptBuilder: promptBuilder).makeRequest(
            action: action,
            question: question,
            session: session,
            language: language,
            selectedText: selectedText
        )
        session.messages.append(request.userMessage)
        session.messages.append(request.assistantMessage)
        let assistantID = request.assistantMessage.id
        let sessionID = session.id
        let requestID = beginRequest()
        let hidesStreamingContent = session.learningMetadata.needsReviewFlow.stage == .microCheck

        inFlightTask = Task { [weak self] in
            guard let self else { return }
            defer { self.finishRequest(requestID) }
            var pendingTokens = ""
            var lastRenderAt = Date()
            do {
                try await deepSeekClient.stream(messages: request.deepSeekMessages) { [weak self] token in
                    guard let self,
                          self.isCurrentRequest(requestID),
                          self.session.id == sessionID else { return }
                    pendingTokens += token
                    let shouldRender = !hidesStreamingContent && (pendingTokens.count >= 96 || Date().timeIntervalSince(lastRenderAt) >= 0.06)
                    if shouldRender, let index = self.session.messages.firstIndex(where: { $0.id == assistantID }) {
                        self.session.messages[index].content += pendingTokens
                        pendingTokens = ""
                        lastRenderAt = Date()
                    }
                }
                try Task.checkCancellation()
                guard isCurrentRequest(requestID), session.id == sessionID else { return }
                if let index = session.messages.firstIndex(where: { $0.id == assistantID }) {
                    let rawContent = session.messages[index].content + pendingTokens
                    if !hidesStreamingContent {
                        session.messages[index].content = rawContent
                    }
                    pendingTokens = ""
                    RuntimeLog.writeTextBlock("chat-deepseek-raw action=\(action.rawValue) message=\(assistantID.uuidString)", rawContent)
                    var validatedContent = rawContent
                    if hidesStreamingContent,
                       let check = SATMicroCheck.extract(from: rawContent).check,
                       let focus = session.learningMetadata.needsReviewFlow.learningFocus {
                        let validation = try await MicroCheckValidator(client: deepSeekClient).validate(check, focus: focus)
                        if !validation.isValid {
                            validatedContent = SATMicroCheck.extract(from: rawContent).body
                            RuntimeLog.write("micro-check-validation-failed reason=\(validation.reason)")
                        }
                    }
                    let learningContent = applyNeedsReviewResponse(validatedContent, action: action)
                    applyProcessedResponse(TutorResponseProcessor.process(rawContent: learningContent, action: action), toMessageAt: index)
                }
            } catch is CancellationError {
                RuntimeLog.write("chat-request-cancelled action=\(action.rawValue)")
            } catch {
                guard isCurrentRequest(requestID), session.id == sessionID else { return }
                if let index = session.messages.firstIndex(where: { $0.id == assistantID }) {
                    session.messages[index].content = "请求失败：\(error.localizedDescription)"
                }
                errorMessage = error.localizedDescription
            }
            guard isCurrentRequest(requestID), session.id == sessionID else { return }
            session.updatedAt = Date()
            session.title = SessionTitle.make(from: session.ocrDocument.editedText)
            refreshQuestionCategory()
        }
    }

    private func applyProcessedResponse(_ response: ProcessedTutorResponse, toMessageAt index: Int) {
        session.messages[index].content = response.content
        if let summary = response.answerSummary {
            if let verified = session.correctAnswer,
               session.learningMetadata.isAIVerified,
               summary.choiceLetter != verified {
                answerSummary = nil
                RuntimeLog.write("answer-summary-rejected summary=\(summary.choiceLetter ?? "nil") verified=\(verified)")
            } else {
                answerSummary = summary
                RuntimeLog.write("answer-summary answer=\(summary.answer) reasonChars=\(summary.reason.count) evidenceChars=\(summary.evidence.count)")
            }
        }
        if !response.vocabularyCards.isEmpty {
            session.vocabularyCards = response.vocabularyCards
            RuntimeLog.write("vocabulary-cards count=\(response.vocabularyCards.count)")
        }
    }

    private func bindSessionChanges() {
        sessionCancellable = session.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }
    }

    func resetTransientState() {
        inputText = ""
        selectedText = ""
        selectedTextRect = nil
        answerSummary = nil
        errorMessage = nil
        lastRequest = nil
        categorySourceAI = false
        learningFeedback = nil
        viewedQuestionSnapshot = nil
    }

    private func resetSourceDerivedState() {
        selectedText = ""
        selectedTextRect = nil
        answerSummary = nil
        lastRequest = nil
        session.messages = []
        session.selectedAnswer = nil
        session.correctAnswer = nil
        session.vocabularyCards = []
        session.studyStatus = .unreviewed
        let wasGenerated = session.learningMetadata.isAIGenerated
        session.learningMetadata = SATLearningMetadata(isAIGenerated: wasGenerated)
        learningFeedback = nil
        viewedQuestionSnapshot = nil
    }

    func classifyQuestionCategoryWithAI(_ text: String) async {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        var raw = ""
        do {
            try await deepSeekClient.stream(messages: promptBuilder.classifyQuestionPrompt(text: text)) { token in
                raw += token
            }
            let category = TutorQuestionParsing.category(fromAI: raw)
            if category != .unknown {
                session.category = category
                categorySourceAI = true
                RuntimeLog.write("question-category-ai \(category.rawValue)")
            } else {
                RuntimeLog.writeTextBlock("question-category-ai-unknown", raw)
            }
        } catch is CancellationError {
            RuntimeLog.write("question-category-ai-cancelled")
        } catch {
            RuntimeLog.write("question-category-ai-error \(error.localizedDescription)")
        }
    }
}
