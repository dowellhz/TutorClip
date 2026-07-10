import AppKit
import Foundation

extension DiagnosticCLI {
    static func runSessionMutationProbe() {
        let session = TutorSession(
            id: UUID(),
            title: "Old",
            createdAt: Date(),
            updatedAt: Date(),
            ocrDocument: OCRDocument(
                id: UUID(),
                fullText: "Old question",
                editedText: "Old question",
                detectedLanguage: "en-US",
                createdAt: Date(),
                blocks: [],
                lines: [],
                tokens: []
            ),
            messages: [
                ChatMessage(id: UUID(), sessionId: UUID(), role: .user, content: "Old message", createdAt: Date(), actionType: .explainAll)
            ],
            screenshotInMemory: NSImage(size: NSSize(width: 10, height: 10)),
            category: .reading,
            studyStatus: .mistake,
            selectedAnswer: "C",
            correctAnswer: "C",
            vocabularyCards: [
                VocabularyCard(id: UUID(), term: "old", meaning: "旧", note: "stale", example: "Old example.", source: "old")
            ]
        )
        TutorSessionMutation.applyFormattedQuestion(
            "New passage\n\nWhich choice?\n\nA) One\n\nB) Two\n\nC) Three\n\nD) Four",
            answer: "B",
            category: .grammar,
            to: session
        )
        let cleared = session.messages.isEmpty
            && session.screenshotInMemory == nil
            && session.selectedAnswer == nil
            && session.vocabularyCards.isEmpty
            && session.studyStatus == StudyStatus.unreviewed
        let applied = session.correctAnswer == "B"
            && session.category == SessionCategory.grammar
            && session.ocrDocument.editedText.contains("New passage")
            && session.title.contains("New passage")
        print("sessionCleared=\(cleared)")
        print("sessionApplied=\(applied)")
        if !cleared || !applied {
            fputs("Session mutation probe failed.\n", stderr)
            exit(2)
        }
    }

    static func runAnswerSelectionProbe() {
        let session = TutorSession(
            id: UUID(),
            title: "Practice",
            createdAt: Date(),
            updatedAt: Date(),
            ocrDocument: OCRDocument(
                id: UUID(),
                fullText: "Passage\n\nWhich choice?\n\nA) One\n\nB) Two\n\nC) Three\n\nD) Four",
                editedText: "Passage\n\nWhich choice?\n\nA) One\n\nB) Two\n\nC) Three\n\nD) Four",
                detectedLanguage: "en-US",
                createdAt: Date(),
                blocks: [],
                lines: [],
                tokens: []
            ),
            messages: [],
            screenshotInMemory: nil,
            category: .reading,
            correctAnswer: "B"
        )
        let choices = TutorQuestionParsing.answerChoices(from: session.ocrDocument.editedText)
        let wrong = TutorSessionMutation.selectAnswer("C", in: session)
        let wrongState = session.studyStatus == StudyStatus.mistake
            && session.selectedAnswer == "C"
            && wrong == .incorrect(selected: "C", correct: "B")
        let correct = TutorSessionMutation.selectAnswer("b", in: session)
        let correctState = session.studyStatus == StudyStatus.known
            && session.selectedAnswer == "B"
            && correct == .correct("B")
        let result = TutorSessionMutation.answerSelectionResult(selected: session.selectedAnswer, correct: session.correctAnswer)
        print("choices=\(choices.joined())")
        print("wrongState=\(wrongState)")
        print("correctState=\(correctState)")
        print("result=\(String(describing: result))")
        if choices != ["A", "B", "C", "D"] || !wrongState || !correctState || result != .correct("B") {
            fputs("Answer selection probe failed.\n", stderr)
            exit(2)
        }
    }

