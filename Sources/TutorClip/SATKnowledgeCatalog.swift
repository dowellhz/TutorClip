import Foundation

struct SATQuestionTypeDefinition: Identifiable, Equatable {
    let id: String
    let domain: String
    let skill: String
    let titleZH: String
    let titleEN: String
}

struct SATKnowledgePointDefinition: Identifiable, Equatable {
    let id: String
    let questionTypeID: String
    let titleZH: String
    let titleEN: String
}

/// Stable, versioned IDs for the College Board Reading and Writing skill tree.
/// The question-type level is official; knowledge points are TutorClip's teachable mastery units.
enum SATKnowledgeCatalog {
    static let version = 2

    static let questionTypes: [SATQuestionTypeDefinition] = [
        type("RW.II.CID", "Information and Ideas", "Central Ideas and Details", "主旨与细节", "Central Ideas and Details"),
        type("RW.II.INF", "Information and Ideas", "Inferences", "推断", "Inferences"),
        type("RW.II.COE.TEXT", "Information and Ideas", "Command of Evidence", "文本证据", "Textual Evidence"),
        type("RW.II.COE.QUANT", "Information and Ideas", "Command of Evidence", "图表证据", "Quantitative Evidence"),
        type("RW.CS.WIC", "Craft and Structure", "Words in Context", "语境词义", "Words in Context"),
        type("RW.CS.TSP", "Craft and Structure", "Text Structure and Purpose", "结构与目的", "Text Structure and Purpose"),
        type("RW.CS.CTC", "Craft and Structure", "Cross-Text Connections", "双文本联系", "Cross-Text Connections"),
        type("RW.EI.RS", "Expression of Ideas", "Rhetorical Synthesis", "修辞综合", "Rhetorical Synthesis"),
        type("RW.EI.TR", "Expression of Ideas", "Transitions", "过渡", "Transitions"),
        type("RW.SEC.BND", "Standard English Conventions", "Boundaries", "句子边界", "Boundaries"),
        type("RW.SEC.FSS", "Standard English Conventions", "Form, Structure, and Sense", "形式、结构与语义", "Form, Structure, and Sense")
    ]

