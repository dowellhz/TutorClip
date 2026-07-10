import Foundation

enum TutorQuestionParsing {
    static func answerChoices(from text: String) -> [String] {
        var choices: [String] = []
        for paragraph in text.components(separatedBy: .newlines) {
            let trimmed = paragraph.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let first = trimmed.first else { continue }
            let letter = String(first).uppercased()
            guard ["A", "B", "C", "D"].contains(letter), !choices.contains(letter) else { continue }
            if trimmed.count == 1 {
                choices.append(letter)
                continue
            }
            let rest = trimmed.dropFirst()
            guard let delimiter = rest.first else { continue }
            if delimiter == ")" || delimiter == "." || delimiter == ":" || delimiter.isWhitespace {
                choices.append(letter)
            }
        }
        return choices.sorted()
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
