import SwiftUI

struct NeedsReviewGuidanceView: View {
    @ObservedObject var viewModel: TutorViewModel

    private var flow: SATNeedsReviewFlow { viewModel.session.learningMetadata.needsReviewFlow }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if flow.stage != .chooseGap && flow.stage != .inactive {
                HStack {
                    Spacer()
                    Button(viewModel.text("重新选择卡点", "Change Learning Gap")) { viewModel.restartNeedsReviewDiagnosis() }
                        .buttonStyle(ChromeButtonStyle())
                        .disabled(viewModel.isStreaming)
                }
            }
            if let feedback = viewModel.learningFeedback {
                Text(feedback).font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
            }
            stageContent
        }
        .padding(10)
        .background(Color.primary.opacity(0.035))
        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
    }

    @ViewBuilder
    private var stageContent: some View {
        switch flow.stage {
        case .chooseGap:
            Text(viewModel.text("你卡在哪里？", "Where are you stuck?"))
                .font(.system(size: 12, weight: .semibold))
            Button(SATLearningGap.englishReading.title(language: viewModel.language)) { viewModel.selectLearningGap(.englishReading) }
                .buttonStyle(PrimaryCapsuleButtonStyle())
                .accessibilityIdentifier("needsReview.gap.englishReading")
            gapRow([.comprehension, .concept])
            gapRow([.application, .explanationStillUnclear])
            Button(SATLearningGap.aiDiagnose.title(language: viewModel.language)) { viewModel.selectLearningGap(.aiDiagnose) }
                .buttonStyle(ChromeButtonStyle())
                .accessibilityIdentifier("needsReview.gap.aiDiagnose")
        case .chooseEnglishBarrier:
            Text(viewModel.text("英文具体卡在哪里？", "What makes the English difficult?"))
                .font(.system(size: 12, weight: .semibold))
            LazyVGrid(columns: microCheckColumns, alignment: .leading, spacing: 8) {
                ForEach(SATEnglishBarrier.allCases) { barrier in
                    Button(barrier.title(language: viewModel.language)) { viewModel.selectEnglishBarrier(barrier) }
                        .buttonStyle(ReviewChoiceButtonStyle())
                }
            }
        case .planReady:
            if let gap = flow.gap {
                Text(gap.title(language: viewModel.language)).font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Text(flow.gap == .englishReading
                 ? viewModel.text("接下来：拆解理解 → 含义检查 → 回到原题", "Next: unpack → meaning check → original question")
                 : viewModel.text("接下来：基础讲解 → 微型检查 → 简单同类题", "Next: foundation → quick check → easier question"))
                .font(.system(size: 11)).foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button(viewModel.text("稍后复习", "Review Later")) { viewModel.scheduleNeedsReviewForLater() }
                    .buttonStyle(ChromeButtonStyle())
                Button { viewModel.startNeedsReviewLearning() } label: {
                    loadingLabel(
                        action: .foundation,
                        idle: viewModel.text("开始学习", "Start Learning"),
                        loading: viewModel.text("准备讲解…", "Preparing…")
                    )
                }
                    .buttonStyle(PrimaryCapsuleButtonStyle())
                    .disabled(viewModel.isStreaming)
                    .accessibilityIdentifier("needsReview.startLearning")
            }
        case .foundation:
            Text(flow.gap == .englishReading
                 ? viewModel.text("英文辅助 · 拆解理解 2/4", "English support · Unpack 2/4")
                 : viewModel.text("不会题学习 · 基础讲解 1/3", "Review learning · Foundation 1/3"))
                .font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
            HStack {
                Button { viewModel.requestAlternativeFoundation() } label: {
                    loadingLabel(
                        action: .alternativeExplanation,
                        idle: viewModel.text("换种方式讲", "Explain Differently"),
                        loading: viewModel.text("重新讲解中…", "Reteaching…")
                    )
                }
                    .buttonStyle(ChromeButtonStyle()).disabled(viewModel.isStreaming)
                Button { viewModel.reportFoundationStillUnclear() } label: {
                    loadingLabel(
                        action: .prerequisiteExplanation,
                        idle: viewModel.text("还是不懂", "Still Unclear"),
                        loading: viewModel.text("退回基础中…", "Stepping Back…")
                    )
                }
                    .buttonStyle(ChromeButtonStyle()).disabled(viewModel.isStreaming)
                Spacer()
                Button { viewModel.startMicroCheck() } label: {
                    loadingLabel(
                        action: .microCheck,
                        idle: flow.gap == .englishReading ? viewModel.text("这句读懂了", "I Understand the Sentence") : viewModel.text("这一步懂了", "I Understand"),
                        loading: flow.gap == .englishReading ? viewModel.text("生成含义检查…", "Generating Meaning Check…") : viewModel.text("生成检查题…", "Generating Check…")
                    )
                }
                    .buttonStyle(PrimaryCapsuleButtonStyle())
                    .disabled(viewModel.isStreaming)
            }
        case .microCheck:
            Text(flow.gap == .englishReading
                 ? viewModel.text("英文辅助 · 含义检查 3/4", "English support · Meaning check 3/4")
                 : viewModel.text("不会题学习 · 微型检查 2/3", "Review learning · Quick check 2/3"))
                .font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
            if let check = flow.microCheck {
                Text(check.question)
                    .font(.system(size: 12, weight: .semibold))
                    .fixedSize(horizontal: false, vertical: true)
                LazyVGrid(columns: microCheckColumns, alignment: .leading, spacing: 8) {
                    ForEach(check.choices, id: \.self) { choice in
                        Button {
                            viewModel.answerMicroCheck(String(choice.prefix(1)))
                        } label: {
                            Text(choice)
                                .font(.system(size: 11))
                                .multilineTextAlignment(.leading)
                                .fixedSize(horizontal: false, vertical: true)
                                .frame(maxWidth: .infinity, minHeight: 34, alignment: .leading)
                        }
                        .buttonStyle(ReviewChoiceButtonStyle())
                        .disabled(viewModel.isStreaming)
                    }
                }
            } else {
                Text(viewModel.isStreaming ? viewModel.text("正在准备一道小题…", "Preparing a quick check…") : viewModel.text("微型检查没有生成成功。", "The quick check was not generated."))
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                if !viewModel.isStreaming {
                    Button(viewModel.text("重新生成微型检查", "Regenerate Quick Check")) { viewModel.startMicroCheck() }
                        .buttonStyle(PrimaryCapsuleButtonStyle())
                }
            }
        case .easyPractice:
            HStack {
                Text(viewModel.text("微型检查已通过。", "Quick check passed."))
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                Spacer()
                Button { viewModel.startFoundationPractice() } label: {
                    loadingLabel(
                        action: .easyPractice,
                        idle: viewModel.text("开始简单同类题", "Start Easy Practice"),
                        loading: viewModel.text("正在生成…", "Generating…")
                    )
                }
                    .buttonStyle(PrimaryCapsuleButtonStyle())
                    .disabled(viewModel.isStreaming)
            }
        case .scheduled:
            Text(viewModel.text("已保存进度。可从“今日复习”继续。", "Progress saved. Continue from Today's Review."))
                .font(.system(size: 11)).foregroundStyle(.secondary)
        case .pendingVerification:
            Button { viewModel.startImmediateVerification() } label: {
                loadingLabel(
                    action: .verification,
                    idle: viewModel.text("挑战原难度", "Try Original Difficulty"),
                    loading: viewModel.text("正在生成…", "Generating…")
                )
            }
                .buttonStyle(PrimaryCapsuleButtonStyle())
                .disabled(viewModel.isStreaming)
        case .returnToOriginal:
            HStack {
                Text(viewModel.text("含义检查已通过。", "Meaning check passed."))
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                Spacer()
                Button { viewModel.continueWithOriginalQuestion() } label: {
                    loadingLabel(
                        action: .foundation,
                        idle: viewModel.text("回到原题", "Return to Original"),
                        loading: viewModel.text("准备原题引导…", "Preparing Guidance…")
                    )
                }
                .buttonStyle(PrimaryCapsuleButtonStyle())
                .disabled(viewModel.isStreaming)
            }
        case .originalQuestion:
            Text(viewModel.text("英文已经读懂。请在上方选择 A/B/C/D，系统会按真实作答结果判断。", "You understand the English. Answer with A/B/C/D above so mastery is based on your result."))
                .font(.system(size: 11)).foregroundStyle(.secondary)
            HStack {
                Button(viewModel.text("还是不会做", "Still Can't Solve")) { viewModel.selectLearningGap(.application) }
                    .buttonStyle(ChromeButtonStyle())
            }
        case .inactive:
            EmptyView()
        }
    }

    private var microCheckColumns: [GridItem] {
        [
            GridItem(.flexible(minimum: 150), spacing: 8, alignment: .top),
            GridItem(.flexible(minimum: 150), spacing: 8, alignment: .top)
        ]
    }

    @ViewBuilder
    private func loadingLabel(action: LearningLoadingAction, idle: String, loading: String) -> some View {
        if viewModel.learningLoadingAction == action, viewModel.isStreaming {
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text(loading)
            }
        } else {
            Text(idle)
        }
    }

    private func gapRow(_ gaps: [SATLearningGap]) -> some View {
        HStack {
            ForEach(gaps) { gap in
                Button(gap.title(language: viewModel.language)) { viewModel.selectLearningGap(gap) }
                    .buttonStyle(ChromeButtonStyle())
                    .accessibilityIdentifier("needsReview.gap.\(gap.rawValue)")
            }
        }
    }
}

private struct ReviewChoiceButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .focusEffectDisabled()
            .foregroundStyle(.primary)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(Color.primary.opacity(configuration.isPressed ? 0.10 : 0.055))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)
            )
    }
}

struct CompletedMicroCheckView: View {
    let attempt: SATMicroCheckAttempt
    let language: AppLanguage

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label(language.text("已完成的微型检查", "Completed Quick Check"), systemImage: attempt.wasCorrect ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(attempt.wasCorrect ? Color.teal : Color.orange)
                Spacer()
                Text(language.text("选择 \(attempt.selectedAnswer)", "Selected \(attempt.selectedAnswer)"))
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            Text(attempt.check.question)
                .font(.system(size: 12, weight: .medium))
            ForEach(attempt.check.choices, id: \.self) { choice in
                Text(choice)
                    .font(.system(size: 11))
                    .foregroundStyle(choice.hasPrefix(attempt.check.correctAnswer) ? Color.teal : Color.secondary)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.035))
        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
    }
}
