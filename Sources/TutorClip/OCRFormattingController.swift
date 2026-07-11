import Foundation

@MainActor
extension TutorViewModel {
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
                var parsed = GeneratedQuestion.parse(formatted, requireQuestionBlock: true)
                parsed.question = try await TableFormattingAuditor(client: deepSeekClient, promptBuilder: promptBuilder)
                    .audit(document: session.ocrDocument, candidate: parsed.question)
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
                let verification = try await AnswerVerificationService(client: deepSeekClient, promptBuilder: promptBuilder)
                    .verify(question: cleaned)
                updateOCRText(cleaned)
                session.correctAnswer = verification?.answer
                session.learningMetadata = parsed.learningMetadata
                session.learningMetadata.isAIVerified = verification != nil
                session.learningMetadata.answerConfidence = verification?.confidence
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
}
