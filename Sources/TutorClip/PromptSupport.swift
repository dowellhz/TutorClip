import Foundation

extension PromptBuilder {
    func practiceGenerationSystemPrompt(language: AppLanguage) -> String {
        if language == .english {
            return """
            You generate SAT-style practice questions. Output only the required machine-readable blocks. Do not explain, solve, tutor, summarize, or reveal the answer outside QUESTION_METADATA.
            """
        }
        return """
        你是 SAT 风格练习题生成器。只能输出指定机器可解析块。不要讲解、不要解题、不要总结、不要在 QUESTION_METADATA 以外泄露答案。
        """
    }

    func explanationInstruction(for category: SessionCategory, language: AppLanguage) -> String {
        switch language {
        case .chinese:
            return chineseExplanationInstruction(for: category)
        case .english:
            return englishExplanationInstruction(for: category)
        }
    }

    func categoryGuidance(for category: SessionCategory, language: AppLanguage) -> String {
        switch language {
        case .chinese:
            return chineseCategoryGuidance(for: category)
        case .english:
            return englishCategoryGuidance(for: category)
        }
    }

    func formattedTranslationInstruction(scope: String, language: AppLanguage) -> String {
        if language == .english {
            return """
            Return only the English translation or cleaned English rendering of \(scope). Do not answer the SAT question, identify the correct choice, explain choices, summarize, add headings, or use decorative Markdown:
            - Preserve paragraph breaks and question/choice structure.
            - If the source is already English, keep it in English and only make the wording readable where OCR spacing is clearly broken.
            - Keep question numbers, choice letters, punctuation, parentheses, and dashes.
            - If OCR is obviously garbled or incomplete, translate/render only what can be determined without inventing content.
            """
        }
        return """
        请只返回\(scope)的中文译文。不要回答题目、不要给正确选项、不要讲解选项、不要总结、不要输出英文原文、不要添加标题：
        - 不要使用 Markdown 标题、粗体、列表、分隔线或代码块。
        - 严格保留原文的段落结构和空白行，不要合并或拆分段落。
        - 正文自然段翻译成中文自然段，不要在句子中间硬换行。
        - 保留题号、选项字母、冒号、括号、破折号等结构标记，但内容必须翻译成中文。
        - 如果原文有 A/B/C/D 选项，每个选项必须各自独立成段。
        - 如果某一行 OCR 明显乱码或残缺，只翻译能判断的部分，不要添加「OCR 不确定」等说明。
        """
    }

    func vocabularyInstruction(scope: String, language: AppLanguage) -> String {
        if language == .english {
            return """
            Extract only important vocabulary from \(scope). If this is selected text, use only the selected text and do not pull vocabulary from the rest of the passage.
            Do not answer the SAT question, identify the correct choice, solve the question, summarize the passage, translate the whole text, or explain grammar.
            Include only genuinely useful SAT-level words, short phrases, fixed expressions, collocations, and paraphrases. Skip basic words.
            For each item, give the meaning in this passage first, then the general meaning, then one short example sentence.
            Start with this machine-readable block. Keep field names in English:
            VOCAB_CARDS
            - Term: original word or phrase | Meaning: meaning in this passage | Note: general meaning or common paraphrase | Example: short example sentence | Source: short source phrase
            END_VOCAB_CARDS
            Then output concise Markdown:
            ### Vocabulary
            - **original item**: In context: ... General meaning: ... Example: ...
            ### Phrases / Collocations
            - **original phrase**: In context: ... General meaning: ... Example: ...
            If there are very few useful items, return only those items. Do not invent items that are not in the text.
            """
        }
        return """
        请只从\(scope)中整理重要词汇清单。如果是用户选中文本，就只看选中内容，不要从文章其他地方扩展。
        不要回答题目、不要给正确选项、不要讲题、不要总结文章、不要全文翻译、不要分析语法。
        只选真正有用的 SAT 难词、短语、固定搭配、常见表达和同义转述；跳过基础词。
        每一项必须先给它在文章/选中内容里的意思，再给这个词或短语的一般词义，最后给一个简短英文例句。
        开头必须先输出这个机器可解析块，字段名必须保持英文：
        VOCAB_CARDS
        - Term: 英文原词或短语 | Meaning: 文中含义 | Note: 一般词义或常见同义转述 | Example: 简短英文例句 | Source: 原文短片段
        END_VOCAB_CARDS
        然后再输出给用户看的简洁 Markdown：
        ### 难词
        - **英文原词**：文中含义：...；一般词义：...；例句：...
        ### 短语和固定搭配
        - **英文短语**：文中含义：...；一般词义：...；例句：...
        如果值得讲的内容很少，就只列少量项目。不要编造原文没有的词或短语。
        """
    }

