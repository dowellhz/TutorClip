import CoreGraphics
import Foundation

struct OCRDocument: Codable, Equatable {
    var id: UUID
    var fullText: String
    var editedText: String
    var detectedLanguage: String?
    var createdAt: Date
    var blocks: [OCRBlock]
    var lines: [OCRLine]
    var tokens: [OCRToken]
    var tables: [OCRTable]? = nil
    var documentTitle: OCRDocumentTitle? = nil
    var paragraphs: [OCRParagraph]? = nil
    var alternateText: String? = nil
    var alternateTokens: [OCRToken]? = nil
    var recognitionCandidates: [String]? = nil
    var alternateRecognitionCandidates: [String]? = nil

    static func empty() -> OCRDocument {
        OCRDocument(id: UUID(), fullText: "", editedText: "", detectedLanguage: nil, createdAt: Date(), blocks: [], lines: [], tokens: [], tables: [])
    }

    var structuredTables: [OCRTable] { tables ?? [] }
}

struct OCRParagraph: Codable, Equatable {
    var text: String
    var boundingBox: CodableRect
}

struct OCRDocumentTitle: Codable, Equatable {
    var text: String
    var boundingBox: CodableRect
}

struct OCRTable: Codable, Equatable, Identifiable {
    var id: UUID
    var boundingBox: CodableRect
    var rows: [[OCRTableCell]]
}

struct OCRTableCell: Codable, Equatable, Identifiable {
    var id: UUID
    var text: String
    var rowStart: Int
    var rowEnd: Int
    var columnStart: Int
    var columnEnd: Int
    var boundingBox: CodableRect
}

struct OCRBlock: Codable, Equatable, Identifiable {
    var id: UUID
    var text: String
    var boundingBox: CodableRect
    var confidence: Float
    var lineIds: [UUID]
}

struct OCRLine: Codable, Equatable, Identifiable {
    var id: UUID
    var text: String
    var boundingBox: CodableRect
    var confidence: Float
    var tokenIds: [UUID]
}

struct OCRToken: Codable, Equatable, Identifiable {
    var id: UUID
    var text: String
    var boundingBox: CodableRect
    var confidence: Float
    var isLikelyUnderlined: Bool?
}

struct CodableRect: Codable, Equatable {
    var x: Double
    var y: Double
    var width: Double
    var height: Double

    init(_ rect: CGRect) {
        x = rect.origin.x
        y = rect.origin.y
        width = rect.size.width
        height = rect.size.height
    }

    var cgRect: CGRect { CGRect(x: x, y: y, width: width, height: height) }
}
