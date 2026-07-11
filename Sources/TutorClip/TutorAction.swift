enum TutorAction: String, Codable, CaseIterable {
    case explainAll
    case translateAll
    case formatOCR
    case checkOCR
    case translateSelection
    case explainSelection
    case vocabulary
    case grammar
    case practiceSimilar
    case customQuestion
    case guidedLearning

    static let selectedTextActions: [TutorAction] = [.translateSelection, .vocabulary]
    static let sourceLeadingActions: [TutorAction] = [.vocabulary, .grammar]
    static let sourceTrailingActions: [TutorAction] = [.practiceSimilar, .translateAll, .explainAll]

    var title: String {
        title(language: .chinese)
    }

    func title(language: AppLanguage) -> String {
        switch self {
        case .explainAll: return language.text("讲解整题", "Explain")
        case .translateAll: return language.text("翻译全文", "Translate")
        case .formatOCR: return language.text("整理 OCR", "Format OCR")
        case .checkOCR: return language.text("检查 OCR", "Check OCR")
        case .translateSelection: return language.text("翻译", "Translate")
        case .explainSelection: return language.text("讲题", "Explain")
        case .vocabulary: return language.text("词汇", "Vocabulary")
        case .grammar: return language.text("解析文章", "Analyze")
        case .practiceSimilar: return language.text("再练一题", "Practice")
        case .customQuestion: return language.text("提问", "Ask")
        case .guidedLearning: return language.text("引导学习", "Guided Learning")
        }
    }
}