    func practiceSimilarInstruction(language: AppLanguage) -> String {
        if language == .english {
            return """
            Create one new SAT-style practice question with the same question type, tested skill, and approximate difficulty as the OCR question.
            Do not reuse the original passage topic, names, wording, or answer choices.
            Do not show the answer, explanation, hint, or solution to the user.
            Output exactly two blocks:
            FORMATTED_QUESTION
            the new practice question in clean Markdown, including passage/stimulus, question stem, and A/B/C/D choices
            END_FORMATTED_QUESTION
            QUESTION_METADATA
            Answer: correct choice letter
            Type: exactly one of reading, writing, notesSynthesis, vocabulary, grammar, math, unknown
            END_QUESTION_METADATA
            Do not output slash-separated labels such as reading/writing/notesSynthesis.
            Keep it realistic and concise.
            """
        }
        return """
        请仿照 OCR 题目，生成一道新的 SAT 风格练习题，题型、考点和难度要接近原题。
        不要复用原题的话题、人物、措辞或选项。
        不要把答案、解析、提示或解题思路展示给用户。
        必须严格输出两个块：
        FORMATTED_QUESTION
        新练习题本身，用清晰 Markdown 排版，包含文章或题干材料、问题、A/B/C/D 选项
        END_FORMATTED_QUESTION
        QUESTION_METADATA
        Answer: 正确选项字母
        Type: 只能填一个标签：reading、writing、notesSynthesis、vocabulary、grammar、math、unknown
        END_QUESTION_METADATA
        不要输出 reading/writing/notesSynthesis 这种斜杠组合。
        题目要真实、简洁，适合学生重新做一遍。
        """
    }

    func passageAnalysisInstruction(hasSelection: Bool, language: AppLanguage) -> String {
        if language == .english {
            return """
            Analyze the full SAT passage in English rather than solving the question directly.
            Use Markdown with these sections:
            ### 1. Main Idea
            ### 2. Structure
            ### 3. Key Evidence
            ### 4. Useful Expressions
            ### 5. Hard Sentence
            ### 6. How This Helps With Questions
            Keep every heading followed immediately by content.
            """
        }

        let focus = hasSelection
            ? "用户选中文本只是重点关注区域，不要只解析选中文本。先帮用户读懂全文，再补充选中文本相关的重点。"
            : "不是只讲语法点，也不要直接解题。帮助用户读懂文章、看清结构、抓住 SAT 常见表达和逻辑。"
        let finalSection = hasSelection ? "对做题的帮助" : "做题提示"
        let finalInstruction = hasSelection
            ? "说明这篇文章的核心逻辑如何帮助判断题干或选项；如果选中文本重要，专门说明它的作用。"
            : "说明这篇文章的核心逻辑通常会如何对应题干或选项判断，但不要代替“讲解整题”。"

        return """
        请解析 OCR 全文这篇 SAT 文章。\(focus)
        必须用中文回答，保留关键英文原文。回答紧凑，不要连续空行，不要表格。
        每个编号后面必须直接跟内容，不能出现只有编号的空行。
        必须按这个 Markdown 结构输出：
        ### 1. 文章主旨
        用 1-2 句话说明这段文章主要讲什么。
        ### 2. 结构脉络
        用项目符号按自然语义块说明文章怎么推进，例如背景、转折、发现、结论或例子。
        ### 3. 原文结合翻译
        挑 2-3 个最关键的英文片段。每个片段必须按下面格式输出：
        > 英文关键片段
        翻译：对应中文意思。
        解释：它在文章逻辑中的作用。
        ### 4. 重点表达
        用项目符号解释真正影响理解的词组、搭配、转折、同义转述或 SAT 常见表达；跳过基础词。
        ### 5. 长难句
        只挑 1 个最影响理解的句子，拆主干、从句/修饰关系，并给自然中文。
        ### 6. \(finalSection)
        \(finalInstruction)
        """
    }

