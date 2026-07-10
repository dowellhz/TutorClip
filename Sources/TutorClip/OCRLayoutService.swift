import CoreGraphics
import Foundation
import Vision

struct OCRLayoutService {
    func makeDocument(observations: [VNRecognizedTextObservation], language: OCRLanguage) -> OCRDocument {
        var tokens: [OCRToken] = []
        let lines: [OCRLine] = observations.compactMap { observation in
            guard let candidate = observation.topCandidates(1).first else { return nil }
            let lineTokens = makeTokens(from: candidate.string, lineBox: observation.boundingBox, confidence: candidate.confidence)
            tokens.append(contentsOf: lineTokens)
            return OCRLine(
                id: UUID(),
                text: candidate.string,
                boundingBox: CodableRect(observation.boundingBox),
                confidence: candidate.confidence,
                tokenIds: lineTokens.map(\.id)
            )
        }

        let rawLines = lines.map(\.text)
        let fullText = rawLines.joined(separator: "\n")
        let block = OCRBlock(
            id: UUID(),
            text: fullText,
            boundingBox: CodableRect(CGRect(x: 0, y: 0, width: 1, height: 1)),
            confidence: lines.map(\.confidence).average,
            lineIds: lines.map(\.id)
        )

        return OCRDocument(
            id: UUID(),
            fullText: fullText,
            editedText: fullText,
            detectedLanguage: language.rawValue,
            createdAt: Date(),
            blocks: fullText.isEmpty ? [] : [block],
            lines: lines,
            tokens: tokens
        )
    }

    private func makeTokens(from text: String, lineBox: CGRect, confidence: Float) -> [OCRToken] {
        let words = text.split(whereSeparator: \.isWhitespace).map(String.init)
        guard !words.isEmpty else { return [] }
        let totalCharacters = max(words.reduce(0) { $0 + $1.count }, 1)
        var offset: CGFloat = 0
        return words.map { word in
            let ratio = CGFloat(word.count) / CGFloat(totalCharacters)
            let width = lineBox.width * ratio
            let rect = CGRect(x: lineBox.minX + offset, y: lineBox.minY, width: width, height: lineBox.height)
            offset += width
            return OCRToken(id: UUID(), text: word, boundingBox: CodableRect(rect), confidence: confidence)
        }
    }
}

private extension Array where Element == Float {
    var average: Float {
        guard !isEmpty else { return 0 }
        return reduce(0, +) / Float(count)
    }
}
