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
    private var lastRequest: TutorRequest?
    private var categorySourceAI = false

    private let settingsStore: SettingsStore
    private let historyStore: HistoryStore
    private let deepSeekClient: any DeepSeekStreaming
    private let promptBuilder: PromptBuilder
    private let onRecapture: () -> Void
    private let onSettings: () -> Void
    private let onClose: () -> Void
    private var settingsCancellable: AnyCancellable?
    private var sessionCancellable: AnyCancellable?
    var inFlightTask: Task<Void, Never>?
    var activeRequestID: UUID?

    init(session: TutorSession, isLoadingOCR: Bool, settingsStore: SettingsStore, historyStore: HistoryStore, deepSeekClient: any DeepSeekStreaming, promptBuilder: PromptBuilder, onRecapture: @escaping () -> Void, onSettings: @escaping () -> Void, onClose: @escaping () -> Void) {
        self.session = session
        self.isLoadingOCR = isLoadingOCR
        self.settingsStore = settingsStore
        self.historyStore = historyStore
        self.deepSeekClient = deepSeekClient
        self.promptBuilder = promptBuilder
        self.onRecapture = onRecapture
        self.onSettings = onSettings
        self.onClose = onClose
        settingsCancellable = settingsStore.$settings.sink { [weak self] _ in
            self?.objectWillChange.send()
        }
        bindSessionChanges()
    }

    var language: AppLanguage {
        settingsStore.settings.appLanguage
    }

    var answerEvidence: String {
        answerSummary?.evidence ?? ""
    }

    var answerChoices: [String] {
        TutorQuestionParsing.answerChoices(from: session.ocrDocument.editedText)
    }

    var answerSelectionResult: TutorSessionMutation.AnswerSelectionResult? {
        TutorSessionMutation.answerSelectionResult(
            selected: session.selectedAnswer,
            correct: session.correctAnswer ?? answerSummary?.choiceLetter
        )
    }

    var ocrQualityWarning: String? {
        let lines = session.ocrDocument.lines
        guard !isLoadingOCR, !lines.isEmpty else { return nil }
        let average = lines.map { Double($0.confidence) }.reduce(0, +) / Double(lines.count)
        let lowCount = lines.filter { $0.confidence < 0.45 }.count
        guard average < 0.66 || lowCount >= max(2, lines.count / 5) else { return nil }
        return text(
            "OCR 置信度偏低，已保留原文；可直接编辑题目后再讲解。",
            "OCR confidence is low. The original text was kept; edit the question before explaining if needed."
        )
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
        resetTransientState()
        ocrFormatState = .idle
        bindSessionChanges()
        objectWillChange.send()
    }

    func showSettings() {
        onSettings()
    }

    func closeWindow() {
        onClose()
    }

    func setStudyStatus(_ status: StudyStatus) {
        session.studyStatus = status
        session.updatedAt = Date()
        objectWillChange.send()
        historyStore.save(session: session, enabled: settingsStore.settings.historyEnabled) { [weak self] success in
            guard let self, !success else { return }
            self.errorMessage = self.text("学习状态保存失败。", "Failed to save study status.")
        }
    }

    func selectAnswer(_ answer: String) {
        _ = TutorSessionMutation.selectAnswer(answer, in: session)
        objectWillChange.send()
        historyStore.save(session: session, enabled: settingsStore.settings.historyEnabled) { [weak self] success in
            guard let self, !success else { return }
            self.errorMessage = self.text("答案状态保存失败。", "Failed to save answer state.")
        }
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

    func formatOCR() {
        guard !isStreaming else {
            RuntimeLog.write("format-ocr-skipped streaming=true")
            return
        }
        let original = session.ocrDocument.editedText
        guard !original.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            RuntimeLog.write("format-ocr-skipped empty=true")
            return
        }
        RuntimeLog.write("format-ocr-start chars=\(original.count)")
        RuntimeLog.writeTextBlock("format-ocr-original", original)
        errorMessage = nil
        ocrFormatState = .formatting
        let requestID = beginRequest()

        var formatted = ""
        let messages = promptBuilder.formatOCRPrompt(document: session.ocrDocument)
        inFlightTask = Task { [weak self] in
            guard let self else { return }
            defer { self.finishRequest(requestID) }
            do {
                try await deepSeekClient.stream(messages: messages) { token in
                    guard self.isCurrentRequest(requestID) else { return }
                    formatted += token
                }
                try Task.checkCancellation()
                guard isCurrentRequest(requestID) else { return }
                let parsed = GeneratedQuestion.parse(formatted, requireQuestionBlock: true)
                let cleaned = parsed.question
                RuntimeLog.write("format-ocr-finished chars=\(cleaned.count)")
                RuntimeLog.writeTextBlock("format-ocr-deepseek-raw", formatted)
                RuntimeLog.writeTextBlock("format-ocr-cleaned", cleaned)
                guard !cleaned.isEmpty else {
                    let message = text("OCR 整理结果为空，已保留原文。", "OCR formatting returned empty output. Original text was kept.")
                    errorMessage = message
                    ocrFormatState = .failed(message)
                    RuntimeLog.write("format-ocr-rejected empty-result")
                    return
                }
                updateOCRText(cleaned)
                session.correctAnswer = parsed.answer
                applyMetadataCategory(parsed.category)
                session.selectedAnswer = nil
                TutorSessionMutation.updateFullText(cleaned, in: session)
                RuntimeLog.writeTextMetrics("format-ocr-document-after-fulltext", session.ocrDocument.editedText)
                if parsed.category == nil {
                    await classifyQuestionCategoryWithAI(cleaned)
                    try Task.checkCancellation()
                }
                ocrFormatState = .applied
                RuntimeLog.write("format-ocr-applied")
            } catch is CancellationError {
                RuntimeLog.write("format-ocr-cancelled")
            } catch {
                guard isCurrentRequest(requestID) else { return }
                errorMessage = error.localizedDescription
                ocrFormatState = .failed(error.localizedDescription)
                RuntimeLog.write("format-ocr-error \(error.localizedDescription)")
            }
        }
    }

    func generatePracticeQuestion() {
        guard !isStreaming else { return }
        errorMessage = nil
        lastRequest = TutorRequest(action: .practiceSimilar, question: nil)
        refreshQuestionCategory()
        let requestID = beginRequest()
        let userContent = promptBuilder.userPrompt(
            action: .practiceSimilar,
            document: session.ocrDocument,
            selectedText: nil,
            customQuestion: nil,
            category: session.category,
            language: language
        )
        let messages = [
            DeepSeekMessage(role: "system", content: promptBuilder.practiceGenerationSystemPrompt(language: language)),
            DeepSeekMessage(role: "user", content: userContent)
        ]
        var raw = ""
        inFlightTask = Task { [weak self] in
            guard let self else { return }
            defer { self.finishRequest(requestID) }
            do {
                try await deepSeekClient.stream(messages: messages) { token in
                    guard self.isCurrentRequest(requestID) else { return }
                    raw += token
                }
                try Task.checkCancellation()
                guard isCurrentRequest(requestID) else { return }
                RuntimeLog.writeTextBlock("practice-similar-raw", raw)
                let parsed = GeneratedQuestion.parse(raw, requireQuestionBlock: true)
                guard !parsed.question.isEmpty else {
                    errorMessage = text("再练一题没有返回有效题目，已保留当前题目。", "Practice generation did not return a valid question. The current question was kept.")
                    RuntimeLog.write("practice-similar-rejected missing-question-block")
                    return
                }
                applyGeneratedQuestion(parsed.question, correctAnswer: parsed.answer, category: parsed.category)
                RuntimeLog.write("practice-similar-applied chars=\(parsed.question.count) answer=\(parsed.answer ?? "")")
            } catch is CancellationError {
                RuntimeLog.write("practice-similar-cancelled")
            } catch {
                guard isCurrentRequest(requestID) else { return }
                errorMessage = error.localizedDescription
                RuntimeLog.write("practice-similar-error \(error.localizedDescription)")
            }
        }
    }

    private func send(action: TutorAction, question: String?) {
        guard !isStreaming else { return }
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

        inFlightTask = Task { [weak self] in
            guard let self else { return }
            defer { self.finishRequest(requestID) }
            do {
                try await deepSeekClient.stream(messages: request.deepSeekMessages) { [weak self] token in
                    guard let self,
                          self.isCurrentRequest(requestID),
                          self.session.id == sessionID else { return }
                    if let index = self.session.messages.firstIndex(where: { $0.id == assistantID }) {
                        self.session.messages[index].content += token
                    }
                }
                try Task.checkCancellation()
                guard isCurrentRequest(requestID), session.id == sessionID else { return }
                if let index = session.messages.firstIndex(where: { $0.id == assistantID }) {
                    let rawContent = session.messages[index].content
                    RuntimeLog.writeTextBlock("chat-deepseek-raw action=\(action.rawValue) message=\(assistantID.uuidString)", rawContent)
                    applyProcessedResponse(TutorResponseProcessor.process(rawContent: rawContent, action: action), toMessageAt: index)
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
            answerSummary = summary
            session.correctAnswer = summary.choiceLetter ?? session.correctAnswer
            RuntimeLog.write("answer-summary answer=\(summary.answer) reasonChars=\(summary.reason.count) evidenceChars=\(summary.evidence.count)")
        }
        if !response.vocabularyCards.isEmpty {
            session.vocabularyCards = response.vocabularyCards
            RuntimeLog.write("vocabulary-cards count=\(response.vocabularyCards.count)")
        }
    }

    private func refreshQuestionCategory() {
        guard !categorySourceAI else {
            RuntimeLog.write("question-category-ai-preserved \(session.category.rawValue)")
            return
        }
        session.category = SessionCategory.infer(from: session.ocrDocument.editedText)
        RuntimeLog.write("question-category \(session.category.rawValue)")
    }

    private func applyGeneratedQuestion(_ question: String, correctAnswer: String?, category: SessionCategory?) {
        TutorSessionMutation.applyFormattedQuestion(question, answer: correctAnswer, category: category, to: session)
        resetTransientState()
        viewMode = .text
        categorySourceAI = false
        applyMetadataCategory(category)
        if category == nil {
            refreshQuestionCategory()
        }
    }

    private func applyMetadataCategory(_ category: SessionCategory?) {
        guard let category, category != .unknown else { return }
        session.category = category
        categorySourceAI = true
        RuntimeLog.write("question-category-metadata \(category.rawValue)")
    }

    private func bindSessionChanges() {
        sessionCancellable = session.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }
    }

    private func resetTransientState() {
        inputText = ""
        selectedText = ""
        selectedTextRect = nil
        answerSummary = nil
        errorMessage = nil
        lastRequest = nil
        categorySourceAI = false
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
    }

    private func classifyQuestionCategoryWithAI(_ text: String) async {
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
