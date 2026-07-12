import Foundation

enum SATKnowledgeComplexity: String, Codable {
    case simple
    case ordinary
    case complex
}

struct SATKnowledgeRelationship: Codable, Equatable {
    enum Kind: String, Codable { case prerequisite, easilyConfused, composite }
    let fromID: String
    let toID: String
    let kind: Kind
}

enum SATKnowledgeGraph {
    static let relationships: [SATKnowledgeRelationship] = [
        .init(fromID: "RW.SEC.BND.INDEPENDENT_CLAUSE", toID: "RW.SEC.BND.COMMA_SPLICE", kind: .prerequisite),
        .init(fromID: "RW.SEC.BND.INDEPENDENT_CLAUSE", toID: "RW.SEC.BND.PERIOD_SEMICOLON", kind: .prerequisite),
        .init(fromID: "RW.EI.TR.CONTRAST", toID: "RW.EI.TR.CONCESSION", kind: .easilyConfused),
        .init(fromID: "RW.II.COE.QUANT.AXES_UNITS", toID: "RW.II.COE.QUANT.TEXT_GRAPH_LINK", kind: .prerequisite),
        .init(fromID: "RW.II.CID.EXPLICIT_DETAIL", toID: "RW.II.CID.MAIN_IDEA", kind: .prerequisite),
        .init(fromID: "RW.II.INF.FACT_VS_INFERENCE", toID: "RW.II.INF.MINIMUM_INFERENCE", kind: .prerequisite),
        .init(fromID: "RW.II.COE.TEXT.TARGET_CLAIM", toID: "RW.II.COE.TEXT.DIRECT_SUPPORT", kind: .prerequisite),
        .init(fromID: "RW.CS.TSP.CONTENT_VS_FUNCTION", toID: "RW.CS.TSP.MAIN_PURPOSE", kind: .prerequisite),
        .init(fromID: "RW.CS.CTC.SEPARATE_POSITIONS", toID: "RW.CS.CTC.RESPONSE", kind: .prerequisite),
        .init(fromID: "RW.EI.RS.RHETORICAL_GOAL", toID: "RW.EI.RS.RELEVANT_NOTES", kind: .prerequisite),
        .init(fromID: "RW.SEC.FSS.SUBJECT_VERB", toID: "RW.SEC.FSS.FINITE_NONFINITE", kind: .easilyConfused),
        .init(fromID: "RW.SEC.BND.COLON", toID: "RW.SEC.BND.DASH", kind: .easilyConfused)
    ]

    static func complexity(of id: String) -> SATKnowledgeComplexity {
        let simpleSuffixes = ["SUBJECT_VERB", "ADDITION", "DATA_POINT", "AXES_UNITS", "PERCENT"]
        if simpleSuffixes.contains(where: id.hasSuffix) { return .simple }
        if relationships.contains(where: { $0.toID == id && $0.kind == .composite }) { return .complex }
        return id.contains("QUAD") || id.contains("CROSS") || id.contains("SYNTHESIS") ? .complex : .ordinary
    }

    static func prerequisites(of id: String) -> [String] {
        relationships.filter { $0.toID == id && $0.kind == .prerequisite }.map(\.fromID)
    }
}
