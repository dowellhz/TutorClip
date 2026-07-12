import Foundation

@MainActor
extension TutorViewModel {
    func setStudyStatus(_ status: StudyStatus) {
        guard session.studyStatus != status else { return }
        session.studyStatus = status
        let nextStep: SATLearningNextStep?
        if status == .known && !hasIndependentCorrectEvidence {
            session.learningMetadata.masteryState = .pendingVerification
            session.learningMetadata.nextReviewAt = Date()
            session.learningMetadata.reviews.append(SATReviewEvent(status: .known, scheduledFor: Date()))
            nextStep = .scheduleVerification(Date())
        } else {
            nextStep = SATLearningStateMachine.apply(status: status, metadata: &session.learningMetadata)
        }
        learningFeedback = feedback(for: nextStep)
        if status == .needsReview {
            var flow = SATNeedsReviewFlow(
                stage: .chooseGap,
                originalDifficulty: session.learningMetadata.difficulty
            )
            flow.questionChain = [currentQuestionSnapshot(role: .original)]
            session.learningMetadata.needsReviewFlow = flow
            learningFeedback = text("已标记为“不会”。先选择你卡住的地方。", "Marked for review. First choose where you are stuck.")
        } else {
            session.learningMetadata.needsReviewFlow = SATNeedsReviewFlow()
        }
        session.updatedAt = Date()
        objectWillChange.send()
        saveLearningState(errorMessage: text("学习状态保存失败。", "Failed to save study status."))
    }

    private var hasIndependentCorrectEvidence: Bool {
        session.learningMetadata.attempts.contains {
            $0.wasCorrect && !$0.usedHint && $0.countsTowardMastery
        }
    }

    private func currentQuestionSnapshot(role: SATQuestionChainRole) -> SATQuestionSnapshot {
        SATQuestionSnapshot(
            role: role,
            text: session.ocrDocument.editedText,
            correctAnswer: session.correctAnswer,
            category: session.category,
            difficulty: session.learningMetadata.difficulty
        )
    }

    func selectLearningGap(_ gap: SATLearningGap) {
        session.learningMetadata.needsReviewFlow.gap = gap
        if gap == .englishReading {
            session.learningMetadata.needsReviewFlow.stage = .chooseEnglishBarrier
            learningFeedback = text("先确认具体是哪一种英文障碍。", "First identify the specific English barrier.")
        } else {
            session.learningMetadata.needsReviewFlow.stage = .planReady
            learningFeedback = text("学习计划：基础讲解 → 微型检查 → 简单同类题。", "Plan: foundation → quick check → easier SAT question.")
        }
        persistLearningFlow()
    }

    func restartNeedsReviewDiagnosis() {
        let originalDifficulty = session.learningMetadata.needsReviewFlow.originalDifficulty
        let questionChain = session.learningMetadata.needsReviewFlow.questionChain
        var flow = SATNeedsReviewFlow(
            stage: .chooseGap,
            originalDifficulty: originalDifficulty
        )
        flow.questionChain = questionChain
        session.learningMetadata.needsReviewFlow = flow
        learningFeedback = text("重新选择你真正卡住的地方。", "Choose where you are actually stuck.")
        persistLearningFlow()
    }

    func selectEnglishBarrier(_ barrier: SATEnglishBarrier) {
        session.learningMetadata.needsReviewFlow.englishBarrier = barrier
        session.learningMetadata.needsReviewFlow.stage = .planReady
        learningFeedback = text("英文辅助计划：定位障碍 → 拆解理解 → 含义检查 → 回到原题。", "English support plan: diagnose → unpack → meaning check → return to the question.")
        persistLearningFlow()
    }

    func scheduleNeedsReviewForLater() {
        session.learningMetadata.needsReviewFlow.stage = .scheduled
        learningFeedback = text("已加入今日复习，可以从学习中心继续。", "Added to today's review. Continue from the Learning Center.")
        persistLearningFlow()
    }

    func startNeedsReviewLearning() {
        guard let gap = session.learningMetadata.needsReviewFlow.gap else { return }
        learningLoadingAction = .foundation
        session.learningMetadata.needsReviewFlow.stage = .foundation
        session.learningMetadata.needsReviewFlow.learningFocus = nil
        let isEnglishFlow = gap == .englishReading
        learningFeedback = isEnglishFlow
            ? text("英文辅助 · 拆解理解 2/4", "English support · Unpack 2/4")
            : text("不会题学习 · 基础讲解 1/3", "Review learning · Foundation 1/3")
        persistLearningFlow()
        send(action: .guidedLearning, question: foundationPrompt(for: gap))
    }

