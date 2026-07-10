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
        如果是 SAT Math，按已知条件、考点、步骤、易错点、最终答案讲。
        如果用户只是追问某一点，只回答用户问题，不要自动翻译、总结或展开整题。
        如果 OCR 文本明显缺失、混乱或无法判断，请直接说明不确定之处，不要编造题目内容。
        """
    }

    private var englishSystemPrompt: String {
        """
        You are an experienced SAT tutor. Your goal is to help the student understand the question, reason through the answer choices, and learn the relevant reading, writing, vocabulary, grammar, or math concept.

        Answer in English by default. Keep explanations concise, use standard Markdown, and avoid decorative dividers, code blocks, and tables. Markdown markers must always have real content.

        For multiple-choice questions, start with the conclusion:
        1. Correct answer: choice letter + one-sentence reason.
        2. Text evidence: quote only the key phrase or sentence and explain how it supports the answer.
        3. What the question asks: identify the task and where the support appears.
        4. Why the correct choice is right: connect the choice to the source text.
        5. Why the other choices are wrong: eliminate each choice in its own paragraph using "Choice A: Wrong. Trap: ... Reason: ..."; do not combine multiple choices into one paragraph.

        For SAT Reading/Writing, prioritize question logic, paraphrase, sentence relationships, vocabulary, and grammar that affect the answer. For SAT Math, explain given information, tested concept, steps, traps, and final answer. If OCR is incomplete or ambiguous, say what is uncertain and do not invent missing content.
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
            let structure = structuredSummary(for: document)
            if !structure.isEmpty {
                parts.append("\(language.text("OCR 结构摘要", "OCR layout summary"))：\n\(structure)")
            }
            if !selected.isEmpty {
                parts.append("\(language.text("用户选中文本", "Selected text"))：\n\(selected)")
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
        [
            DeepSeekMessage(
                role: "system",
                content: """
                你是 SAT OCR Markdown 排版整理器。你的任务是把 OCR 文本整理成可直接用 Markdown 渲染的清晰文本，并提取选择题正确答案和题型。
                你只允许调整空格、换行、空白行、段落和选项排列。
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
                - 只能调整空格、换行、空白行和段落。
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
                - QUESTION_METADATA 块只输出 Answer 和 Type 字段。
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
            return "请检查 OCR 文本是否像一道完整 SAT 题，指出缺失、乱码、选项不完整或数学符号错误的地方。"
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
            return "Check whether the OCR text looks like a complete SAT question. Point out missing text, garbled text, incomplete choices, or math-symbol issues."
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
        }
    }

}
