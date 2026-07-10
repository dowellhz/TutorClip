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

    static func empty() -> OCRDocument {
        OCRDocument(id: UUID(), fullText: "", editedText: "", detectedLanguage: nil, createdAt: Date(), blocks: [], lines: [], tokens: [])
    }
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