    func requestAlternativeFoundation() {
        learningLoadingAction = .alternativeExplanation
        session.learningMetadata.needsReviewFlow.learningFocus = nil
        learningFeedback = text("正在换一种方式讲解…", "Trying another explanation…")
        persistLearningFlow()
        send(action: .guidedLearning, question: alternativeExplanationPrompt())
    }

    func reportFoundationStillUnclear() {
        learningLoadingAction = .prerequisiteExplanation
        session.learningMetadata.needsReviewFlow.learningFocus = nil
        learningFeedback = text("正在降低一个难度层级…", "Stepping back to a prerequisite…")
        persistLearningFlow()
        send(action: .guidedLearning, question: text(
            "我还是不懂。不要只换措辞，请判断缺失的前置知识并退回一个难度层级，用一个最小例子重新教。不要给原题答案。结尾重新输出 LEARNING_FOCUS 协议。",
            "I still do not understand. Do not merely rephrase; identify the missing prerequisite, step back one level, and reteach with one minimal example. Do not reveal the original answer. Re-emit LEARNING_FOCUS."
        ))
    }

    func startMicroCheck() {
        let usesRecoveredContext = session.learningMetadata.needsReviewFlow.learningFocus == nil
        if usesRecoveredContext {
            session.learningMetadata.needsReviewFlow.learningFocus = recoveredLearningFocus()
        }
        errorMessage = nil
        learningLoadingAction = .microCheck
        session.learningMetadata.needsReviewFlow.stage = .microCheck
        session.learningMetadata.needsReviewFlow.microCheck = nil
        let isEnglishFlow = session.learningMetadata.needsReviewFlow.gap == .englishReading
        learningFeedback = isEnglishFlow
            ? text("英文辅助 · 含义检查 3/4", "English support · Meaning check 3/4")
            : usesRecoveredContext
                ? text("正在根据刚才的讲解补建教学焦点并生成检查题…", "Recovering the teaching focus from the explanation and generating a check…")
                : text("不会题学习 · 微型检查 2/3", "Review learning · Quick check 2/3")
        persistLearningFlow()
        send(action: .guidedLearning, question: text(
            isEnglishFlow
                ? "只检查以下教学焦点的英文含义，不要考 SAT 解题逻辑：\n\(learningFocusContext())\n生成一道非常短的中文 A/B/C/D 含义选择题。\(microCheckProtocolInstruction())"
                : "只检查以下教学焦点，不要考原题答案：\n\(learningFocusContext())\n生成一道非常短的 A/B/C/D 概念检查题。\(microCheckProtocolInstruction())",
            isEnglishFlow
                ? "Check only whether I understood the English sentence, not SAT solving logic, and do not reveal the original answer. Create a very short Chinese A/B/C/D meaning check using the required MICRO_CHECK protocol."
                : "Create one very short A/B/C/D check for the single concept just taught. End with exactly: MICRO_CHECK, Question:, A./B./C./D., Answer: letter, END_MICRO_CHECK."
        ))
    }

    func answerMicroCheck(_ choice: String) {
        guard let check = session.learningMetadata.needsReviewFlow.microCheck else { return }
        session.learningMetadata.needsReviewFlow.microCheckAttempts += 1
        let isCorrect = choice == check.correctAnswer
        session.learningMetadata.needsReviewFlow.completedMicroChecks.append(
            SATMicroCheckAttempt(check: check, selectedAnswer: choice, wasCorrect: isCorrect)
        )
        if isCorrect {
            if session.learningMetadata.needsReviewFlow.gap == .englishReading {
                session.learningMetadata.needsReviewFlow.stage = .returnToOriginal
                learningFeedback = text("含义检查通过。下一步回到原题，只分析题目要求。", "Meaning check passed. Return to the original question next.")
            } else {
                session.learningMetadata.needsReviewFlow.stage = .easyPractice
                learningFeedback = text("微型检查正确。下一步做一道简单同类题。", "Quick check passed. Next, try an easier SAT question.")
            }
        } else {
            learningLoadingAction = .alternativeExplanation
            session.learningMetadata.needsReviewFlow.stage = .foundation
            session.learningMetadata.needsReviewFlow.learningFocus = nil
            learningFeedback = text("这一步还没掌握，我会针对这个错误再讲一次。", "This step needs more work. Let's reteach the exact error.")
            send(action: .guidedLearning, question: text("我在教学检查中选择了 \(choice)，正确答案是 \(check.correctAnswer)。只纠正这个理解错误，再给一个更简单的例子；不要讨论原题答案。", "I chose \(choice) in the learning check; the correct answer is \(check.correctAnswer). Correct only this misunderstanding with a simpler example; do not discuss the original answer."))
        }
        persistLearningFlow()
    }

