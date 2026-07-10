import Foundation

struct ProcessedTutorResponse {
    var content: String
    var answerSummary: AnswerSummary?
    var vocabularyCards: [VocabularyCard]
}

enum TutorResponseProcessor {
    static func process(rawContent: String, action: TutorAction) -> ProcessedTutorResponse {
        switch action {
        case .explainAll:
            let parsed = AnswerSummary.extract(from: rawContent)
            return ProcessedTutorResponse(
                content: parsed.body.isEmpty ? rawContent : parsed.body,
                answerSummary: parsed.summary,
                vocabularyCards: []
            )
        case .vocabulary:
            let parsed = VocabularyCard.extract(from: rawContent)
            return ProcessedTutorResponse(
                content: parsed.cards.isEmpty || parsed.body.isEmpty ? rawContent : parsed.body,
                answerSummary: nil,
                vocabularyCards: parsed.cards
            )
        default:
            return ProcessedTutorResponse(
                content: rawContent,
                answerSummary: nil,
                vocabularyCards: []
            )
        }
    }
}
