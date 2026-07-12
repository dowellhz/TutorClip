import Foundation

enum QuestionUnderlineMarkup {
    struct Segment: Equatable {
        var text: String
        var isUnderlined: Bool
    }

    private static let references = [
        "underlined portion", "underlined sentence", "underlined phrase", "underlined text",
        "划线部分", "下划线部分", "下划线内容"
    ]

    static func satisfiesReferenceContract(_ question: String) -> Bool {
        let lowercased = question.lowercased()
        guard references.contains(where: lowercased.contains) else { return true }
        return segments(in: question).contains {
            $0.isUnderlined && !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    static func segments(in source: String) -> [Segment] {
        var result: [Segment] = []
        var remainder = source[...]
        while let opening = remainder.range(of: "<u>", options: .caseInsensitive) {
            append(String(remainder[..<opening.lowerBound]), underlined: false, to: &result)
            let afterOpening = remainder[opening.upperBound...]
            guard let closing = afterOpening.range(of: "</u>", options: .caseInsensitive) else {
                append(String(afterOpening), underlined: false, to: &result)
                return result
            }
            append(String(afterOpening[..<closing.lowerBound]), underlined: true, to: &result)
            remainder = afterOpening[closing.upperBound...]
        }
        append(String(remainder), underlined: false, to: &result)
        return result
    }

    private static func append(_ text: String, underlined: Bool, to segments: inout [Segment]) {
        guard !text.isEmpty else { return }
        segments.append(Segment(text: text, isUnderlined: underlined))
    }
}

struct PracticeValidationResult: Equatable {
    var isValid: Bool
    var reason: String

    static func parse(_ raw: String) -> PracticeValidationResult {
        let fields = raw.split(whereSeparator: \.isNewline).map(String.init)
        let valid = fields.first { $0.lowercased().hasPrefix("valid:") }?
            .split(separator: ":", maxSplits: 1).last?
            .trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "yes"
        let reasonLine = fields.first { $0.lowercased().hasPrefix("reason:") } ?? ""
        let reason = reasonLine.split(separator: ":", maxSplits: 1).last
            .map(String.init)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return PracticeValidationResult(isValid: valid, reason: reason)
    }
}

@MainActor
struct PracticeQuestionValidator {
    let client: any DeepSeekStreaming

    func validate(
        _ question: GeneratedQuestion,
        expectedQuestionTypeID: String = "",
        expectedKnowledgePointIDs: [String] = []
    ) async throws -> PracticeValidationResult {
        guard question.contract.isComplete else {
            return PracticeValidationResult(isValid: false, reason: "missing structured teaching contract")
        }
        guard QuestionUnderlineMarkup.satisfiesReferenceContract(question.question) else {
            return PracticeValidationResult(isValid: false, reason: "question refers to underlined text but does not mark the target with <u> tags")
        }
        guard GeneratedQuestionStructure.containsExactlyOneQuestion(question.question) else {
            return PracticeValidationResult(isValid: false, reason: "practice output must contain exactly one question")
        }
        let choiceLabels = TutorQuestionParsing.answerChoices(from: question.question)
        guard choiceLabels == ["A", "B", "C", "D"] else {
            return PracticeValidationResult(isValid: false, reason: "question must contain complete A/B/C/D choices")
        }
        guard let answer = question.answer?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased().first,
              choiceLabels.contains(String(answer)) else {
            return PracticeValidationResult(isValid: false, reason: "declared answer is not one of the displayed choices")
        }
        var raw = ""
        let metadata = question.learningMetadata
        let expectedKnowledge = expectedKnowledgePointIDs.compactMap {
            SATKnowledgeCatalog.knowledgePoint(id: $0).map { "\($0.titleEN) [\($0.id)]" }
        }.joined(separator: ", ")
        let prompt = """
        Independently validate this AI-generated SAT practice question. Check that it has exactly one correct answer, that the declared answer is correct, that it matches the declared SAT domain and skill, and that it is unambiguous. When an expected teacher target is provided, return Valid: yes only if the actual question genuinely tests that exact target; do not rely only on the generator's declared metadata. Output exactly:
        VALIDATION_RESULT
        Valid: yes or no
        Reason: concise reason
        END_VALIDATION_RESULT

        Declared answer: \(question.answer ?? "unknown")
        Domain: \(metadata.domain)
        Skill: \(metadata.skill)
        Difficulty: \(metadata.difficulty.rawValue)
        Expected question type ID: \(expectedQuestionTypeID.isEmpty ? "not specified" : expectedQuestionTypeID)
        Expected knowledge target: \(expectedKnowledge.isEmpty ? "not specified" : expectedKnowledge)

        QUESTION
        \(question.question)
        END_QUESTION
        """
        try await client.stream(messages: [
            DeepSeekMessage(role: "system", content: "You are a strict SAT question quality reviewer. Do not solve for the student; only return the validation protocol."),
            DeepSeekMessage(role: "user", content: prompt)
        ], temperatureOverride: 0) { raw += $0 }
        return PracticeValidationResult.parse(raw)
    }
}

enum GeneratedQuestionStructure {
    static func containsExactlyOneQuestion(_ text: String) -> Bool {
        let normalized = text.lowercased()
        let groupedHeadings = ["questions 1-2", "questions 1–2", "questions 1 and 2"]
        guard !groupedHeadings.contains(where: normalized.contains) else { return false }
        let trimmedLines = text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        return !trimmedLines.contains { $0.hasPrefix("2.") || $0.hasPrefix("2)") }
    }
}

@MainActor
struct MicroCheckValidator {
    let client: any DeepSeekStreaming

    func validate(_ check: SATMicroCheck, focus: SATLearningFocus) async throws -> PracticeValidationResult {
        var raw = ""
        let prompt = """
        Validate this short learning check. It must test only the declared learning focus, have exactly one correct answer, and must not test or reveal the original SAT question's answer. Return exactly:
        Valid: yes or no
        Reason: concise reason

        Focus type: \(focus.type)
        Focus text: \(focus.text)
        Objective: \(focus.objective)
        Question: \(check.question)
        Choices: \(check.choices.joined(separator: " | "))
        Declared answer: \(check.correctAnswer)
        """
        try await client.stream(messages: [
            DeepSeekMessage(role: "system", content: "You strictly validate a tiny learning check. Return only Valid and Reason fields."),
            DeepSeekMessage(role: "user", content: prompt)
        ], temperatureOverride: 0) { raw += $0 }
        return PracticeValidationResult.parse(raw)
    }
}