    func continueWithOriginalQuestion() {
        learningLoadingAction = .foundation
        session.learningMetadata.needsReviewFlow.stage = .originalQuestion
        learningFeedback = text("英文辅助 · 回到原题 4/4", "English support · Original question 4/4")
        persistLearningFlow()
        send(action: .guidedLearning, question: text(
            "现在我已经读懂英文。请回到原题，只说明题目在问什么、应该寻找哪类证据或使用哪种方法。先不要直接公布正确选项，让我自己再尝试一次。",
            "I now understand the English. Return to the original question and explain only what it asks and what evidence or method to use. Do not reveal the correct option yet; let me try again."
        ))
    }

    private func foundationPrompt(for gap: SATLearningGap) -> String {
        let task: String
        switch gap {
        case .englishReading:
            task = englishBarrierPrompt()
        case .comprehension:
            task = text("只用自己的话解释题干要求、输入信息和我要找的结果；不要讲考点或判断选项。", "Paraphrase only the task, given information, and required result; do not teach the skill or judge choices.")
        case .concept:
            task = text("指出唯一核心考点、一个前置知识和一条规则，并给一个与原题无关的极短例子。", "Identify the single core skill, one prerequisite, and one rule, with a tiny unrelated example.")
        case .application:
            task = text("假设我已经知道概念，只示范如何从题干识别触发信号并选择第一步；不要重复定义。", "Assume I know the concept. Show how to recognize the trigger and choose the first step; do not repeat definitions.")
        case .explanationStillUnclear:
            task = text("不要复述上一份解析。改用更简单的表示方式，只解释最可能断裂的一步。", "Do not repeat the prior explanation. Use a simpler representation and reteach only the likely broken step.")
        case .aiDiagnose:
            task = text("先根据对话判断我卡在语言、题意、概念还是应用，然后只教授最可能的一个缺口，并明确说明诊断。", "Diagnose whether the blocker is language, task meaning, concept, or application, then teach only the most likely gap and state the diagnosis.")
        }
        return task + "\n\n" + learningFocusProtocolInstruction()
    }

    private func englishBarrierPrompt() -> String {
        switch session.learningMetadata.needsReviewFlow.englishBarrier {
        case .vocabulary:
            return text("只选出真正阻碍理解的 3–5 个词，结合原句解释含义和作用，不要整段翻译。", "Explain only 3–5 words that block comprehension, in context; do not translate the whole passage.")
        case .sentenceStructure:
            return text("只处理最难的一句：标出主干、从句和修饰关系，再给自然中文意译和简单英文改写。", "Handle only the hardest sentence: mark its core, clauses, and modifiers, then give a natural Chinese translation and simple English paraphrase.")
        case .answerChoices:
            return text("逐项意译选项并解释关键措辞，但绝对不要判断、排除或暗示任何选项正误。", "Paraphrase each choice and explain key wording, but never judge, eliminate, or imply correctness.")
        case .wholePassage:
            return text("按两到四个语义块说明每块在做什么，再用一句中文概括逻辑链；不要解题。", "Explain the passage in two to four meaning chunks and summarize its logic in one Chinese sentence; do not solve.")
        case nil:
            return text("定位最影响理解的一处英文并进行最小必要解释，不要解题。", "Find the single biggest English barrier and explain only what is necessary; do not solve.")
        }
    }

    private func alternativeExplanationPrompt() -> String {
        text(
            "围绕同一个教学焦点换一种表示方式：优先使用更短句、对比例子或步骤图式。不要扩大范围，不要给原题答案。结尾重新输出 LEARNING_FOCUS 协议。",
            "Reteach the same focus using shorter language, a contrast example, or a step pattern. Do not broaden scope or reveal the original answer. Re-emit the LEARNING_FOCUS protocol."
        )
    }

