import Foundation

enum TutorQuestionParsing {
    static func answerChoices(from text: String) -> [String] {
        var choices: [String] = []
        for paragraph in text.components(separatedBy: .newlines) {
            guard let letter = answerChoiceLabel(atStartOf: paragraph),
                  !choices.contains(letter) else { continue }
            choices.append(letter)
        }
        // SAT questions are not single-choice protocols. Requiring multiple labels
        // prevents prose such as “A historian…” from creating a lone A button.
        return choices.count >= 2 ? choices.sorted() : []
    }

    static func answerChoiceLabel(atStartOf rawLine: String) -> String? {
        var line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
        for bullet in ["- ", "* ", "• "] where line.hasPrefix(bullet) {
            line.removeFirst(bullet.count)
            line = line.trimmingCharacters(in: .whitespaces)
            break
        }
        if line.hasPrefix("**") {
            line.removeFirst(2)
        }
        if line.hasPrefix("(") {
            line.removeFirst()
            guard line.count >= 2 else { return nil }
            let letter = String(line.removeFirst()).uppercased()
            guard ["A", "B", "C", "D"].contains(letter), line.first == ")" else { return nil }
            return letter
        }
        guard let first = line.first else { return nil }
        let letter = String(first).uppercased()
        guard ["A", "B", "C", "D"].contains(letter) else { return nil }
        if line.count == 1 { return letter }
        let delimiter = line.dropFirst().first
        return delimiter == ")" || delimiter == "." || delimiter == ":" || delimiter?.isWhitespace == true
            ? letter
            : nil
    }

    static func category(fromAI raw: String) -> SessionCategory {
        let label = raw
            .lowercased()
            .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters))
        switch label {
        case "reading": return .reading
        case "writing": return .writing
        case "notessynthesis", "notes_synthesis", "notes-synthesis", "notes": return .notesSynthesis
        case "vocabulary": return .vocabulary
        case "grammar": return .grammar
        case "math": return .math
        default: return .unknown
        }
    }

    static func userMessageContent(action: TutorAction, selectedText: String, question: String?, language: AppLanguage) -> String {
        if let question {
            return "\(action.title(language: language))：\(singleLineSummary(question))"
        }
        guard action.usesSelectedTextSummary, !selectedText.isEmpty else {
            return action.title(language: language)
        }
        return "\(action.title(language: language))：\(singleLineSummary(selectedText))"
    }

    private static func singleLineSummary(_ text: String) -> String {
        let singleLine = text.split(whereSeparator: \.isNewline).joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let maxLength = 64
        guard singleLine.count > maxLength else { return singleLine }
        return "\(singleLine.prefix(maxLength))..."
    }
}
