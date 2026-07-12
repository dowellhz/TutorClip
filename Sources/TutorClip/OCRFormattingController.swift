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
        let sessionID = session.id
        let preflightVerification = beginAnswerVerification(for: original)
        errorMessage = nil
        ocrFormatState = .formatting
        let requestID = beginRequest()

        var formatted = ""
        let messages = promptBuilder.formatOCRPrompt(document: session.ocrDocument)
        inFlightTask = Task { [weak self] in
            guard let self else { return }
            defer { self.finishRequest(requestID) }
            do {
                try await deepSeekClient.stream(
                    messages: messages,
                    temperatureOverride: nil,
                    modelOverride: DeepSeekModel.flash.rawValue
                ) { token in
                    guard self.isCurrentRequest(requestID) else { return }
                    formatted += token
                }
                try Task.checkCancellation()
                guard isCurrentRequest(requestID) else { return }
                var parsed = GeneratedQuestion.parse(formatted, requireQuestionBlock: true)
                if parsed.category == .math {
                    applyMetadataCategory(.math)
                    let message = text(
                        "TutorClip 暂不支持数学题。请切换到截图查看原题；OCR 文字不会作为可靠公式使用。",
                        "TutorClip does not currently support math questions. View the original screenshot; OCR text will not be treated as a reliable formula."
                    )
                    errorMessage = message
                    ocrFormatState = .failed(message)
                    RuntimeLog.write("format-ocr-rejected unsupported-category=math")
                    return
                }
                parsed.question = try await TableFormattingAuditor(client: deepSeekClient, promptBuilder: promptBuilder)
                    .audit(document: session.ocrDocument, candidate: parsed.question)
                parsed.question = try await GrammarBlankAuditor(client: deepSeekClient)
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
                updateOCRText(cleaned)
                session.learningMetadata = parsed.learningMetadata
                session.learningMetadata.isAIGenerated = false
                applyMetadataCategory(parsed.category)
                session.selectedAnswer = nil
                TutorSessionMutation.updateFullText(cleaned, in: session)
                RuntimeLog.writeTextMetrics("format-ocr-document-after-fulltext", session.ocrDocument.editedText)
                if parsed.category == nil {
                    await classifyQuestionCategoryWithAI(cleaned)
                    try Task.checkCancellation()
                }
                ocrFormatState = .applied
                applyPreflightVerification(
                    preflightVerification,
                    originalQuestion: original,
                    formattedQuestion: cleaned,
                    sessionID: sessionID
                )
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

@MainActor
private struct GrammarBlankAuditor {
    let client: any DeepSeekStreaming

    func audit(document: OCRDocument, candidate: String) async throws -> String {
        let normalized = candidate.lowercased()
        let isSATBlankQuestion = normalized.contains("conventions of standard english")
            || normalized.contains("complete the text so that it conforms")
            || normalized.contains("completes the text")
            || normalized.contains("complete the text?")
        let addedEmDash = candidate.filter({ $0 == "—" }).count > document.editedText.filter({ $0 == "—" }).count
        guard isSATBlankQuestion || (candidate.contains("—") && addedEmDash) else {
            return candidate
        }
        var response = ""
        let messages = [
            DeepSeekMessage(role: "system", content: """
            你是 SAT 语法题作答空格审校器。对照原始 OCR 和候选文本，只修复候选新增的破折号。
            Vision 可能已把作答横线识别成破折号、句号或直接漏掉。结合题干和 A/B/C/D 找出选项应插入的位置：该位置必须输出五个下划线：_____。原文真正作为句子标点的破折号或句号必须保留。
            不得改写、增删或重排其他文字。只输出 FORMATTED_QUESTION 与 END_FORMATTED_QUESTION 包裹的完整题目。
            """),
            DeepSeekMessage(role: "user", content: "原始 OCR：\n\(document.editedText)\n\n待审校候选：\n\(candidate)")
        ]
        try await client.stream(
            messages: messages,
            temperatureOverride: 0,
            modelOverride: DeepSeekModel.flash.rawValue
        ) { response += $0 }
        try Task.checkCancellation()
        let repaired = GeneratedQuestion.parse(response, requireQuestionBlock: true).question
        let sourceChoices = Set(TutorQuestionParsing.answerChoices(from: candidate))
        let repairedChoices = Set(TutorQuestionParsing.answerChoices(from: repaired))
        guard repaired.count >= Int(Double(candidate.count) * 0.9),
              sourceChoices.isSubset(of: repairedChoices),
              repaired.contains("_____") else {
            RuntimeLog.write("grammar-blank-audit-rejected")
            return candidate
        }
        RuntimeLog.write("grammar-blank-audit-applied")
        return repaired
    }
}
