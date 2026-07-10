import AppKit
import Foundation

enum DemoSessionFactory {
    static func make() -> TutorSession {
        let text = """
        The following passage is adapted from a discussion of urban gardens.

        Researchers have found that small community gardens can improve neighborhood cohesion. Residents who work together to maintain shared plots often report stronger social ties and a greater sense of responsibility for public spaces.

        Which choice best states the main idea of the text?
        A. Community gardens mainly benefit professional researchers.
        B. Shared gardens can strengthen connections among local residents.
        C. Public spaces are difficult for residents to maintain.
        D. Urban neighborhoods rarely support shared projects.
        """
        let image = makeImage(text: text)
        let document = makeDocument(text: text)
        return TutorSession(
            id: UUID(),
            title: "Demo SAT Reading Question",
            createdAt: Date(),
            updatedAt: Date(),
            ocrDocument: document,
            messages: [],
            screenshotInMemory: image,
            category: .reading
        )
    }

    private static func makeDocument(text: String) -> OCRDocument {
        let linesText = text.components(separatedBy: .newlines).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        let lineHeight = 0.055
        let top = 0.9
        var tokens: [OCRToken] = []
        let lines = linesText.enumerated().map { index, line in
            let y = top - Double(index) * lineHeight
            let rect = CGRect(x: 0.06, y: max(0.05, y), width: min(0.88, 0.02 + Double(line.count) * 0.011), height: 0.04)
            let lineTokens = makeTokens(from: line, lineBox: rect)
            tokens.append(contentsOf: lineTokens)
            return OCRLine(id: UUID(), text: line, boundingBox: CodableRect(rect), confidence: 1, tokenIds: lineTokens.map(\.id))
        }
        let block = OCRBlock(
            id: UUID(),
            text: text,
            boundingBox: CodableRect(CGRect(x: 0, y: 0, width: 1, height: 1)),
            confidence: 1,
            lineIds: lines.map(\.id)
        )
        return OCRDocument(
            id: UUID(),
            fullText: text,
            editedText: text,
            detectedLanguage: OCRLanguage.english.rawValue,
            createdAt: Date(),
            blocks: [block],
            lines: lines,
            tokens: tokens
        )
    }

    private static func makeTokens(from line: String, lineBox: CGRect) -> [OCRToken] {
        let words = line.split(whereSeparator: \.isWhitespace).map(String.init)
        guard !words.isEmpty else { return [] }
        let total = max(words.reduce(0) { $0 + $1.count }, 1)
        var x = lineBox.minX
        return words.map { word in
            let width = lineBox.width * CGFloat(word.count) / CGFloat(total)
            defer { x += width }
            return OCRToken(id: UUID(), text: word, boundingBox: CodableRect(CGRect(x: x, y: lineBox.minY, width: width, height: lineBox.height)), confidence: 1)
        }
    }

    private static func makeImage(text: String) -> NSImage {
        let size = CGSize(width: 900, height: 620)
        let image = NSImage(size: size)
        image.lockFocus()
        NSColor.textBackgroundColor.setFill()
        NSRect(origin: .zero, size: size).fill()
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 6
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 22),
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: paragraph
        ]
        text.draw(in: NSRect(x: 42, y: 34, width: 816, height: 550), withAttributes: attributes)
        image.unlockFocus()
        return image
    }
}
