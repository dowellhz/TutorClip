import Foundation

enum TutorSessionMutation {
    enum AnswerSelectionResult: Equatable {
        case correct(String)
        case incorrect(selected: String, correct: String)
        case selected(String)
    }

    static func updateOCRText(_ text: String, in session: TutorSession) {
        var document = session.ocrDocument
        document.editedText = text
        session.ocrDocument = document
    }

    @discardableResult
    static func selectAnswer(_ answer: String, in session: TutorSession) -> AnswerSelectionResult {
        let selected = choiceLetter(answer) ?? answer.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        session.selectedAnswer = selected
        session.updatedAt = Date()

        guard let correct = choiceLetter(session.correctAnswer) else {
            return .selected(selected)
        }
        if selected == correct {
            session.studyStatus = .known
            return .correct(correct)
        }
        session.studyStatus = .mistake
        return .incorrect(selected: selected, correct: correct)
    }

    static func answerSelectionResult(selected: String?, correct: String?) -> AnswerSelectionResult? {
        guard let selected = choiceLetter(selected) else { return nil }
        guard let correct = choiceLetter(correct) else {
            return .selected(selected)
        }
        return selected == correct ? .correct(correct) : .incorrect(selected: selected, correct: correct)
    }

    static func applyFormattedQuestion(_ question: String, answer: String?, category: SessionCategory?, to session: TutorSession) {
        session.ocrDocument = OCRDocument(
            id: UUID(),
            fullText: question,
            editedText: question,
            detectedLanguage: session.ocrDocument.detectedLanguage,
            createdAt: Date(),
            blocks: [],
            lines: [],
            tokens: []
        )
        session.messages = []
        session.screenshotInMemory = nil
        session.selectedAnswer = nil
        session.correctAnswer = answer
        session.vocabularyCards = []
        session.studyStatus = .unreviewed
        session.category = category ?? SessionCategory.infer(from: question)
        session.title = SessionTitle.make(from: question)
        session.updatedAt = Date()
    }

    static func updateFullText(_ text: String, in session: TutorSession) {
        var document = session.ocrDocument
        document.fullText = text
        session.ocrDocument = document
        session.title = SessionTitle.make(from: text)
        session.updatedAt = Date()
    }

    private static func choiceLetter(_ value: String?) -> String? {
        guard let first = value?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .first?
            .uppercased(),
            ["A", "B", "C", "D"].contains(first) else {
            return nil
        }
        return first
    }
}
