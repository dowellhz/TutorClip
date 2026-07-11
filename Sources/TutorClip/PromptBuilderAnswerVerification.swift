import Foundation

extension PromptBuilder {
    func answerSolverPrompt(question: String) -> [DeepSeekMessage] {
        [
            DeepSeekMessage(role: "system", content: verificationSystemPrompt),
            DeepSeekMessage(role: "user", content: """
            独立解答下面 SAT 选择题。不要采信题目文本之外的任何既有答案。
            对表格题必须先写出题干要求数据证明的精确主张，再在内部逐项计算每个选项所给区间内、各比较对象的变化量或差距变化。
            “跨度最大”本身不是证据；禁止只因文章提到长期趋势就机械选择最早与最晚年份。必须选择最直接区分题干所述现象的比较。
            若主张是两个对象“变化速度不同”，对每个候选区间都要计算：起点时各对应类别差值的总量，以及终点时该差值总量。只有差值明显扩大的区间才能直接显示两者发生了不同速度的转型；起终点仍相近的区间不能证明速度不同。
            Evidence 必须写出决定答案的具体数据变化，并明确说明为什么该变化比其他区间更能证明题干主张。

            \(question)
            """)
        ]
    }

    func answerCriticPrompt(question: String, proposal: AnswerVerification) -> [DeepSeekMessage] {
        [
            DeepSeekMessage(role: "system", content: verificationSystemPrompt),
            DeepSeekMessage(role: "user", content: """
            你是第二位独立 SAT 审核老师。先从零解题并逐项核对，再判断候选答案是否正确。不能因为候选答案存在而迎合它。
            对表格题必须明确题干要求证明的是“共同趋势”还是“对象之间速度/幅度不同”，并核对每个候选区间内各对象的变化量。
            不得把“覆盖题目提到的完整年代”误当作“最有效支持主张”；时间跨度只有在数据确实显示目标差异时才有意义。若候选错误，输出你独立得到的答案。
            对“对象之间速度不同”的主张，必须复算每个候选区间起点和终点的对象间总差值；如果候选区间两端对象都同样接近，它不能证明不同速度，即使跨度很长。

            题目：
            \(question)

            第一位老师的候选：\(proposal.answer)
            第一位老师的依据：\(proposal.evidence)
            """)
        ]
    }

    private var verificationSystemPrompt: String {
        """
        你只负责验证 SAT 选择题答案，不负责 OCR 排版或教学讲解。必须依据题目中实际存在的文字、数字和选项独立推理，不得猜测缺失内容。
        最终只输出以下协议，不要使用代码块或补充其他文字：
        ANSWER_VERIFICATION
        Answer: A/B/C/D 中一个字母
        Confidence: 0 到 1
        Evidence: 一行具体证据；表格题必须包含关键数值比较
        END_ANSWER_VERIFICATION
        若题目不完整或无法可靠作答，Confidence 必须低于 0.8。
        """
    }
}