    func structuredSummary(for document: OCRDocument) -> String {
        document.lines.prefix(80).enumerated().map { index, line in
            let box = line.boundingBox
            return "\(index + 1). [x:\(box.x.rounded2), y:\(box.y.rounded2), w:\(box.width.rounded2), h:\(box.height.rounded2), c:\(Double(line.confidence).rounded2)] \(line.text)"
        }.joined(separator: "\n")
    }

    private func chineseExplanationInstruction(for category: SessionCategory) -> String {
        switch category {
        case .math:
            return explainHeader(language: .chinese) + """
            摘要块之后按这个结构讲：
            ### 1. 正确答案
            直接给最终答案，并用一句话说明核心原因。
            ### 2. 已知条件
            提取题目给出的数值、关系、图形信息或方程，不要套用阅读题证据格式。
            ### 3. 考点
            说明考的是代数、函数、比例、几何、统计或其他具体概念。
            ### 4. 解题步骤
            分步列式/计算，每一步说明为什么这么做。
            ### 5. 易错点
            说明常见误读、单位、符号、范围或计算陷阱。
            ### 6. 选项排除
            如果有 A/B/C/D，逐项说明每个错误选项对应的误区。
            """
        case .grammar:
            return explainHeader(language: .chinese) + """
            摘要块之后按这个结构讲：
            ### 1. 正确答案
            先给选项和一句话规则理由。
            ### 2. 题干考点
            明确 tested rule：标点、句子边界、主谓一致、修饰语、代词、时态、过渡或惯用表达。
            ### 3. 原文结构
            引用关键英文片段，下一行给中文翻译，再说明句法关系。
            ### 4. 为什么正确
            说明正确选项如何同时满足语法规则和上下文逻辑。
            ### 5. 为什么其他选项不对
            A/B/C/D 逐项排除，每项独立成段，指出具体语法或表达错误。
            ### 6. 可迁移规则
            总结这类题下次怎么判断。
            """
        case .writing, .notesSynthesis:
            return explainHeader(language: .chinese) + """
            摘要块之后按这个结构讲：
            ### 1. 正确答案
            先给选项和一句话理由。
            ### 2. 题干目标
            说明题干要求完成什么写作目的或使用哪些相关信息。
            ### 3. 上下文逻辑
            引用关键英文片段，下一行给中文翻译，再说明前后关系。
            ### 4. 为什么正确
            说明正确选项如何最准确、最简洁、最有效地完成目标。
            ### 5. 为什么其他选项不对
            A/B/C/D 逐项排除，每项独立成段，指出偏离目标、无关、重复、过度推断、语气不合或信息不完整。
            ### 6. 写作判断方法
            总结这类题的判断顺序。
            """
        case .vocabulary:
            return explainHeader(language: .chinese) + """
            摘要块之后按这个结构讲：
            ### 1. 正确答案
            先给选项和目标词在文中的意思。
            ### 2. 上下文线索
            引用目标词前后的英文片段，下一行给中文翻译，再说明语义方向。
            ### 3. 同义替换
            把正确选项代回原句，说明为什么语气、对象和逻辑都合适。
            ### 4. 为什么其他选项不对
            A/B/C/D 逐项排除，每项独立成段，指出常见释义但不合语境、语气不对、对象不对或逻辑相反。
            ### 5. 记忆点
            只讲这个词/短语在本题中有用的含义。
            """
        case .reading, .unknown:
            return explainHeader(language: .chinese) + """
            摘要块之后按这个结构讲：
            ### 1. 正确答案
            先给选项和一句话理由。
            ### 2. 原文结合翻译
            只引用最关键的英文证据；每段证据下一行给中文翻译，再解释如何支持答案。
            ### 3. 解题关键
            说明题干问什么，以及答案要在原文哪类逻辑里找。
            ### 4. 为什么正确
            说明正确选项和原文的同义转述、因果、转折或范围关系。
            ### 5. 为什么其他选项不对
            A/B/C/D 逐项排除，每项独立成段，指出未提及、偷换对象、范围不对、因果倒置、只对一半或与转折后结论相反。
            ### 6. 词汇/推理点
            只讲对判断答案有帮助的点。
            """
        }
    }

