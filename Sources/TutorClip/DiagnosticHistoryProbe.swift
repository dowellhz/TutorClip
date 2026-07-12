import AppKit
import Foundation

enum DiagnosticHistoryProbe {
    static func runBlocking() {
        let semaphore = DispatchSemaphore(value: 0)
        let completedBox = LockedBox(false)
        let resultBox = LockedBox(false)
        Task { @MainActor in
            resultBox.set(await run())
            completedBox.set(true)
            semaphore.signal()
        }
        let deadline = Date().addingTimeInterval(5)
        while semaphore.wait(timeout: .now()) == .timedOut, Date() < deadline {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.02))
        }
        guard completedBox.value() else {
            fputs("History round-trip probe timed out.\n", stderr)
            exit(2)
        }
        guard resultBox.value() else {
            fputs("History round-trip probe failed.\n", stderr)
            exit(2)
        }
    }

    @MainActor
    private static func run() async -> Bool {
        let baseURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("tutorclip-history-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: baseURL) }

        let store = HistoryStore(baseDirectory: baseURL)
        store.open()
        let session = makeSession()
        let saved = await save(session: session, in: store)
        let loaded = store.sessions.first
        store.close()

        let detailsPreserved = loaded?.ocrDocument.editedText == session.ocrDocument.editedText
            && loaded?.messages.first?.content == session.messages.first?.content
            && loaded?.messages.first?.role == session.messages.first?.role
            && loaded?.messages.first?.actionType == session.messages.first?.actionType
        let learningExcluded = loaded?.selectedAnswer == nil
            && loaded?.correctAnswer == nil
            && loaded?.vocabularyCards.isEmpty == true
            && loaded?.studyStatus == .unreviewed
        let screenshotDiscarded = loaded?.screenshotInMemory == nil

        print("historySaved=\(saved)")
        print("historyDetailsPreserved=\(detailsPreserved)")
        print("historyLearningMetadataExcluded=\(learningExcluded)")
        print("historyScreenshotDiscarded=\(screenshotDiscarded)")
        return saved && detailsPreserved && learningExcluded && screenshotDiscarded
    }

    @MainActor
    private static func save(session: TutorSession, in store: HistoryStore) async -> Bool {
        await withCheckedContinuation { continuation in
            store.save(
                session: session,
                detailedHistoryEnabled: true,
                learningProgressEnabled: false
            ) { success in
                continuation.resume(returning: success)
            }
        }
    }

    private static func makeSession() -> TutorSession {
        let id = UUID()
        return TutorSession(
            id: id,
            title: "Synthetic SAT Session",
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
            messages: [
                ChatMessage(id: UUID(), sessionId: id, role: .assistant, content: "Synthetic explanation.", createdAt: Date(), actionType: .explainAll)
            ],
            screenshotInMemory: NSImage(size: NSSize(width: 12, height: 12)),
            category: .reading,
            studyStatus: .mistake,
            selectedAnswer: "C",
            correctAnswer: "B",
            vocabularyCards: [
                VocabularyCard(id: UUID(), term: "synthetic", meaning: "合成的", note: "test card", example: "This is synthetic.", source: "Synthetic")
            ]
        )
    }
}
