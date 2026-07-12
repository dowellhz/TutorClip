import Foundation

struct PromptBuilder {
    func systemPrompt(language: AppLanguage) -> String {
        switch language {
        case .chinese:
            return chineseSystemPrompt
        case .english:
            return englishSystemPrompt
        }
    }

    func guidedLearningSystemPrompt(language: AppLanguage) -> String {
        language.text(
            """
            你是一名采用苏格拉底式教学的 SAT 老师。当前处于引导学习流程，而不是整题讲解。
            严禁公布、暗示或排除原题的正确选项，也不要输出原题答案字母。只完成用户指定的当前一步。
            可以解释必要的英文、题意、知识点或方法，但必须保留让学生独立作答的机会。
            如果任务要求协议块，必须严格输出；协议块之外保持简洁。OCR 不完整时明确说明，不得补造内容。
            """,
            """
            You are a Socratic SAT tutor in a guided-learning flow, not a full-solution mode.
            Never reveal, imply, or eliminate toward the original question's correct choice, and never output its answer letter. Complete only the requested step.
            Explain necessary language, task meaning, concepts, or methods while preserving the student's chance to answer independently.
            Follow requested protocol blocks exactly. State OCR uncertainty instead of inventing content.
            """
        )
    }

    private var chineseSystemPrompt: String {
        """
        你是一名经验丰富的 SAT 老师，目标是让学生看懂题目、会判断选项，而不是堆长篇讲义。

        默认用中文回答，必要时保留关键英文原文。回答要紧凑：不要连续空行，不要大段铺开，不要把多个编号挤在同一段里。
        使用标准 Markdown：可以使用标题、编号列表、项目符号、短段落和适度加粗；不要使用表格、代码块或装饰性分隔线。
        Markdown 标记必须有实际内容，例如写成“### 1. 正确答案”，不要输出单独的 ###、---、**、__。

        如果是选择题，必须先给结论：
        1. 正确答案：选项字母 + 一句话理由
        2. 原文结合翻译：只选关键句或关键语义块。每个语义块必须这样写：
        原文：英文关键片段
        翻译：对应中文意思
        原文和翻译之间不要空行，然后紧跟解释它如何支持答案。
        3. 解题关键：题干问什么，原文哪里支持。
        4. 为什么正确：说明正确选项如何对应原文逻辑。
        5. 为什么其他选项不对：逐项排除。每个选项必须独立成段，格式为“选项 A：错误。陷阱：... 理由：...”；不要把多个选项写在同一段里。

        如果是 SAT Reading/Writing，优先讲题目逻辑、同义转述、句间关系、词汇或语法点；基础词不要解释。
        TutorClip 不支持 SAT Math；如果上下文是数学题，只说明不支持，不得解题。
        如果用户只是追问某一点，只回答用户问题，不要自动翻译、总结或展开整题。
        如果 OCR 文本明显缺失、混乱或无法判断，请直接说明不确定之处，不要编造题目内容。
        STRUCTURED_TABLE_n 块是 Apple Vision 按单元格输出的制表符分隔表格，行列关系优先于普通 OCR 行。若表格块缺失、为空或数据与题干冲突，必须说明无法可靠读取表格，禁止猜测数值。
        """
    }

    private var englishSystemPrompt: String {
        """
        You are an experienced SAT Reading and Writing tutor. Help the student understand reading, writing, vocabulary, and grammar questions.

        Answer in English by default. Keep explanations concise, use standard Markdown, and avoid decorative dividers, code blocks, and tables. Markdown markers must always have real content.

        For multiple-choice questions, start with the conclusion:
        1. Correct answer: choice letter + one-sentence reason.
        2. Text evidence: quote only the key phrase or sentence and explain how it supports the answer.
        3. What the question asks: identify the task and where the support appears.
        4. Why the correct choice is right: connect the choice to the source text.
        5. Why the other choices are wrong: eliminate each choice in its own paragraph using "Choice A: Wrong. Trap: ... Reason: ..."; do not combine multiple choices into one paragraph.

        Prioritize question logic, paraphrase, sentence relationships, vocabulary, and grammar that affect the answer. TutorClip does not support SAT Math; if the context is mathematical, state that it is unsupported and do not solve it. If OCR is incomplete or ambiguous, say what is uncertain and do not invent missing content.
        STRUCTURED_TABLE_n blocks are tab-separated cell data produced by Apple Vision. Treat their row-column structure as authoritative over plain OCR lines. If a table block is missing, empty, or conflicts with the prompt, state that the table cannot be read reliably and never guess values.
        """
    }

