import Foundation

struct TutorChatRequest {
    var selectedText: String
    var userMessage: ChatMessage
    var assistantMessage: ChatMessage
    var deepSeekMessages: [DeepSeekMessage]
}

struct TutorChatRequestBuilder {
    let promptBuilder: PromptBuilder

    func makeRequest(
        action: TutorAction,
        question: String?,
        session: TutorSession,
        language: AppLanguage,
        selectedText: String
    ) -> TutorChatRequest {
        let selected = selectedText.trimmingCharacters(in: .whitespacesAndNewlines)
        var userContent = promptBuilder.userPrompt(
            action: action,
            document: session.ocrDocument,
            selectedText: selected.isEmpty ? nil : selected,
            customQuestion: question,
            category: session.category,
            language: language
        )
        if action == .explainAll,
           session.learningMetadata.isAIVerified,
           let verifiedAnswer = session.correctAnswer {
            userContent += "\n\n已由独立判题流程验证的正确答案：\(verifiedAnswer)。讲解必须以此答案为准；如果你的推理冲突，请重新核对题目数据，不得改写该答案。"
        }
        let userMessage = ChatMessage(
            id: UUID(),
            sessionId: session.id,
            role: .user,
            content: TutorQuestionParsing.userMessageContent(
                action: action,
                selectedText: selected,
                question: question,
                language: language
            ),
            createdAt: Date(),
            actionType: action,
            contextDocumentID: session.ocrDocument.id
        )
        let assistantMessage = ChatMessage(
            id: UUID(),
            sessionId: session.id,
            role: .assistant,
            content: "",
            createdAt: Date(),
            actionType: action,
            contextDocumentID: session.ocrDocument.id
        )

        let systemPrompt: String
        if action == .guidedLearning {
            systemPrompt = promptBuilder.guidedLearningSystemPrompt(language: language)
        } else if action == .customQuestion {
            systemPrompt = promptBuilder.customQuestionSystemPrompt(language: language)
        } else {
            systemPrompt = promptBuilder.systemPrompt(language: language)
        }
        var deepSeekMessages = [DeepSeekMessage(role: "system", content: systemPrompt)]
        let currentContextMessages = session.messages.filter {
            ($0.contextDocumentID == nil || $0.contextDocumentID == session.ocrDocument.id)
                && ($0.role == .user || $0.role == .assistant)
        }
        for message in currentContextMessages.suffix(8) {
            deepSeekMessages.append(DeepSeekMessage(role: message.role.rawValue, content: message.content))
        }
        deepSeekMessages.append(DeepSeekMessage(role: "user", content: userContent))

        return TutorChatRequest(
            selectedText: selected,
            userMessage: userMessage,
            assistantMessage: assistantMessage,
            deepSeekMessages: deepSeekMessages
        )
    }
}
