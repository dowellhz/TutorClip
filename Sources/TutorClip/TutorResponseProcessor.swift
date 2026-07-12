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
        case .guidedLearning:
            return ProcessedTutorResponse(content: rawContent, answerSummary: nil, vocabularyCards: [])
        default:
            return ProcessedTutorResponse(
                content: rawContent,
                answerSummary: nil,
                vocabularyCards: []
            )
        }
    }
}

enum VocabularyResponseRepairer {
    static func repairIfNeeded(
        _ response: ProcessedTutorResponse,
        rawContent: String,
        client: any DeepSeekStreaming
    ) async throws -> ProcessedTutorResponse {
        guard response.vocabularyCards.isEmpty,
              !rawContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return response }
        var repaired = ""
        let messages = [
            DeepSeekMessage(role: "system", content: """
            你是词卡协议修复器。保持原响应中的词汇及含义，不新增词，只补成指定机器块。
            每个词一行，字段名必须是 Term、Meaning、Note、Example、Source。
            输出必须以 VOCAB_CARDS 开始、END_VOCAB_CARDS 结束；块后可保留原来的可读 Markdown。不要解释修复过程。
            """),
            DeepSeekMessage(role: "user", content: rawContent)
        ]
        try await client.stream(messages: messages, temperatureOverride: 0) { repaired += $0 }
        try Task.checkCancellation()
        let parsed = TutorResponseProcessor.process(rawContent: repaired, action: .vocabulary)
        guard !parsed.vocabularyCards.isEmpty else {
            RuntimeLog.write("vocabulary-protocol-repair-rejected")
            return response
        }
        RuntimeLog.write("vocabulary-protocol-repair-applied cards=\(parsed.vocabularyCards.count)")
        return parsed
    }
}
