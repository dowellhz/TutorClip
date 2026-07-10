import Foundation

enum LatexDisplayNormalizer {
    static func displayString(from text: String) -> String {
        var output = ""
        var index = text.startIndex
        while index < text.endIndex {
            let character = text[index]
            if character == "\\" {
                if skipEscapedLatexSlash(in: text, index: &index) {
                    continue
                }
                if appendLatexCommand(from: text, index: &index, output: &output) {
                    continue
                }
            }
            if character == "^" || character == "_" {
                if appendScript(from: text, marker: character, index: &index, output: &output) {
                    continue
                }
            }
            output.append(character)
            index = text.index(after: index)
        }
        return output
    }

    private static func skipEscapedLatexSlash(in text: String, index: inout String.Index) -> Bool {
        let next = text.index(after: index)
        guard next < text.endIndex, text[next] == "\\" else { return false }
        let commandStart = text.index(after: next)
        guard commandStart < text.endIndex, text[commandStart].isLetter else { return false }
        index = next
        return true
    }

    private static func appendLatexCommand(from text: String, index: inout String.Index, output: inout String) -> Bool {
        let slashIndex = index
        let commandStart = text.index(after: slashIndex)
        guard commandStart < text.endIndex else { return false }

        let delimiter = text[commandStart]
        if ["(", ")", "[", "]"].contains(delimiter) {
            index = text.index(after: commandStart)
            return true
        }

        guard delimiter.isLetter else { return false }
        var cursor = commandStart
        while cursor < text.endIndex, text[cursor].isLetter {
            cursor = text.index(after: cursor)
        }
        let command = String(text[commandStart..<cursor])

        switch command {
        case "frac":
            guard let numerator = parseBracedContent(in: text, from: cursor) else { return false }
            guard let denominator = parseBracedContent(in: text, from: numerator.endIndex) else { return false }
            output.append(fraction(numerator.content, denominator.content))
            index = denominator.endIndex
            return true
        case "sqrt":
            guard let radicand = parseBracedContent(in: text, from: cursor) else { return false }
            output.append(squareRoot(radicand.content))
            index = radicand.endIndex
            return true
        default:
            guard let replacement = commandReplacements[command] else { return false }
            output.append(replacement)
            index = cursor
            return true
        }
    }

    private static func appendScript(from text: String, marker: Character, index: inout String.Index, output: inout String) -> Bool {
        let start = text.index(after: index)
        guard start < text.endIndex else { return false }

        let rawContent: String
        let endIndex: String.Index
        if let braced = parseBracedContent(in: text, from: start) {
            rawContent = braced.content
            endIndex = braced.endIndex
        } else {
            rawContent = String(text[start])
            endIndex = text.index(after: start)
        }

        let rendered = marker == "^" ? superscript(rawContent) : subscriptText(rawContent)
        guard !rendered.isEmpty else { return false }
        output.append(rendered)
        index = endIndex
        return true
    }

    private static func parseBracedContent(in text: String, from start: String.Index) -> (content: String, endIndex: String.Index)? {
        guard start < text.endIndex, text[start] == "{" else { return nil }
        var depth = 1
        var cursor = text.index(after: start)
        let contentStart = cursor
        while cursor < text.endIndex {
            if text[cursor] == "{" {
                depth += 1
            } else if text[cursor] == "}" {
                depth -= 1
                if depth == 0 {
                    return (String(text[contentStart..<cursor]), text.index(after: cursor))
                }
            }
            cursor = text.index(after: cursor)
        }
        return nil
    }

    private static func fraction(_ numerator: String, _ denominator: String) -> String {
        let key = "\(numerator.trimmingCharacters(in: .whitespacesAndNewlines))/\(denominator.trimmingCharacters(in: .whitespacesAndNewlines))"
        if let singleCharacter = commonFractions[key] {
            return singleCharacter
        }
        return "\(fractionPart(numerator))⁄\(fractionPart(denominator))"
    }

    private static func fractionPart(_ text: String) -> String {
        let rendered = displayString(from: text.trimmingCharacters(in: .whitespacesAndNewlines))
        guard rendered.contains(where: { "+-=×÷· ".contains($0) }) else { return rendered }
        return "(\(rendered))"
    }

    private static func squareRoot(_ content: String) -> String {
        let rendered = displayString(from: content)
        return rendered.count == 1 ? "√\(rendered)" : "√(\(rendered))"
    }

    private static func superscript(_ text: String) -> String {
        text.compactMap { superscripts[$0] }.joined()
    }

    private static func subscriptText(_ text: String) -> String {
        text.compactMap { subscripts[$0] }.joined()
    }

    private static let commandReplacements: [String: String] = [
        "cdot": "·",
        "times": "×",
        "div": "÷",
        "le": "≤",
        "leq": "≤",
        "ge": "≥",
        "geq": "≥",
        "neq": "≠",
        "ne": "≠",
        "pm": "±",
        "pi": "π",
        "theta": "θ",
        "alpha": "α",
        "beta": "β"
    ]

    private static let commonFractions: [String: String] = [
        "1/2": "½",
        "1/3": "⅓",
        "2/3": "⅔",
        "1/4": "¼",
        "3/4": "¾",
        "1/5": "⅕",
        "2/5": "⅖",
        "3/5": "⅗",
        "4/5": "⅘",
        "1/6": "⅙",
        "5/6": "⅚",
        "1/7": "⅐",
        "1/8": "⅛",
        "3/8": "⅜",
        "5/8": "⅝",
        "7/8": "⅞",
        "1/9": "⅑",
        "1/10": "⅒"
    ]

    private static let superscripts: [Character: String] = [
        "0": "⁰",
        "1": "¹",
        "2": "²",
        "3": "³",
        "4": "⁴",
        "5": "⁵",
        "6": "⁶",
        "7": "⁷",
        "8": "⁸",
        "9": "⁹",
        "+": "⁺",
        "-": "⁻",
        "=": "⁼",
        "(": "⁽",
        ")": "⁾",
        "n": "ⁿ"
    ]

    private static let subscripts: [Character: String] = [
        "0": "₀",
        "1": "₁",
        "2": "₂",
        "3": "₃",
        "4": "₄",
        "5": "₅",
        "6": "₆",
        "7": "₇",
        "8": "₈",
        "9": "₉",
        "+": "₊",
        "-": "₋",
        "=": "₌",
        "(": "₍",
        ")": "₎"
    ]
}
