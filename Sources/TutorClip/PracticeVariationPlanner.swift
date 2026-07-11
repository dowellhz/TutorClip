import Foundation

struct PracticeVariation: Equatable {
    let topic: String
    let structure: String
    let answerPosition: String
}

final class PracticeVariationPlanner {
    static let practiceTemperature = 0.8
    static let recentQuestionLimit = 5

    private let topics = [
        "natural science", "social science", "history", "arts and literature",
        "technology", "everyday quantitative reasoning"
    ]
    private let structures = [
        "use a different passage organization", "use a different evidence pattern",
        "use a different sentence construction", "use a different distractor strategy"
    ]
    private let answerPositions = ["A", "B", "C", "D"]
    private var generationIndex = 0
    private(set) var recentQuestions: [String] = []

    func nextVariation() -> PracticeVariation {
        defer { generationIndex += 1 }
        return PracticeVariation(
            topic: topics[generationIndex % topics.count],
            structure: structures[(generationIndex * 3 + 1) % structures.count],
            answerPosition: answerPositions[(generationIndex * 3 + 2) % answerPositions.count]
        )
    }

    func diversityInstruction(for variation: PracticeVariation, retrying: Bool) -> String {
        let recentSection = recentQuestions.isEmpty
            ? "There are no earlier generated practice questions to avoid."
            : "Do not reproduce or closely paraphrase any of these recent generated questions:\n" + recentQuestions.enumerated().map { index, question in
                "RECENT_QUESTION_\(index + 1):\n\(String(question.prefix(1_200)))"
            }.joined(separator: "\n")
        let retryInstruction = retrying
            ? "The previous attempt was rejected as a duplicate. Change the scenario, wording, reasoning path, values, and distractors substantially."
            : "Before answering, silently compare the new question with the recent questions and redesign it if it is substantially similar."

        return """
        DIVERSITY_REQUIREMENTS
        - New subject area: \(variation.topic)
        - Structural variation: \(variation.structure)
        - Put the correct answer at position \(variation.answerPosition), while keeping all choices plausible.
        - Preserve only the tested SAT skill and approximate difficulty. Change the scenario, source material, wording, reasoning path, values, and distractor design.
        - \(retryInstruction)
        \(recentSection)
        END_DIVERSITY_REQUIREMENTS
        """
    }

    func isExactDuplicate(_ question: String) -> Bool {
        let candidate = normalized(question)
        return recentQuestions.contains { normalized($0) == candidate }
    }

    func record(_ question: String) {
        recentQuestions.append(question)
        if recentQuestions.count > Self.recentQuestionLimit {
            recentQuestions.removeFirst(recentQuestions.count - Self.recentQuestionLimit)
        }
    }

    func reset() {
        recentQuestions = []
        generationIndex = 0
    }

    private func normalized(_ question: String) -> String {
        question.split(whereSeparator: \.isWhitespace).joined(separator: " ").lowercased()
    }
}
