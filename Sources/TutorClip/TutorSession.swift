import AppKit
import Foundation

final class TutorSession: ObservableObject, Identifiable {
    let id: UUID
    @Published var title: String
    let createdAt: Date
    @Published var updatedAt: Date
    @Published var ocrDocument: OCRDocument
    @Published var messages: [ChatMessage]
    @Published var screenshotInMemory: NSImage?
    @Published var category: SessionCategory
    @Published var studyStatus: StudyStatus
    @Published var selectedAnswer: String?
    @Published var correctAnswer: String?
    @Published var vocabularyCards: [VocabularyCard]

    init(id: UUID, title: String, createdAt: Date, updatedAt: Date, ocrDocument: OCRDocument, messages: [ChatMessage], screenshotInMemory: NSImage?, category: SessionCategory, studyStatus: StudyStatus = .unreviewed, selectedAnswer: String? = nil, correctAnswer: String? = nil, vocabularyCards: [VocabularyCard] = []) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.ocrDocument = ocrDocument
        self.messages = messages
        self.screenshotInMemory = screenshotInMemory
        self.category = category
        self.studyStatus = studyStatus
        self.selectedAnswer = selectedAnswer
        self.correctAnswer = correctAnswer
        self.vocabularyCards = vocabularyCards
    }

    static func newSession(screenshot: NSImage?) -> TutorSession {
        TutorSession(
            id: UUID(),
            title: "New Capture",
            createdAt: Date(),
            updatedAt: Date(),
            ocrDocument: OCRDocument.empty(),
            messages: [],
            screenshotInMemory: screenshot,
            category: .unknown,
            vocabularyCards: []
        )
    }

    func discardScreenshot() {
        screenshotInMemory = nil
    }
}

enum StudyStatus: String, Codable, CaseIterable {
    case unreviewed
    case known
    case needsReview
    case mistake

    func title(language: AppLanguage) -> String {
        switch self {
        case .unreviewed: return language.text("未复习", "Unreviewed")
        case .known: return language.text("会了", "Got it")
        case .needsReview: return language.text("不会", "Review")
        case .mistake: return language.text("错题", "Mistake")
        }
    }
}

enum SessionCategory: String, Codable, CaseIterable {
    case reading
    case writing
    case notesSynthesis
    case vocabulary
    case grammar
    case math
    case unknown

    var displayName: String {
        displayName(language: .english)
    }

    func displayName(language: AppLanguage) -> String {
        switch self {
        case .reading: return language.text("阅读", "Reading")
        case .writing: return language.text("写作", "Writing")
        case .notesSynthesis: return language.text("笔记综合", "Notes")
        case .vocabulary: return language.text("词汇", "Vocabulary")
        case .grammar: return language.text("语法", "Grammar")
        case .math: return language.text("数学", "Math")
        case .unknown: return language.text("未知", "Unknown")
        }
    }

    static func infer(from text: String) -> SessionCategory {
        QuestionClassifier.classify(text)
    }
}

enum SessionTitle {
    static func make(from text: String) -> String {
        let normalized = text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        if normalized.isEmpty { return "Untitled Session" }
        return String(normalized.prefix(54))
    }
}