    static let knowledgePoints: [SATKnowledgePointDefinition] = [
        points("RW.II.CID", [("CORE_SUBJECT","识别核心对象","Identify the central subject"),("MAIN_IDEA","概括核心观点","Determine the main idea"),("LITERARY_SUMMARY","概括文学情节或人物处境","Summarize literary situation"),("EXPLICIT_DETAIL","定位明确细节","Locate explicit details"),("SCOPE_CONTROL","控制答案范围","Match answer scope"),("OBJECT_CONSISTENCY","避免偷换对象","Maintain referent consistency")]),
        points("RW.II.INF", [("FACT_VS_INFERENCE","区分事实与推断","Distinguish fact from inference"),("MINIMUM_INFERENCE","最小幅度推断","Make the minimum supported inference"),("CHARACTER_ATTITUDE","推断人物态度或动机","Infer character attitude or motive"),("AUTHOR_POSITION","推断作者立场","Infer author position"),("RESEARCH_IMPLICATION","推断研究含义","Infer research implications"),("MODAL_STRENGTH","控制可能与必然的强度","Control modal strength"),("OVERREACH","识别过度推断","Reject overreach")]),
        points("RW.II.COE.TEXT", [("TARGET_CLAIM","明确待证明主张","Identify the target claim"),("RELEVANCE","判断证据相关性","Evaluate relevance"),("DIRECT_SUPPORT","选择直接支持","Select direct support"),("WEAKEN","选择削弱证据","Select weakening evidence"),("EVIDENCE_STRENGTH","比较证据力度","Compare evidence strength")]),
        points("RW.II.COE.QUANT", [("AXES_UNITS","识别轴、单位与组别","Read axes, units, and groups"),("DATA_POINT","准确读取数据点","Read data points"),("COMPARISON","比较数据","Compare values"),("TREND","识别趋势","Identify trends"),("TEXT_GRAPH_LINK","连接文字与图表","Connect text and graph"),("SUPPORT_WEAKEN","用数据支持或削弱","Use data to support or weaken"),("CORRELATION_CAUSATION","区分相关与因果","Distinguish correlation and causation")]),
        points("RW.CS.WIC", [("LOCAL_CONTEXT","使用句内语境","Use local context"),("GLOBAL_CONTEXT","使用上下文逻辑","Use surrounding logic"),("LOGIC_DIRECTION","识别转折或因果方向","Identify logical direction"),("PRECISION","区分近义词精度","Choose semantic precision"),("CONNOTATION","判断感情色彩","Evaluate connotation"),("SECONDARY_MEANING","识别熟词僻义","Recognize secondary meanings"),("COLLOCATION","判断自然搭配","Evaluate collocation"),("INTENSITY","选择适当强度","Choose appropriate intensity")]),
        points("RW.CS.TSP", [("CONTENT_VS_FUNCTION","区分内容与功能","Distinguish content from function"),("CLAIM_ROLE","识别提出观点","Identify a claim"),("EXAMPLE_ROLE","识别例证作用","Identify an example"),("EVIDENCE_ROLE","识别证据作用","Identify evidence"),("METHOD_RESULT","区分研究方法与结果","Distinguish method from result"),("COUNTERPOINT","识别反例、限制或反驳","Identify counterpoint or limitation"),("LOCAL_TO_GLOBAL","联系局部与全文","Connect local role to whole text"),("MAIN_PURPOSE","判断全文目的","Determine main purpose"),("TEXT_STRUCTURE","判断论证结构","Determine text structure")]),
        points("RW.CS.CTC", [("SEPARATE_POSITIONS","分别概括两文立场","Summarize each position"),("AGREEMENT","识别共同立场","Identify agreement"),("DISAGREEMENT","识别分歧","Identify disagreement"),("RESPONSE","预测作者回应","Predict an author's response"),("NEW_EVIDENCE","判断新证据的影响","Evaluate new evidence"),("PARTIAL_AGREEMENT","区分部分与完全同意","Distinguish partial agreement")]),
        points("RW.EI.RS", [("RHETORICAL_GOAL","识别写作目标","Identify the rhetorical goal"),("RELEVANT_NOTES","筛选相关笔记","Select relevant notes"),("AUDIENCE","适配目标读者","Adapt to audience"),("COMPARE","突出相同或不同","Compare or contrast"),("EVIDENCE_USE","用例子或数据支持","Use examples or data"),("SEQUENCE_CAUSE","突出顺序或因果","Emphasize sequence or cause"),("FAITHFUL_SYNTHESIS","忠实简洁地综合","Synthesize faithfully and concisely")]),
        points("RW.EI.TR", [("ADDITION","补充关系","Addition"),("SIMILARITY","相似关系","Similarity"),("CONTRAST","对比关系","Contrast"),("CONCESSION","让步关系","Concession"),("CAUSE_EFFECT","因果关系","Cause and effect"),("EXAMPLE","例证关系","Example"),("SPECIFICATION","具体化","Specification"),("RESTATEMENT","换言解释","Restatement"),("TIME_SEQUENCE","时间与顺序","Time and sequence"),("ALTERNATIVE","替代关系","Alternative"),("EMPHASIS","强调关系","Emphasis"),("SUMMARY","总结关系","Summary")]),
        points("RW.SEC.BND", [("INDEPENDENT_CLAUSE","识别独立句","Identify independent clauses"),("DEPENDENT_FRAGMENT","识别从属结构与残句","Identify dependent clauses and fragments"),("COMMA_SPLICE","识别逗号拼接","Avoid comma splices"),("PERIOD_SEMICOLON","使用句号或分号","Use periods and semicolons"),("COMMA_FANBOYS","使用逗号加并列连词","Use comma plus coordinating conjunction"),("CONJUNCTIVE_ADVERB","连接副词标点","Punctuate conjunctive adverbs"),("COLON","正确使用冒号","Use colons"),("DASH","正确使用破折号","Use dashes"),("NONESSENTIAL","标记非必要成分","Set off nonessential elements"),("APPOSITIVE","标记同位语","Punctuate appositives"),("LIST","处理列举","Punctuate lists")]),
        points("RW.SEC.FSS", [("SUBJECT_VERB","主谓一致","Subject-verb agreement"),("TENSE_TIMELINE","时态与时间线","Verb tense and timeline"),("FINITE_NONFINITE","限定与非限定动词","Finite and nonfinite verbs"),("VOICE","主动与被动","Active and passive voice"),("PRONOUN_AGREEMENT","代词一致","Pronoun agreement"),("PRONOUN_CASE","代词格","Pronoun case"),("PRONOUN_CLARITY","代词指代清晰","Pronoun clarity"),("MODIFIER_PLACEMENT","修饰语位置","Modifier placement"),("DANGLING_MODIFIER","悬垂修饰语","Dangling modifiers"),("ADJECTIVE_ADVERB","形容词与副词","Adjectives and adverbs"),("PARALLELISM","平行结构","Parallelism"),("POSSESSIVE","所有格","Possessives"),("NOUN_NUMBER","名词单复数","Noun number"),("COMPARISON","比较结构","Comparisons"),("IDIOM_PREPOSITION","固定搭配与介词","Idioms and prepositions")])
    ].flatMap { $0 }

    static func questionType(id: String) -> SATQuestionTypeDefinition? { questionTypes.first { $0.id == id } }
    static func knowledgePoint(id: String) -> SATKnowledgePointDefinition? { knowledgePoints.first { $0.id == id } }
    static func validKnowledgePointIDs(_ ids: [String], questionTypeID: String? = nil) -> [String] {
        let allowed = Set(knowledgePoints.filter { questionTypeID == nil || $0.questionTypeID == questionTypeID }.map(\.id))
        var seen: Set<String> = []
        return ids
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() }
            .filter { allowed.contains($0) && seen.insert($0).inserted }
    }

    private static func type(_ id: String, _ domain: String, _ skill: String, _ zh: String, _ en: String) -> SATQuestionTypeDefinition {
        SATQuestionTypeDefinition(id: id, domain: domain, skill: skill, titleZH: zh, titleEN: en)
    }
    private static func points(_ typeID: String, _ values: [(String, String, String)]) -> [SATKnowledgePointDefinition] {
        values.map { SATKnowledgePointDefinition(id: "\(typeID).\($0.0)", questionTypeID: typeID, titleZH: $0.1, titleEN: $0.2) }
    }
}
