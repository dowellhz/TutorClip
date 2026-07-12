import Foundation

/// Narrow stability fallback used only after two AI table-layout attempts omit answer choices.
/// It copies exact source blocks and never changes or replaces choices already present.
enum MissingChoiceFallback {
    static func restore(source: String, candidate: String) -> String {
        let sourceBlocks = choiceBlocks(in: source)
        let candidateLabels = Set(TutorQuestionParsing.answerChoices(from: candidate))
        let missing = ["A", "B", "C", "D"].compactMap { label -> String? in
            guard !candidateLabels.contains(label) else { return nil }
            return sourceBlocks[label]
        }
        guard !missing.isEmpty else { return candidate }
        return ([candidate.trimmingCharacters(in: .whitespacesAndNewlines)] + missing)
            .joined(separator: "\n\n")
    }

    private static func choiceBlocks(in text: String) -> [String: String] {
        var result: [String: String] = [:]
        var activeLabel: String?
        var activeLines: [String] = []

        func finishBlock() {
            guard let activeLabel else { return }
            let block = activeLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            if !block.isEmpty { result[activeLabel] = block }
        }

        for line in text.components(separatedBy: .newlines) {
            if let label = choiceLabel(atStartOf: line) {
                finishBlock()
                activeLabel = label
                activeLines = [line.trimmingCharacters(in: .whitespaces)]
            } else if activeLabel != nil {
                activeLines.append(line)
            }
        }
        finishBlock()
        return result
    }

    private static func choiceLabel(atStartOf line: String) -> String? {
        TutorQuestionParsing.answerChoiceLabel(atStartOf: line)
    }
}
