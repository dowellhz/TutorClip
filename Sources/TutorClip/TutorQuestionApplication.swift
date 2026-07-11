import Foundation

@MainActor
extension TutorViewModel {
    func restoreDifficultyAfterFailedPractice(_ flow: SATNeedsReviewFlow) {
        guard flow.stage == .easyPractice, flow.originalDifficulty != .unknown else { return }
        session.learningMetadata.difficulty = flow.originalDifficulty
    }

    func refreshQuestionCategory() {
        guard !categorySourceAI else {
            RuntimeLog.write("question-category-ai-preserved \(session.category.rawValue)")
            return
        }
        session.category = SessionCategory.infer(from: session.ocrDocument.editedText)
        RuntimeLog.write("question-category \(session.category.rawValue)")
    }

    func applyGeneratedQuestion(
        _ question: String,
        correctAnswer: String?,
        category: SessionCategory?,
        learningMetadata: SATLearningMetadata
    ) {
        let retainedMessages = TutorSessionMutation.messagesArchivedForQuestionTransition(in: session)
        TutorSessionMutation.applyFormattedQuestion(question, answer: correctAnswer, category: category, to: session)
        session.messages = retainedMessages
        session.learningMetadata = learningMetadata
        resetTransientState()
        viewMode = .text
        categorySourceAI = false
        applyMetadataCategory(category)
        if category == nil {
            refreshQuestionCategory()
        }
    }

    func applyMetadataCategory(_ category: SessionCategory?) {
        guard let category, category != .unknown else { return }
        session.category = category
        categorySourceAI = true
        RuntimeLog.write("question-category-metadata \(category.rawValue)")
    }
}