    func applyNeedsReviewResponse(_ raw: String, action: TutorAction) -> String {
        guard action == .guidedLearning else { return raw }
        let focusResult = SATLearningFocus.extract(from: raw)
        if let focus = focusResult.focus {
            session.learningMetadata.needsReviewFlow.learningFocus = focus
            persistLearningFlow()
        }
        let content = focusResult.body
        if session.learningMetadata.needsReviewFlow.stage == .foundation,
           session.learningMetadata.needsReviewFlow.learningFocus == nil {
            learningFeedback = text("讲解已显示，但教学焦点没有确认；请换种方式讲或重试。", "The explanation is visible, but its learning focus was not confirmed. Reteach or retry.")
            errorMessage = text("教学焦点格式无效。", "The learning-focus format was invalid.")
        }
        let containsMicroCheckProtocol = content.contains("MICRO_CHECK") && content.contains("END_MICRO_CHECK")
        guard session.learningMetadata.needsReviewFlow.stage == .microCheck || containsMicroCheckProtocol else { return content }
        if containsMicroCheckProtocol {
            session.studyStatus = .needsReview
            session.learningMetadata.needsReviewFlow.stage = .microCheck
        }
        let extracted = SATMicroCheck.extract(from: content)
        guard let check = extracted.check else {
            session.learningMetadata.needsReviewFlow.microCheck = nil
            learningFeedback = text("微型检查生成失败，请在这里重新生成。", "Quick check generation failed. Regenerate it here.")
            errorMessage = text("微型检查格式无效，请重试。", "The quick check was malformed. Try again.")
            persistLearningFlow()
            return text("微型检查暂未生成成功，可以在学习操作台中重新生成。", "The quick check was not generated. Regenerate it in the learning dock.")
        }
        session.learningMetadata.needsReviewFlow.microCheck = check
        persistLearningFlow()
        return extracted.body
    }

    private func persistLearningFlow() {
        session.updatedAt = Date()
        objectWillChange.send()
        saveLearningState(errorMessage: text("学习进度保存失败。", "Failed to save learning progress."))
    }

    private func feedback(for nextStep: SATLearningNextStep?) -> String? {
        switch nextStep {
        case .scheduleVerification(let date):
            return text("已标记为待验证，\(date.formatted(date: .abbreviated, time: .omitted))复习。", "Marked for verification on \(date.formatted(date: .abbreviated, time: .omitted)).")
        case .teachFoundation:
            return text("将先补基础，再安排一道简单同类题。", "TutorClip will teach the foundation, then give an easier question.")
        case .analyzeMistake:
            return text("请选择错因，随后分析错误并安排变式题。", "Choose an error reason, then review the mistake and a variant question.")
        case .stableMastery(let date):
            return text("已稳定掌握，\(date.formatted(date: .abbreviated, time: .omitted))抽查。", "Mastered; scheduled for a check on \(date.formatted(date: .abbreviated, time: .omitted)).")
        case nil:
            return nil
        }
    }

    func setErrorReason(_ reason: SATErrorReason) {
        let needsReviewSchedule = session.studyStatus != .mistake
            || session.learningMetadata.nextReviewAt == nil
        session.learningMetadata.errorReason = reason
        session.studyStatus = .mistake
        if needsReviewSchedule {
            SATReviewScheduler.apply(status: .mistake, to: &session.learningMetadata)
        }
        session.updatedAt = Date()
        objectWillChange.send()
        saveLearningState(errorMessage: text("错因保存失败。", "Failed to save the error reason."))
        send(action: .customQuestion, question: text(
            "这是我的错题，确认错因是“\(reason.title(language: language))”。请解释我可能怎样掉进这个错误、正确证据或解法是什么、下次如何识别，并在结尾建议一道同技能变式题。",
            "This is a mistake. The confirmed reason is \(reason.title(language: language)). Explain the error path, the correct evidence or method, how to avoid it, and recommend a same-skill variant."
        ))
    }

    func selectAnswer(_ answer: String) {
        let result = TutorSessionMutation.selectAnswer(answer, in: session)
        applyGuidedAnswerResult(result)
        objectWillChange.send()
        saveLearningState(errorMessage: text("答案状态保存失败。", "Failed to save answer state."))
    }

