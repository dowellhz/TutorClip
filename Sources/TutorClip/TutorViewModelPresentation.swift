import Foundation

@MainActor
extension TutorViewModel {
    var visibleQuestionText: String {
        viewedQuestionSnapshot?.text ?? session.ocrDocument.editedText
    }

    var underlinedOCRTexts: [String] {
        session.ocrDocument.tokens.filter { $0.isLikelyUnderlined == true }.map(\.text)
    }

    func viewQuestionSnapshot(_ snapshot: SATQuestionSnapshot?) {
        viewedQuestionSnapshot = snapshot
    }
    var answerEvidence: String { answerSummary?.evidence ?? "" }

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
        if !underlinedOCRTexts.isEmpty {
            return text(
                "检测到可能的下划线文本，已在题目视图还原；请对照截图确认。",
                "Possible underlined text was detected and restored; confirm it against the screenshot."
            )
        }
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
}
