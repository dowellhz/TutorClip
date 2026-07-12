import CoreGraphics
import Foundation
import Vision

struct OCRLayoutService {
    func makeDocument(observation: DocumentObservation, language: OCRLanguage) -> OCRDocument {
        var tokens: [OCRToken] = []
        let lines = observation.document.text.lines.map { item in
            let box = item.boundingRegion.normalizedPath.boundingBox
            let lineTokens = makeTokens(from: item)
            tokens.append(contentsOf: lineTokens)
            return OCRLine(id: item.uuid, text: item.transcript, boundingBox: CodableRect(box), confidence: item.confidence, tokenIds: lineTokens.map(\.id))
        }
        let fullText = observation.document.text.transcript
        let block = OCRBlock(id: UUID(), text: fullText, boundingBox: CodableRect(observation.document.boundingRegion.normalizedPath.boundingBox), confidence: lines.map(\.confidence).average, lineIds: lines.map(\.id))
        let tables = observation.document.tables.map { table in
            OCRTable(id: UUID(), boundingBox: CodableRect(table.boundingRegion.normalizedPath.boundingBox), rows: table.rows.map { row in
                row.map { cell in
                    OCRTableCell(id: UUID(), text: cell.content.text.transcript, rowStart: cell.rowRange.lowerBound, rowEnd: cell.rowRange.upperBound, columnStart: cell.columnRange.lowerBound, columnEnd: cell.columnRange.upperBound, boundingBox: CodableRect(cell.content.boundingRegion.normalizedPath.boundingBox))
                }
            })
        }
        let title = observation.document.title.map {
            OCRDocumentTitle(text: $0.transcript, boundingBox: CodableRect($0.boundingRegion.normalizedPath.boundingBox))
        }
        var paragraphs = observation.document.paragraphs.map {
            OCRParagraph(text: $0.transcript, boundingBox: CodableRect($0.boundingRegion.normalizedPath.boundingBox))
        }
        for segment in transcriptSegments(from: observation.document.text) where !paragraphs.contains(where: { $0.text == segment.text }) {
            paragraphs.append(segment)
        }
        var document = OCRDocument(id: UUID(), fullText: fullText, editedText: fullText, detectedLanguage: language.rawValue, createdAt: Date(), blocks: fullText.isEmpty ? [] : [block], lines: lines, tokens: tokens, tables: tables, documentTitle: title, paragraphs: paragraphs)
        document.recognitionCandidates = observation.document.text.lines.map { line in
            line.topCandidates(5).map(\.string).joined(separator: " || ")
        }
        return document
    }

    private func transcriptSegments(from text: DocumentObservation.Container.Text) -> [OCRParagraph] {
        let transcript = text.transcript
        var searchStart = transcript.startIndex
        return transcript.split(whereSeparator: \.isNewline).compactMap { part in
            let value = String(part).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty,
                  let range = transcript.range(of: value, range: searchStart..<transcript.endIndex),
                  let region = text.boundingRegion(for: range) else { return nil }
            searchStart = range.upperBound
            return OCRParagraph(text: value, boundingBox: CodableRect(region.normalizedPath.boundingBox))
        }
    }

    private func makeTokens(from observation: RecognizedTextObservation) -> [OCRToken] {
        guard let recognized = observation.topCandidates(1).first else { return [] }
        let text = recognized.string
        return text.indices.compactMap { start -> OCRToken? in
            let end = text.index(after: start)
            let character = String(text[start..<end])
            guard !character.allSatisfy(\.isWhitespace),
                  let rectangle = recognized.boundingBox(for: start..<end) else { return nil }
            return OCRToken(
                id: UUID(),
                text: character,
                boundingBox: CodableRect(rectangle.boundingBox.cgRect),
                confidence: recognized.confidence,
                isLikelyUnderlined: nil
            )
        }
    }
}

private extension Array where Element == Float {
    var average: Float {
        guard !isEmpty else { return 0 }
        return reduce(0, +) / Float(count)
    }
}