    func userPrompt(action: TutorAction, document: OCRDocument, selectedText: String?, customQuestion: String?, category: SessionCategory, language: AppLanguage) -> String {
        var parts: [String] = []
        let ocrText = document.editedText
        let selected = selectedText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let selectionOnly = action.usesOnlySelectedText && !selected.isEmpty

        if selectionOnly {
            parts.append("\(language.text("用户选中文本", "Selected text"))：\n\(selected)")
        } else {
            parts.append("\(language.text("OCR 全文", "Full OCR text"))：\n\(ocrText.isEmpty ? language.text("(OCR 为空)", "(OCR is empty)") : ocrText)")
            parts.append("\(language.text("识别题型", "Detected question type"))：\(category.displayName(language: language))")
            let structure = formattingStructureSummary(for: document)
            if !structure.isEmpty {
                parts.append("\(language.text("OCR 结构摘要", "OCR layout summary"))：\n\(structure)")
            }
            if !selected.isEmpty {
                parts.append("\(language.text("用户选中文本", "Selected text"))：\n\(selected)")
            }
            let underlined = document.tokens.filter { $0.isLikelyUnderlined == true }.map(\.text)
            if !underlined.isEmpty {
                parts.append("\(language.text("本地下划线检测（可能有误，请结合截图语义谨慎处理）", "Locally detected underlined text (may be imperfect; treat cautiously)"))：\n\(underlined.joined(separator: ", "))")
            }
        }
        parts.append("\(language.text("任务", "Task"))：\(instruction(for: action, hasSelection: !selected.isEmpty, category: category, language: language))")
        if let customQuestion, !customQuestion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            parts.append("\(language.text("用户问题", "User question"))：\n\(customQuestion)")
        }
        if !action.suppressesQuestionGuidance {
            parts.append(categoryGuidance(for: category, language: language))
        }
        return parts.joined(separator: "\n\n")
    }

    func formatOCRPrompt(document: OCRDocument) -> [DeepSeekMessage] {
        let structure = formattingStructureSummary(for: document, includeTokenLayout: true)
        return [
            DeepSeekMessage(
                role: "system",
                content: """
                你是 SAT OCR Markdown 排版整理器。你的任务是把 OCR 文本整理成可直接用 Markdown 渲染的清晰文本，并提取选择题正确答案和题型。
                通常只允许调整空格、换行、空白行、段落和选项排列。当 OCR 结构摘要包含 STRUCTURED_TABLE_n 时有两个明确例外：(1) 必须用标准 GFM Markdown 表格恢复这些单元格，可以增加表格语法所需的 |、- 和对齐符号；(2) OCR 可能把同一个表格标题的已有残片错排到表格前后，必须移动这些已有残片、按语义顺序合并，并把完整标题放到表格正上方。除此之外不得增加、删除、改写、移动或猜测任何内容。
                对题目正文严禁增加、删除、替换、翻译或改写任何非空白字符。不要解释，不要添加标题，不要新增项目符号。
                如果 OCR 原文已经包含项目符号，例如 "•"，必须原样保留这些符号，并把每条笔记拆成独立 Markdown 段落。
                题目正文不要使用粗体、斜体、分隔线或任何装饰性 Markdown 标记。
                输出必须严格包含两个块，不要使用代码块包裹，不要输出说明文字：
                FORMATTED_QUESTION
                整理后的 Markdown 题目正文
                END_FORMATTED_QUESTION
                QUESTION_METADATA
                Answer: 正确选项字母；如果无法从题目推出则留空
                Type: 只能填下面 7 个英文标签之一：reading、writing、notesSynthesis、vocabulary、grammar、math、unknown
                Section: 只能填 Reading and Writing、Math、unknown
                Domain: College Board SAT 官方 Domain；无法判断则留空
                Skill: College Board SAT 官方 Skill；无法判断则留空
                QuestionTypeID: 从 TutorClip SAT 类型目录选择稳定 ID；无法判断则留空
                KnowledgePoints: 从该类型对应的 TutorClip 知识点 ID 中选择 1-3 个，英文逗号分隔；无法判断则留空
                Difficulty: 只能填 easy、medium、hard、unknown
                Confidence: 0 到 1 之间的小数
                AnswerConfidence: 对正确答案判断的置信度，0 到 1；Answer 为空时填 0
                END_QUESTION_METADATA
                Type 字段禁止输出斜杠、多个标签、中文解释或额外文字。
                """
            ),
            DeepSeekMessage(
                role: "user",
                content: """
                请重新整理下面 OCR 文本的 Markdown 排版。

                硬性规则：
                - 不要增加任何文字。
                - 不要删除任何文字。
                - 不要修改任何单词、字母、数字、标点或符号。
                - 以上字符限制对表格语法有且只有一个例外：如果下面存在 STRUCTURED_TABLE_n，必须根据其中的制表符分列，输出标准 GFM Markdown 表格；允许增加表格结构所需的 |、- 和对齐符号。
                - STRUCTURED_TABLE_n 的行列关系优先于普通 OCR 行；第一行作为表头，其余行作为数据行。不得猜测、合并或改写单元格内容。
                - 如果结构摘要存在 DOCUMENT_TITLE，它是 Apple Vision 识别的权威文档/表格标题，必须完整放在第一个表格正上方，不得拆分、倒序或放到表格后面。
                - VISUAL_PARAGRAPHS_TOP_TO_BOTTOM 已按屏幕视觉位置从上到下排序。恢复标题和正文顺序时必须以它为准，不能使用 OCR 全文中可能错乱的出现顺序。
                - 如果结构化表格开头存在只有一个单元格的跨列行，它通常是表格标题而不是列标题；必须结合 OCR 全文或普通行中的相邻标题片段，按标题语义顺序放在表格正上方，再用下一行作为 GFM 表头。禁止把标题残片放到表格后面。
                - 同一表格标题因 OCR 被拆成相邻多行时，可以只通过空格和换行把它们合并成一个标题；不得改写标题文字。
                - 仅针对被 OCR 错排到表格前后两侧的标题残片，允许移动已有残片并合并到表格上方；这是除选项排列外唯一允许的文字重排，不能用于改写正文、题干、数据或选项。
                - 特别检查表格后、正文前是否存在一个读起来尚未结束的短标题残片；如果它能与结构化表格的单单元格标题行组成完整标题，必须把该残片移到标题行之前并合并，不能原地保留。
                - 结构化单元格的行列关系是权威的；如果单元格文字明显截断，只能用 OCR 普通行中实际出现的对应字符补全，不能凭常识猜字或数值。
                - 表格前后必须各有空白行。不要把 STRUCTURED_TABLE_n、END_STRUCTURED_TABLE_n 协议标记输出到 FORMATTED_QUESTION。
                - 只能调整空格、换行、空白行和段落。
                - SAT 题中供 A/B/C/D 填入的长横线是作答空格，包括语法填空和 “Which choice ... completes the text?” 逻辑补全题。作答空格必须统一输出为 `_____`，不能变成破折号、句号或直接消失。只有原文确实存在的破折号才能保留为 `—`；作答空格是符号保真规则的窄例外。
                - TutorClip 暂不支持数学题。如果内容涉及方程、代数、几何或其他数学公式，只需将 Type 标记为 math；禁止猜测、修复或补全公式字符。
                - 正文段落内不要保留 OCR 扫描产生的硬换行；同一个自然段应连续成一段，让 Markdown 自动换行。
                - 用 Markdown 段落排版：文章段落、题干、每个选项之间用一个空白行隔开。
                - 如果原文包含 "notes:" 后接多个 "•" 项目符号，每个 "•" 必须单独成行或单独成段；不要把多个 "•" 项目压在同一段。
                - 不要新增项目符号；但原文已有的 "•"、"-"、A/B/C/D 标记必须保留。
                - 如果出现题号，例如 "26."，题号所在问题必须和上方文章用空白行分开。
                - 如果出现 A/B/C/D 选项标记，每个选项标记前必须有空白行。
                - 选项标记必须保持 OCR 原样：原文是 "A" 就输出 "A"，原文是 "A." 才输出 "A."，绝对不要补点号或删除点号。
                - A/B/C/D 每个选项必须各自成为独立 Markdown 段落，不能和题干或其他选项在同一段。
                - 如果选项内容很长，不要手动硬换行，让 Markdown 自动换行；但不能把下一个选项接在同一段。
                - 不要添加 Markdown 标题、列表符号、粗体、引用块、代码块或分隔线。
                - FORMATTED_QUESTION 块内只输出整理后的 Markdown 文本。
                - QUESTION_METADATA 块只输出 Answer、Type、Section、Domain、Skill、QuestionTypeID、KnowledgePoints、Difficulty、Confidence、AnswerConfidence 字段。
                - Reading and Writing QuestionTypeID 只能是：RW.II.CID, RW.II.INF, RW.II.COE.TEXT, RW.II.COE.QUANT, RW.CS.WIC, RW.CS.TSP, RW.CS.CTC, RW.EI.RS, RW.EI.TR, RW.SEC.BND, RW.SEC.FSS。
                - KnowledgePoints 必须使用 TutorClip 知识点稳定 ID；不确定时留空，禁止自造 ID。
                - 合法 KnowledgePoints ID：\(SATKnowledgeCatalog.knowledgePoints.map(\.id).joined(separator: ", "))
                - 如果能解出正确答案，Answer 填 A/B/C/D；如果 OCR 不完整或无法判断，Answer 留空。
                - Type 必须判断 SAT 题型，只能输出一个标签：reading、writing、notesSynthesis、vocabulary、grammar、math、unknown。
                - 如果题目包含 "student has taken the following notes"、项目符号笔记、并要求 "accomplish this goal"，Type 必须填 notesSynthesis。
                - 只有真正涉及方程、图形、函数、代数、几何、数值计算或数学推理时才填 math；普通英文中的 value/function/mean 不算 math。
                - 不要把所有候选标签写到 Type 后面；例如禁止输出 "reading/writing/notesSynthesis"。

                输出结构示例：
                文章段落作为连续自然段，不要在句子中间硬换行...

                26. 问题文字...

                A 选项文字...

                B 选项文字...

                C 选项文字...

                D 选项文字...

                OCR 文本：
                \(document.editedText.isEmpty ? "(OCR 为空)" : document.editedText)

                OCR 结构摘要（仅用于恢复版面，不得原样输出协议标记）：
                \(structure.isEmpty ? "(无结构摘要)" : structure)
                """
            )
        ]
    }

    func repairTableFormattingPrompt(document: OCRDocument, candidate: String, validationFeedback: String = "") -> [DeepSeekMessage] {
        let structure = formattingStructureSummary(for: document)
        return [
            DeepSeekMessage(
                role: "system",
                content: """
                你是 SAT 表格题 Markdown 布局审校器。只检查候选排版中的表格标题、GFM 表格、正文和选项顺序。
                必须把被 OCR 错排在表格前后两侧的已有标题残片合并为完整标题，并放在表格正上方。跨列单单元格行是标题，不是表头；下一行才是表头。
                如果 OCR 表格结构提供 DOCUMENT_TITLE，必须逐字使用它作为第一个表格上方的完整标题，并删除候选中重复或拆散的标题残片。
                表格必须保留结构摘要中的全部行列和单元格文字。可以补充 GFM 的 |、-，也可以用 OCR 全文实际出现的字符修复截断；不得猜测或改写数据、正文、题干和选项。
                表格列数必须等于数据行中最大的单元格数，每个表头和每行数据必须严格同列数。若 OCR 把相邻表头合并成一个单元格，必须使用 OCR 普通行和视觉段落中已经出现的表头文字拆回对应列，禁止让一列拥有两个字段名称。
                只输出 FORMATTED_QUESTION 与 END_FORMATTED_QUESTION 包裹的修正版，不要解释，不要输出代码块。
                """
            ),
            DeepSeekMessage(
                role: "user",
                content: """
                OCR 全文：
                \(document.editedText)

                OCR 表格结构：
                \(structure)

                待审校候选：
                \(candidate)

                必做审校步骤：
                1. 找到候选中的第一个 GFM 表格。
                2. 检查表格后、第一段完整正文前的所有短独立行；如果某行没有句末标点、语义未结束或以连词结束，应视为表格标题残片。
                3. 将这些已有残片与表格前的标题行按能组成完整标题的语义顺序合并，完整标题只出现一次并紧邻表格上方。
                标题残片在 OCR 中可能是反序的，禁止照 OCR 出现顺序机械拼接。英文残片如果以 and、or、of、for 等连接词结束，它必须放在能补全该连接关系的残片之前；最终标题必须是语法完整、自然的名词短语，不能以连接词结束。
                4. 输出前确认表格后、正文前不再残留标题碎片，并确认表格行列未丢失。
                5. 逐行数竖线分隔后的单元格：表头列数必须与每一条数据行完全一致；数据行较宽时，说明表头发生了 OCR 合并，必须恢复缺失的独立表头列。
                \(validationFeedback.isEmpty ? "" : "上次审校失败：\(validationFeedback) 本次必须修正，同时完整保留所有正文和 A/B/C/D 选项。")
                """
            )
        ]
    }

    func restoreMissingQuestionContentPrompt(source: String, candidate: String) -> [DeepSeekMessage] {
        [
            DeepSeekMessage(
                role: "system",
                content: """
                你是 SAT 题目内容完整性修复器。候选已经包含正确的 Markdown 表格，但可能遗漏原始 OCR 中的正文、题干或选项。
                逐项对照原始 OCR，把遗漏内容按原顺序补回候选；必须保留候选中的完整标题和 GFM 表格，不得删减、总结、翻译或改写任何原文。
                如果原文包含 A/B/C/D，输出必须完整包含 A/B/C/D。只输出 FORMATTED_QUESTION 与 END_FORMATTED_QUESTION 包裹的完整结果。
                """
            ),
            DeepSeekMessage(
                role: "user",
                content: """
                原始 OCR：
                \(source)

                已修表格候选：
                \(candidate)
                """
            )
        ]
    }

    func classifyQuestionPrompt(text: String) -> [DeepSeekMessage] {
        [
            DeepSeekMessage(
                role: "system",
                content: """
                You classify SAT questions. Return exactly one label and nothing else:
                reading
                writing
                notesSynthesis
                vocabulary
                grammar
                math
                unknown

                Guidelines:
                - Use math only for actual SAT math questions with equations, values, geometry, graphs, functions like f(x), numeric reasoning, or algebra.
                - Do not classify ordinary English words such as "function", "value", or "mean" as math unless the task is mathematical.
                - Reading questions ask about meaning, inference, evidence, claims, main idea, function of a sentence, or logical completion based on text evidence.
                - Writing questions ask about rhetorical goals, transitions, precision, concision, placement, or combining sentences.
                - Grammar questions ask about Standard English conventions, punctuation, sentence boundaries, modifiers, agreement, or idiom.
                - Vocabulary questions ask what a word or phrase means in context.
                - Notes synthesis questions include student notes and ask which choice uses relevant information to accomplish a goal.
                """
            ),
            DeepSeekMessage(
                role: "user",
                content: """
                Classify this SAT question. Return one label only.

                \(text.isEmpty ? "(empty)" : text)
                """
            )
        ]
    }

    private func instruction(for action: TutorAction, hasSelection: Bool, category: SessionCategory, language: AppLanguage) -> String {
        if language == .english {
            return englishInstruction(for: action, hasSelection: hasSelection, category: category)
        }
        switch action {
        case .explainAll:
            return explanationInstruction(for: category, language: language)
        case .translateAll:
            return formattedTranslationInstruction(scope: "OCR 全文", language: language)
        case .formatOCR:
            return "请只整理 OCR 文本排版，不要增加、删除或修改任何非空白字符。"
        case .checkOCR:
            return "请检查 OCR 文本是否像一道完整 SAT 阅读与写作题，指出缺失、乱码或选项不完整的地方。"
        case .translateSelection:
            return hasSelection ? formattedTranslationInstruction(scope: "用户选中的文本", language: language) : formattedTranslationInstruction(scope: "OCR 全文", language: language)
        case .explainSelection:
            if hasSelection {
                return """
                请只解释用户选中文本在题目中的作用，不要自动展开整题。
                按语义块输出：原文：英文片段；下一行翻译：中文意思；然后说明它在文章逻辑或选项判断中的作用。
                """
            }
            return "请结合 OCR 全文讲解这道 SAT 题，先给结论，再用关键英文原文和紧邻中文翻译解释。"
        case .vocabulary:
            return hasSelection
                ? vocabularyInstruction(scope: "用户选中文本", language: language)
                : vocabularyInstruction(scope: "OCR 全文", language: language)
        case .grammar:
            return passageAnalysisInstruction(hasSelection: hasSelection, language: language)
        case .practiceSimilar:
            return practiceSimilarInstruction(language: language)
        case .customQuestion:
            return """
            请只回答用户问题，基于 OCR 全文给出 SAT 老师式讲解。
            不要自动翻译、总结或逐句解释整段，除非用户明确要求。
            如果需要证据，请用“原文：...”下一行“翻译：...”的形式引用关键片段。
            """
        case .guidedLearning:
            return "只执行用户指定的引导学习步骤，禁止给出原题答案或判断原题选项。"
        }
    }

    private func englishInstruction(for action: TutorAction, hasSelection: Bool, category: SessionCategory) -> String {
        switch action {
        case .explainAll:
            return explanationInstruction(for: category, language: .english)
        case .translateAll:
            return formattedTranslationInstruction(scope: "the full OCR text", language: .english)
        case .formatOCR:
            return "Only format the OCR text. Do not add, delete, or change any non-whitespace characters."
        case .checkOCR:
            return "Check whether the OCR text looks like a complete SAT Reading and Writing question. Point out missing text, garbled text, or incomplete choices."
        case .translateSelection:
            return hasSelection ? formattedTranslationInstruction(scope: "the selected text", language: .english) : formattedTranslationInstruction(scope: "the full OCR text", language: .english)
        case .explainSelection:
            return hasSelection
                ? "Explain only the selected text's role in the question. Do not expand into a full-solution explanation unless needed."
                : "Explain this SAT question in English. Start with the answer, then use key source evidence."
        case .vocabulary:
            return hasSelection
                ? vocabularyInstruction(scope: "the selected text", language: .english)
                : vocabularyInstruction(scope: "the full OCR text", language: .english)
        case .grammar:
            return passageAnalysisInstruction(hasSelection: hasSelection, language: .english)
        case .practiceSimilar:
            return practiceSimilarInstruction(language: .english)
        case .customQuestion:
            return "Answer the user's question in English based on the OCR text. Do not translate or summarize the whole passage unless the user asks."
        case .guidedLearning:
            return "Perform only the requested guided-learning step. Do not reveal or judge the original question's answer choices."
        }
    }

}
