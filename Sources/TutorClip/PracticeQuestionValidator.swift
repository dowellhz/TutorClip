import Foundation

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

    func validate(_ question: GeneratedQuestion) async throws -> PracticeValidationResult {
        var raw = ""
        let metadata = question.learningMetadata
        let prompt = """
        Independently validate this AI-generated SAT practice question. Check that it has exactly one correct answer, that the declared answer is correct, that it matches the declared SAT domain and skill, and that it is unambiguous. Output exactly:
        VALIDATION_RESULT
        Valid: yes or no
        Reason: concise reason
        END_VALIDATION_RESULT

        Declared answer: \(question.answer ?? "unknown")
        Domain: \(metadata.domain)
        Skill: \(metadata.skill)
        Difficulty: \(metadata.difficulty.rawValue)

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
