import Foundation

enum LearningLoadingAction {
    case foundation, alternativeExplanation, prerequisiteExplanation, microCheck, easyPractice, verification
}

struct TutorRequest {
    var action: TutorAction
    var question: String?
}

enum OCRFormatState: Equatable {
    case idle
    case formatting
    case applied
    case failed(String)

    var isVisible: Bool {
        switch self {
        case .idle:
            return false
        case .formatting, .applied, .failed:
            return true
        }
    }

    var isError: Bool {
        if case .failed = self { return true }
        return false
    }

    func message(language: AppLanguage) -> String {
        switch self {
        case .idle:
            return ""
        case .formatting:
            return language.text("本地 OCR 已可阅读；正在用 Flash 整理排版...", "Local OCR is ready; Flash is formatting it...")
        case .applied:
            return language.text("题目已按 Markdown 排版。", "Question was formatted as Markdown.")
        case .failed(let reason):
            return language.text("题目排版失败，已保留本地 OCR 原文：\(reason)", "Question formatting failed. Local OCR text was kept: \(reason)")
        }
    }
}

extension TutorAction {
    var usesSelectedTextSummary: Bool {
        self == .translateSelection || self == .explainSelection || self == .vocabulary
    }

    var usesOnlySelectedText: Bool {
        self == .translateSelection || self == .vocabulary
    }

    var suppressesQuestionGuidance: Bool {
        self == .translateSelection || self == .vocabulary || self == .translateAll || self == .guidedLearning
    }
}

enum SourceViewMode: String, CaseIterable, Identifiable {
    case text
    case screenshot

    var id: String { rawValue }

    func title(language: AppLanguage) -> String {
        switch self {
        case .text: return language.text("题目", "Question")
        case .screenshot: return language.text("截图", "Screenshot")
        }
    }
}
