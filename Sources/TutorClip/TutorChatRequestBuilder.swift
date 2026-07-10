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
        let userContent = promptBuilder.userPrompt(
            action: action,
            document: session.ocrDocument,
            selectedText: selected.isEmpty ? nil : selected,
            customQuestion: question,
            category: session.category,
            language: language
        )
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
            actionType: action
        )
        let assistantMessage = ChatMessage(
            id: UUID(),
            sessionId: session.id,
            role: .assistant,
            content: "",
            createdAt: Date(),
            actionType: action
        )

        var deepSeekMessages = [DeepSeekMessage(role: "system", content: promptBuilder.systemPrompt(language: language))]
        for message in session.messages.suffix(8) where message.role == .user || message.role == .assistant {
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
