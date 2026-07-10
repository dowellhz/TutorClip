import Foundation

enum QuestionClassifier {
    static func classify(_ text: String) -> SessionCategory {
        let normalized = text.lowercased()
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "  ", with: " ")
        guard !normalized.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return .unknown
        }

        if isMath(normalized) { return .math }
        if isNotesSynthesis(normalized) { return .notesSynthesis }
        if isVocabulary(normalized) { return .vocabulary }
        if isGrammar(normalized) { return .grammar }
        if isWriting(normalized) { return .writing }
        if isReading(normalized) { return .reading }
        return .unknown
    }

    private static func isMath(_ text: String) -> Bool {
        let signals = [
            "solve the equation", "equation", "graph of", "triangle", "circle",
            "integer", "linear", "quadratic", "slope", "percent", "probability",
            "x =", "y =", "f(x)", "g(x)", "system of equations", "coordinate plane",
            "what is the value", "which expression is equivalent", "area of", "volume of",
            "right triangle", "mean of", "median of", "standard deviation"
        ]
        guard signals.contains(where: { text.contains($0) }) || hasNumericExpression(text) else {
            return false
        }
        return hasMathQuestionContext(text)
    }

    private static func hasMathQuestionContext(_ text: String) -> Bool {
        let readingSignals = [
            "which choice most logically completes the text",
            "which choice best describes",
            "according to the text",
            "the text suggests",
            "as used in the text",
            "the author"
        ]
        if readingSignals.contains(where: { text.contains($0) }) {
            return false
        }
        let mathSignals = [
            "what is the value",
            "which expression",
            "solve",
            "equation",
            "f(x)",
            "g(x)",
            "graph",
            "triangle",
            "circle",
            "integer",
            "linear",
            "quadratic",
            "slope",
            "percent",
            "probability",
            "coordinate plane"
        ]
        return mathSignals.contains { text.contains($0) } || hasNumericExpression(text)
    }

    private static func isNotesSynthesis(_ text: String) -> Bool {
        let signals = [
            "student has taken the following notes",
            "while researching a topic",
            "the student wants to",
            "which choice most effectively uses relevant information from the notes",
            "accomplish this goal"
        ]
        return signals.contains { text.contains($0) }
    }

    private static func isVocabulary(_ text: String) -> Bool {
        let signals = [
            "as used in the text",
            "most nearly means",
            "which choice best states the meaning",
            "meaning of the word",
            "meaning of the phrase"
        ]
        return signals.contains { text.contains($0) }
    }

    private static func isGrammar(_ text: String) -> Bool {
        let signals = [
            "standard english",
            "conventions of standard english",
            "punctuation",
            "grammar",
            "sentence boundaries",
            "logically completes the text",
            "transition",
            "transitions"
        ]
        return signals.contains { text.contains($0) }
    }

    private static func isWriting(_ text: String) -> Bool {
        let signals = [
            "which choice most effectively",
            "which choice best combines",
            "which choice completes the text",
            "to make the paragraph most logical",
            "the writer wants to"
        ]
        return signals.contains { text.contains($0) }
    }

    private static func isReading(_ text: String) -> Bool {
        let signals = [
            "according to the text",
            "the text suggests",
            "which choice best describes",
            "main idea",
            "claim",
            "evidence",
            "the author",
            "the passage"
        ]
        return signals.contains { text.contains($0) }
    }

    private static func hasNumericExpression(_ text: String) -> Bool {
        let operators = Set("+-*/=")
        var sawLeftNumber = false
        var pendingOperator = false
        for character in text {
            if character.isNumber {
                if pendingOperator {
                    return true
                }
                sawLeftNumber = true
                continue
            }
            if character.isWhitespace {
                continue
            }
            if operators.contains(character), sawLeftNumber {
                pendingOperator = true
                continue
            }
            pendingOperator = false
            sawLeftNumber = false
        }
        return false
    }
}