    private func englishExplanationInstruction(for category: SessionCategory) -> String {
        switch category {
        case .math:
            return explainHeader(language: .english) + "After the summary block, use Markdown sections: Correct Answer, Given Information, Tested Concept, Steps, Common Trap, Choice Elimination."
        case .grammar:
            return explainHeader(language: .english) + "After the summary block, use Markdown sections: Correct Answer, Tested Rule, Sentence Structure, Why It Is Right, Why Other Choices Are Wrong, Transferable Rule."
        case .writing, .notesSynthesis:
            return explainHeader(language: .english) + "After the summary block, use Markdown sections: Correct Answer, Question Goal, Context Logic, Why It Is Right, Why Other Choices Are Wrong, Writing Method."
        case .vocabulary:
            return explainHeader(language: .english) + "After the summary block, use Markdown sections: Correct Answer, Context Clues, Substitution Test, Why Other Choices Are Wrong, Vocabulary Takeaway."
        case .reading, .unknown:
            return explainHeader(language: .english) + "After the summary block, use Markdown sections: Correct Answer, Text Evidence, Question Task, Why It Is Right, Why Other Choices Are Wrong, Useful Reasoning Points."
        }
    }

    private func explainHeader(language: AppLanguage) -> String {
        if language == .english {
            return """
            Explain this SAT question in English. Be concise and start with:
            ANSWER_SUMMARY
            Answer: choice letter or final answer
            Reason: one-sentence reason
            Evidence: the key source-text evidence; leave blank if unavailable
            END_ANSWER_SUMMARY
            """
        }
        return """
        请讲解这道 SAT 题。必须先给结论，必须紧凑，不要连续空行，不要输出空标题或单独的 Markdown 标记。
        开头必须先输出这个机器可解析摘要块，字段名必须保持英文：
        ANSWER_SUMMARY
        Answer: 选项字母或最终答案
        Reason: 一句话理由
        Evidence: 最关键英文证据片段；没有则留空
        END_ANSWER_SUMMARY
        """
    }

    private func chineseCategoryGuidance(for category: SessionCategory) -> String {
        switch category {
        case .notesSynthesis:
            return "题型要求：这是 SAT 笔记综合题。优先判断题干目标，正确选项必须只使用相关笔记且完成目标。"
        case .vocabulary:
            return "题型要求：这是词义/语境题。先根据上下文判断目标词或短语在文中的功能和语义，再用同义替换验证选项。"
        case .grammar:
            return "题型要求：这是语法/表达题。优先讲清 tested rule，正确答案必须同时语法正确且符合上下文逻辑。"
        case .math:
            return "题型要求：这是数学题。按已知条件、考点、步骤、易错点、最终答案讲；不要套阅读题的原文证据格式。"
        case .writing:
            return "题型要求：这是 SAT Writing 题。优先判断题干目标和上下文逻辑，说明正确选项如何完成写作目的。"
        case .reading:
            return "题型要求：这是 SAT Reading 题。答案必须来自文本证据，重点讲题干问法、关键证据、同义转述和错误选项陷阱。"
        case .unknown:
            return "题型要求：题型不确定。先说明你如何判断题型；如果 OCR 不完整或题目不清楚，不要编造缺失内容。"
        }
    }

    private func englishCategoryGuidance(for category: SessionCategory) -> String {
        switch category {
        case .notesSynthesis:
            return "Question type guidance: This is an SAT notes synthesis question. Focus on the student's goal and whether each choice uses only relevant notes to accomplish that goal."
        case .vocabulary:
            return "Question type guidance: This is a vocabulary-in-context question. Use surrounding context to infer the meaning, then test choices as paraphrases."
        case .grammar:
            return "Question type guidance: This is a grammar or expression question. Explain the tested rule and name the specific issue in wrong choices."
        case .math:
            return "Question type guidance: This is a math question. Explain given information, concept, setup, calculation, traps, and final answer."
        case .writing:
            return "Question type guidance: This is an SAT Writing question. Focus on goal, context logic, precision, concision, and effectiveness."
        case .reading:
            return "Question type guidance: This is an SAT Reading question. The answer must be supported by text evidence."
        case .unknown:
            return "Question type guidance: The type is uncertain. State how you are interpreting the question and do not invent missing OCR content."
        }
    }
}

private extension Double {
    var rounded2: String {
        String(format: "%.2f", self)
    }
}
