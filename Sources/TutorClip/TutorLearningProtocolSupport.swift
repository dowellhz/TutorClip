import Foundation

@MainActor
extension TutorViewModel {
    func learningFocusContext() -> String {
        guard let focus = session.learningMetadata.needsReviewFlow.learningFocus else {
            return text("刚才讲解的唯一知识点或英文片段", "the single point or English segment just taught")
        }
        return "Type: \(focus.type)\nText: \(focus.text)\nObjective: \(focus.objective)"
    }

    func recoveredLearningFocus() -> SATLearningFocus? {
        guard let explanation = session.messages.last(where: {
            $0.role == .assistant && !$0.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        })?.content.trimmingCharacters(in: .whitespacesAndNewlines) else {
            return nil
        }
        let type = session.learningMetadata.needsReviewFlow.gap == .englishReading
            ? "sentence"
            : "concept"
        return SATLearningFocus(
            type: type,
            text: String(explanation.prefix(1_200)),
            objective: text(
                "能独立应用刚才讲解的唯一焦点。",
                "Apply the single focus from the preceding explanation independently."
            )
        )
    }

    func learningFocusProtocolInstruction() -> String {
        text(
            "回复最后必须输出且只输出一次：\nLEARNING_FOCUS\nType: vocabulary、sentence、task、concept、application 之一\nText: 本次唯一焦点，必须单行\nObjective: 学生下一步应能做到什么，必须单行\nEND_LEARNING_FOCUS",
            "End with exactly one block:\nLEARNING_FOCUS\nType: one of vocabulary, sentence, task, concept, application\nText: the single focus on one line\nObjective: what the student should do next on one line\nEND_LEARNING_FOCUS"
        )
    }

    func microCheckProtocolInstruction() -> String {
        text(
            "回复最后必须逐行输出以下协议，不得使用代码块、项目符号或加粗：\nMICRO_CHECK\nQuestion: 题目\nA. 选项\nB. 选项\nC. 选项\nD. 选项\nAnswer: 正确字母\nEND_MICRO_CHECK",
            "End with the exact MICRO_CHECK protocol using Question, A/B/C/D, Answer, and END_MICRO_CHECK lines; no code fence, bullets, or bold."
        )
    }
}
