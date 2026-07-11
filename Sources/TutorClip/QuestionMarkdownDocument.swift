import Foundation

struct QuestionMarkdownDocument: Equatable {
    var blocks: [QuestionMarkdownBlock]

    init(markdown: String) {
        blocks = QuestionMarkdownParser.parse(markdown)
    }

    var containsTable: Bool { blocks.contains { $0.table != nil } }
}

struct QuestionMarkdownBlock: Identifiable, Equatable {
    enum Kind: Equatable {
        case text
        case table(QuestionMarkdownTable)
    }

    let id: Int
    let markdown: String
    let kind: Kind

    var table: QuestionMarkdownTable? {
        guard case .table(let table) = kind else { return nil }
        return table
    }
}

struct QuestionMarkdownTable: Equatable {
    let header: [String]
    let rows: [[String]]
    let markdown: String

    var columnCount: Int { header.count }

    func context(for selection: TableInteractionSelection) -> String {
        let indexes = selection.cells.map(\.row)
        let relevantRows: [[String]]
        switch selection.scope {
        case .cell, .row, .supportsAnswer:
            relevantRows = unique(indexes).compactMap { row in row == 0 ? header : rows[safe: row - 1] }
        case .compareRows:
            relevantRows = unique(indexes).compactMap { row in row == 0 ? header : rows[safe: row - 1] }
        case .compareColumns:
            let columns = unique(selection.cells.map(\.column))
            relevantRows = [header] + rows
            return relevantRows.map { row in
                columns.compactMap { row[safe: $0] }.joined(separator: "\t")
            }.joined(separator: "\n")
        }
        return ([header] + relevantRows.filter { $0 != header })
            .map { $0.joined(separator: "\t") }
            .joined(separator: "\n")
    }

    private func unique(_ values: [Int]) -> [Int] {
        var seen = Set<Int>()
        return values.filter { seen.insert($0).inserted }
    }
}

struct TableCellReference: Hashable {
    let row: Int
    let column: Int
    let text: String
}

struct TableInteractionSelection {
    enum Scope {
        case cell
        case row
        case compareRows
        case compareColumns
        case supportsAnswer
    }

    let scope: Scope
    let cells: [TableCellReference]
    let context: String
}

enum QuestionMarkdownParser {
    static func parse(_ markdown: String) -> [QuestionMarkdownBlock] {
        let lines = markdown.components(separatedBy: .newlines)
        var blocks: [QuestionMarkdownBlock] = []
        var textLines: [String] = []
        var index = 0
        var inFence = false

        func appendText() {
            let text = trimBlankEdges(textLines).joined(separator: "\n")
            guard !text.isEmpty else { textLines.removeAll(); return }
            blocks.append(QuestionMarkdownBlock(id: blocks.count, markdown: text, kind: .text))
            textLines.removeAll()
        }

        while index < lines.count {
            let line = lines[index]
            if line.trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                inFence.toggle()
            }
            if !inFence,
               index + 1 < lines.count,
               let header = parseRow(line),
               isSeparatorRow(lines[index + 1], columns: header.count) {
                appendText()
                var tableLines = [line, lines[index + 1]]
                var rows: [[String]] = []
                index += 2
                while index < lines.count, let row = parseRow(lines[index]), row.count == header.count {
                    tableLines.append(lines[index])
                    rows.append(row)
                    index += 1
                }
                let source = tableLines.joined(separator: "\n")
                let table = QuestionMarkdownTable(header: header, rows: rows, markdown: source)
                blocks.append(QuestionMarkdownBlock(id: blocks.count, markdown: source, kind: .table(table)))
                continue
            }
            textLines.append(line)
            index += 1
        }
        appendText()
        return blocks
    }

    static func parseRow(_ line: String) -> [String]? {
        guard line.contains("|") else { return nil }
        var cells: [String] = []
        var current = ""
        var escaped = false
        for character in line {
            if escaped {
                current.append(character)
                escaped = false
            } else if character == "\\" {
                escaped = true
            } else if character == "|" {
                cells.append(current.trimmingCharacters(in: .whitespaces))
                current = ""
            } else {
                current.append(character)
            }
        }
        if escaped { current.append("\\") }
        cells.append(current.trimmingCharacters(in: .whitespaces))
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("|"), cells.first?.isEmpty == true { cells.removeFirst() }
        if trimmed.hasSuffix("|"), cells.last?.isEmpty == true { cells.removeLast() }
        return cells.isEmpty ? nil : cells
    }

    private static func isSeparatorRow(_ line: String, columns: Int) -> Bool {
        guard let cells = parseRow(line), cells.count == columns else { return false }
        return cells.allSatisfy { cell in
            let core = cell.trimmingCharacters(in: CharacterSet.whitespaces.union(CharacterSet(charactersIn: ":")))
            return core.count >= 3 && core.allSatisfy { $0 == "-" }
        }
    }

    private static func trimBlankEdges(_ lines: [String]) -> [String] {
        guard let first = lines.firstIndex(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }),
              let last = lines.lastIndex(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }) else { return [] }
        return Array(lines[first...last])
    }
}

enum GFMTableDetector {
    static func containsTable(in markdown: String) -> Bool {
        QuestionMarkdownDocument(markdown: markdown).containsTable
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
