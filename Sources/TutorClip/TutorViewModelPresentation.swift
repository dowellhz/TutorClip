import Foundation

@MainActor
extension TutorViewModel {
    var visibleQuestionText: String {
        viewedQuestionSnapshot?.text ?? session.ocrDocument.editedText
    }

    var isViewingQuestionSnapshot: Bool { viewedQuestionSnapshot != nil }

    var underlinedOCRTexts: [String] {
        OCRVisualCuePolicy.underlinedTextSpans(in: session.ocrDocument)
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    func viewQuestionSnapshot(_ snapshot: SATQuestionSnapshot?) {
        viewedQuestionSnapshot = snapshot
        selectedText = ""
        selectedTextRect = nil
    }
    var answerEvidence: String { answerSummary?.evidence ?? "" }

    var answerChoices: [String] {
        TutorQuestionParsing.answerChoices(from: session.ocrDocument.editedText)
    }

    var answerSelectionResult: TutorSessionMutation.AnswerSelectionResult? {
        TutorSessionMutation.answerSelectionResult(
            selected: session.selectedAnswer,
            correct: session.learningMetadata.canAutoGradeAnswer
                ? (session.correctAnswer ?? answerSummary?.choiceLetter)
                : nil
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
        guard OCRConfidenceAssessment.shouldWarn(confidences: lines.map(\.confidence)) else { return nil }
        return text(
            "多处文字识别不确定，已保留原文；请对照截图检查后再讲解。",
            "Several OCR lines are uncertain. The original text was kept; check it against the screenshot before explaining."
        )
    }
}

enum OCRConfidenceAssessment {
    static func shouldWarn(confidences: [Float]) -> Bool {
        guard !confidences.isEmpty else { return false }
        let sorted = confidences.sorted()
        let median: Float
        if sorted.count.isMultiple(of: 2) {
            let upper = sorted.count / 2
            median = (sorted[upper - 1] + sorted[upper]) / 2
        } else {
            median = sorted[sorted.count / 2]
        }
        let lowCount = sorted.filter { $0 < 0.45 }.count
        let lowCountLimit = max(2, Int(ceil(Double(sorted.count) * 0.25)))
        return median < 0.50 || lowCount >= lowCountLimit
    }
}
