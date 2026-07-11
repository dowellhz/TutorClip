import Foundation

enum SATLearningGap: String, Codable, CaseIterable, Identifiable {
    case englishReading, comprehension, concept, application, explanationStillUnclear
    case mathConcept, mathModeling, mathExecution, mathRepresentation
    case aiDiagnose
    var id: String { rawValue }

    func title(language: AppLanguage) -> String {
        switch self {
        case .englishReading: return language.text("英文读不懂", "I can't read the English")
        case .comprehension: return language.text("英文能读懂，但不明白题意", "I can read it but don't understand the task")
        case .concept: return language.text("不知道考点", "I don't know the skill")
        case .application: return language.text("知道考点但不会做", "I can't apply it")
        case .explanationStillUnclear: return language.text("看完解析还是不懂", "The explanation is unclear")
        case .mathConcept: return language.text("公式或概念不会", "Formula or concept gap")
        case .mathModeling: return language.text("不会列式或建模", "Can't model the problem")
        case .mathExecution: return language.text("步骤或计算卡住", "Stuck on steps or calculation")
        case .mathRepresentation: return language.text("图表或函数看不懂", "Can't read the graph or function")
        case .aiDiagnose: return language.text("不确定，让 AI 判断", "Let AI diagnose")
        }
    }
}

enum SATEnglishBarrier: String, Codable, CaseIterable, Identifiable {
    case vocabulary, sentenceStructure, answerChoices, wholePassage
    var id: String { rawValue }

    func title(language: AppLanguage) -> String {
        switch self {
        case .vocabulary: return language.text("生词太多", "Too many unknown words")
        case .sentenceStructure: return language.text("长难句看不懂", "Difficult sentence structure")
        case .answerChoices: return language.text("选项读不懂", "I can't read the choices")
        case .wholePassage: return language.text("整段读不懂", "I can't understand the passage")
        }
    }
}

enum SATNeedsReviewStage: String, Codable {
    case inactive, chooseGap, chooseEnglishBarrier, planReady, foundation, microCheck, easyPractice, returnToOriginal, originalQuestion, pendingVerification, scheduled
}

enum SATQuestionChainRole: String, Codable {
    case original, easyPractice, verification

    func title(language: AppLanguage) -> String {
        switch self {
        case .original: return language.text("原题", "Original")
        case .easyPractice: return language.text("简单同类题", "Easy Practice")
        case .verification: return language.text("原难度验证", "Verification")
        }
    }
}

struct SATQuestionSnapshot: Codable, Equatable, Identifiable {
    var id = UUID()
    var role: SATQuestionChainRole
    var text: String
    var correctAnswer: String?
    var category: SessionCategory
    var difficulty: SATDifficulty
}

struct SATMicroCheck: Codable, Equatable {
    var question: String
    var choices: [String]
    var correctAnswer: String

    static func extract(from raw: String) -> (check: SATMicroCheck?, body: String) {
        guard let start = raw.range(of: "MICRO_CHECK"),
              let end = raw.range(of: "END_MICRO_CHECK", range: start.upperBound..<raw.endIndex) else {
            return (nil, raw)
        }
        let block = String(raw[start.upperBound..<end.lowerBound])
        let lines = block.split(whereSeparator: \.isNewline).map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
        let question = field("Question", lines: lines)
        let answerField = field("Answer", lines: lines).uppercased()
        let answer = answerField.first(where: { "ABCD".contains($0) }).map(String.init) ?? ""
        let choices = lines.compactMap(protocolChoice)
        var body = raw
        body.removeSubrange(start.lowerBound..<end.upperBound)
        let check = question.isEmpty || choices.count < 2 || !"ABCD".contains(answer) ? nil : SATMicroCheck(question: question, choices: choices, correctAnswer: String(answer.prefix(1)))
        return (check, body.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private static func field(_ name: String, lines: [String]) -> String {
        for delimiter in [":", "："] {
            let prefix = "\(name)\(delimiter)"
            if let line = lines.first(where: { $0.lowercased().hasPrefix(prefix.lowercased()) }) {
                return String(line.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        return ""
    }

    private static func protocolChoice(_ rawLine: String) -> String? {
        var line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
        if line.hasPrefix("- ") { line.removeFirst(2) }
        line = line.replacingOccurrences(of: "**", with: "")
        guard let letter = line.first, "ABCD".contains(letter) else { return nil }
        let remainder = line.dropFirst().trimmingCharacters(in: .whitespaces)
        guard let delimiter = remainder.first, [".", ")", ":", "：", "、"].contains(String(delimiter)) else { return nil }
        let content = remainder.dropFirst().trimmingCharacters(in: .whitespaces)
        guard !content.isEmpty else { return nil }
        return "\(letter). \(content)"
    }
}

struct SATMicroCheckAttempt: Codable, Equatable, Identifiable {
    var id = UUID()
    var completedAt = Date()
    var check: SATMicroCheck
    var selectedAnswer: String
    var wasCorrect: Bool
}

struct SATLearningFocus: Codable, Equatable {
    var type: String
    var text: String
    var objective: String

    static func extract(from raw: String) -> (focus: SATLearningFocus?, body: String) {
        guard let start = raw.range(of: "LEARNING_FOCUS"),
              let end = raw.range(of: "END_LEARNING_FOCUS", range: start.upperBound..<raw.endIndex) else {
            return (nil, raw)
        }
        let lines = raw[start.upperBound..<end.lowerBound]
            .split(whereSeparator: \.isNewline)
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
        let type = field("Type", lines: lines)
        let text = field("Text", lines: lines)
        let objective = field("Objective", lines: lines)
        var body = raw
        body.removeSubrange(start.lowerBound..<end.upperBound)
        let focus = type.isEmpty || text.isEmpty || objective.isEmpty
            ? nil
            : SATLearningFocus(type: type, text: text, objective: objective)
        return (focus, body.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private static func field(_ name: String, lines: [String]) -> String {
        let prefix = "\(name):"
        return lines.first(where: { $0.lowercased().hasPrefix(prefix.lowercased()) })
            .map { String($0.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines) } ?? ""
    }
}

struct SATNeedsReviewFlow: Codable, Equatable {
    var stage: SATNeedsReviewStage = .inactive
    var gap: SATLearningGap?
    var englishBarrier: SATEnglishBarrier?
    var learningFocus: SATLearningFocus?
    var microCheck: SATMicroCheck?
    var completedMicroChecks: [SATMicroCheckAttempt] = []
    var microCheckAttempts = 0
    var originalDifficulty: SATDifficulty = .unknown
    var questionChain: [SATQuestionSnapshot] = []
}