    private func applyGuidedAnswerResult(_ result: TutorSessionMutation.AnswerSelectionResult) {
        let flow = session.learningMetadata.needsReviewFlow
        if flow.stage == .originalQuestion {
            applyOriginalQuestionResult(result)
            return
        }
        guard flow.stage == .pendingVerification else { return }
        let role = flow.questionChain.last?.role
        switch (role, result) {
        case (.verification, .correct):
            session.learningMetadata.needsReviewFlow.stage = .scheduled
            learningFeedback = text("原难度验证通过，系统会按掌握状态安排下一次抽查。", "Original-difficulty verification passed. The next check will follow your mastery state.")
        case (.verification, .incorrect):
            returnToFoundationAfterFailedPractice(
                text("原难度验证还未通过，先针对这个卡点再巩固。", "Verification was not passed. Reinforce this gap before trying again.")
            )
        case (.easyPractice, .correct):
            learningFeedback = text("基础题已通过。现在挑战原难度，或按计划稍后验证。", "Easy practice passed. Try the original difficulty now or verify later.")
        case (.easyPractice, .incorrect):
            returnToFoundationAfterFailedPractice(
                text("简单题还未通过，先回到基础讲解。", "The easier question was not passed. Return to the foundation step.")
            )
        default:
            break
        }
    }

    private func applyOriginalQuestionResult(_ result: TutorSessionMutation.AnswerSelectionResult) {
        switch result {
        case .correct:
            session.learningMetadata.needsReviewFlow.stage = .pendingVerification
            learningFeedback = text("原题已做对；由于使用过英文辅助，稍后再用一道独立题验证。", "Original question passed. Because English support was used, verify independently with another question.")
        case .incorrect:
            session.studyStatus = .needsReview
            session.learningMetadata.needsReviewFlow.gap = .application
            session.learningMetadata.needsReviewFlow.stage = .planReady
            learningFeedback = text("英文障碍已排除；现在针对解题应用补基础。", "The English barrier is resolved. Now work on applying the SAT skill.")
        case .selected, .locked:
            break
        }
    }

    private func returnToFoundationAfterFailedPractice(_ feedback: String) {
        session.studyStatus = .needsReview
        session.learningMetadata.needsReviewFlow.stage = .foundation
        session.learningMetadata.needsReviewFlow.learningFocus = nil
        learningFeedback = feedback
    }

    func startAnswerRetry() {
        TutorSessionMutation.beginUnscoredRetry(in: session)
        learningFeedback = text("已开始第二次尝试；本次不会覆盖首次成绩。", "Second attempt started; it will not replace the first result.")
        objectWillChange.send()
        saveLearningState(errorMessage: text("重试状态保存失败。", "Failed to save retry state."))
    }

    func confirmCorrectAnswer(_ answer: String) {
        session.correctAnswer = answer
        session.learningMetadata.answerConfidence = 1
        session.learningMetadata.correctAnswerUserConfirmed = true
        session.learningMetadata.pendingHintUsed = true
        session.learningMetadata.answerSubmissionOpen = true
        session.selectedAnswer = nil
        learningFeedback = text("正确答案已由你确认，请重新作答；本次按有提示作答记录。", "Correct answer confirmed. Answer again; this attempt will be marked hint-assisted.")
        objectWillChange.send()
        saveLearningState(errorMessage: text("正确答案保存失败。", "Failed to save the corrected answer."))
    }

    func startImmediateVerification() {
        learningLoadingAction = .verification
        let originalDifficulty = session.learningMetadata.needsReviewFlow.originalDifficulty
        let targetDifficulty = originalDifficulty == .unknown
            ? session.learningMetadata.difficulty
            : originalDifficulty
        generatePracticeQuestion(
            teachingPurposeOverride: .verification,
            difficultyOverride: targetDifficulty
        )
    }

    func startFoundationPractice() {
        learningLoadingAction = .easyPractice
        session.learningMetadata.needsReviewFlow.stage = .easyPractice
        generatePracticeQuestion(
            teachingPurposeOverride: .guidedRecovery,
            difficultyOverride: .easy
        )
    }

    func startMistakeVariant() {
        generatePracticeQuestion()
    }

    func saveLearningState(errorMessage: String) {
        masteryEvidenceStore?.record(
            session: session,
            enabled: settingsStore.settings.learningProgressEnabled
        ) { [weak self] success in
            guard let self, !success else { return }
            self.errorMessage = errorMessage
        }
        historyStore.save(
            session: session,
            detailedHistoryEnabled: settingsStore.settings.historyEnabled,
            learningProgressEnabled: settingsStore.settings.learningProgressEnabled
        ) { [weak self] success in
            guard let self, !success else { return }
            self.errorMessage = errorMessage
        }
    }
}