    static func runChatRequestBuilderProbe() {
        let sessionID = UUID()
        let staleFullText = "STALE_FULL_TEXT_SHOULD_NOT_BE_SENT"
        let editedText = "Canonical edited passage\n\nWhich choice?\n\nA) Edited answer."
        let messages = (0..<10).map { index in
            ChatMessage(
                id: UUID(),
                sessionId: sessionID,
                role: index.isMultiple(of: 2) ? .user : .assistant,
                content: "history-\(index)",
                createdAt: Date(),
                actionType: .customQuestion
            )
        }
        let session = TutorSession(
            id: sessionID,
            title: "Builder",
            createdAt: Date(),
            updatedAt: Date(),
            ocrDocument: OCRDocument(
                id: UUID(),
                fullText: staleFullText,
                editedText: editedText,
                detectedLanguage: "en-US",
                createdAt: Date(),
                blocks: [],
                lines: [],
                tokens: []
            ),
            messages: messages,
            screenshotInMemory: nil,
            category: .reading
        )
        let builder = TutorChatRequestBuilder(promptBuilder: PromptBuilder())
        let selectionRequest = builder.makeRequest(
            action: .translateSelection,
            question: nil,
            session: session,
            language: .chinese,
            selectedText: "microstructures"
        )
        let explainRequest = builder.makeRequest(
            action: .explainAll,
            question: nil,
            session: session,
            language: .chinese,
            selectedText: ""
        )
        let roles = selectionRequest.deepSeekMessages.map(\.role)
        let contents = selectionRequest.deepSeekMessages.map(\.content)
        let keepsRecentHistory = contents.contains("history-2")
            && contents.contains("history-9")
            && !contents.contains("history-0")
            && !contents.contains("history-1")
        let systemAndUserWrapped = roles.first == "system" && roles.last == "user"
        let selectedOnly = contents.last?.contains("microstructures") == true
            && contents.last?.contains(editedText) == false
        let explainContent = explainRequest.deepSeekMessages.last?.content ?? ""
        let explainUsesEditedText = explainContent.contains(editedText)
        let explainAvoidsStaleFullText = !explainContent.contains(staleFullText)
        print("chatRequestMessageCount=\(selectionRequest.deepSeekMessages.count)")
        print("chatRequestKeepsRecentHistory=\(keepsRecentHistory)")
        print("chatRequestSystemAndUserWrapped=\(systemAndUserWrapped)")
        print("chatRequestSelectedOnly=\(selectedOnly)")
        print("chatRequestExplainUsesEditedText=\(explainUsesEditedText)")
        print("chatRequestExplainAvoidsStaleFullText=\(explainAvoidsStaleFullText)")
        if selectionRequest.deepSeekMessages.count != 10
            || !keepsRecentHistory
            || !systemAndUserWrapped
            || !selectedOnly
            || !explainUsesEditedText
            || !explainAvoidsStaleFullText {
            fputs("Chat request builder probe failed.\n", stderr)
            exit(2)
        }
    }

    static func runUserMessageSummaryProbe() {
        let longSelection = """
        microstructures in their feathers to manipulate light, creating the appearance of deeper saturation without maintaining a carotenoid-rich diet
        """
        let message = TutorQuestionParsing.userMessageContent(
            action: .vocabulary,
            selectedText: longSelection,
            question: nil,
            language: .chinese
        )
        let singleLine = !message.contains("\n")
        let hasActionPrefix = message.hasPrefix("词汇：microstructures")
        let isTruncated = message.hasSuffix("...") && message.count < longSelection.count
        print("userMessageSummarySingleLine=\(singleLine)")
        print("userMessageSummaryHasActionPrefix=\(hasActionPrefix)")
        print("userMessageSummaryTruncated=\(isTruncated)")
        if !singleLine || !hasActionPrefix || !isTruncated {
            fputs("User message summary probe failed.\n", stderr)
            exit(2)
        }
    }

    static func runLanguagePolicyProbe() {
        let builder = PromptBuilder()
        var document = OCRDocument.empty()
        document.editedText = "Synthetic SAT question\n\nA) One"
        let chineseSystem = builder.systemPrompt(language: .chinese)
        let englishSystem = builder.systemPrompt(language: .english)
        let chineseUser = builder.userPrompt(
            action: .explainAll,
            document: document,
            selectedText: nil,
            customQuestion: nil,
            category: .reading,
            language: .chinese
        )
        let englishUser = builder.userPrompt(
            action: .explainAll,
            document: document,
            selectedText: nil,
            customQuestion: nil,
            category: .reading,
            language: .english
        )
        let actionTitlesSwitch = TutorAction.explainAll.title(language: .chinese) == "讲解整题"
            && TutorAction.explainAll.title(language: .english) == "Explain"
            && TutorAction.grammar.title(language: .chinese) == "解析文章"
            && TutorAction.grammar.title(language: .english) == "Analyze"
        let sourceTabsSwitch = SourceViewMode.text.title(language: .chinese) == "题目"
            && SourceViewMode.text.title(language: .english) == "Question"
            && SourceViewMode.screenshot.title(language: .chinese) == "截图"
            && SourceViewMode.screenshot.title(language: .english) == "Screenshot"
        let systemPromptsSwitch = chineseSystem.contains("默认用中文回答")
            && englishSystem.contains("Answer in English by default")
            && !englishSystem.contains("默认用中文回答")
        let userPromptsSwitch = chineseUser.contains("OCR 全文")
            && chineseUser.contains("任务")
            && englishUser.contains("Full OCR text")
            && englishUser.contains("Task")
            && !englishUser.contains("OCR 全文")
        print("languageActionTitlesSwitch=\(actionTitlesSwitch)")
        print("languageSourceTabsSwitch=\(sourceTabsSwitch)")
        print("languageSystemPromptsSwitch=\(systemPromptsSwitch)")
        print("languageUserPromptsSwitch=\(userPromptsSwitch)")
        if !actionTitlesSwitch || !sourceTabsSwitch || !systemPromptsSwitch || !userPromptsSwitch {
            fputs("Language policy probe failed.\n", stderr)
            exit(2)
        }
    }
}
