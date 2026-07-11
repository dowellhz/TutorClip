import SwiftUI

struct TutorWindowView: View {
    @ObservedObject var viewModel: TutorViewModel
    @State private var sourceTextEditing = false
    @State private var needsReviewDockExpanded = false
    @State private var needsReviewDockHeight: CGFloat = 0
    private let chatContentEndID = "chat-content-end"
    private let chatBottomID = "chat-bottom"
    private let panelCornerRadius: CGFloat = 16

    var body: some View {
        VStack(spacing: 0) {
            header
            horizontalDivider
            HStack(spacing: 0) {
                TutorSourcePanel(viewModel: viewModel, sourceTextEditing: $sourceTextEditing)
                    .frame(minWidth: 480)
                    .clipped()
                verticalDivider
                chatPanel
                    .frame(minWidth: 380)
                    .clipped()
            }
        }
        .background(panelBackground)
        .clipShape(RoundedRectangle(cornerRadius: panelCornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: panelCornerRadius, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
        .frame(minWidth: 900, minHeight: 620)
    }

    private var panelBackground: some View {
        Color(nsColor: .windowBackgroundColor)
    }

    private var verticalDivider: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.08))
            .frame(width: 1)
    }

    private var horizontalDivider: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.08))
            .frame(height: 1)
    }

    private var header: some View {
        HStack(spacing: 12) {
            Text("TutorClip")
                .font(.system(size: 15, weight: .semibold))
            Spacer()
            Button(viewModel.text("知识地图", "Knowledge Map")) {
                viewModel.showKnowledgeMap()
            }
            .buttonStyle(ChromeButtonStyle())
            Button(viewModel.text("设置", "Settings")) {
                viewModel.showSettings()
            }
            .buttonStyle(ChromeButtonStyle())
            if viewModel.isLoadingOCR {
                ProgressView()
                    .controlSize(.small)
                Text(viewModel.text("OCR", "OCR"))
                    .foregroundStyle(.secondary)
            } else if viewModel.isStreaming {
                ProgressView()
                    .controlSize(.small)
                Text("DeepSeek")
                    .foregroundStyle(.secondary)
            } else {
                Circle()
                    .fill(Color.teal)
                    .frame(width: 7, height: 7)
                Text("DeepSeek")
                    .foregroundStyle(.secondary)
            }
            Button("×") {
                viewModel.closeWindow()
            }
            .buttonStyle(ChromeButtonStyle())
            .focusable(false)
        }
        .padding(.horizontal, 18)
        .frame(height: 46)
        .background(Color.primary.opacity(0.015))
    }

    private var chatPanel: some View {
        VStack(spacing: 0) {
            HStack {
                Text("SAT Tutor")
                    .font(.system(size: 14, weight: .semibold))
                Spacer()
            }
            .padding(.horizontal, 16)
            .frame(height: 46)
            horizontalDivider

            if !viewModel.answerChoices.isEmpty {
                AnswerChoiceControl(viewModel: viewModel, choices: viewModel.answerChoices)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                horizontalDivider
            }

            if let summary = viewModel.answerSummary {
                AnswerSummaryCard(summary: summary, language: viewModel.language)
                    .padding(.horizontal, 16)
                    .padding(.top, 10)
            }
            if !viewModel.session.ocrDocument.editedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                StudyStatusControl(viewModel: viewModel)
                    .padding(.horizontal, 16)
                    .padding(.top, 4)
                    .padding(.bottom, 10)
                horizontalDivider
            }

            ScrollViewReader { proxy in
                ZStack(alignment: .bottomTrailing) {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 12) {
                            if currentMessages.isEmpty {
                                emptyChat
                            }
                            if !viewModel.session.vocabularyCards.isEmpty {
                                VocabularyCardsPanel(cards: viewModel.session.vocabularyCards, language: viewModel.language)
                            }
                            ForEach(learningTimeline) { entry in
                                timelineView(entry)
                            }
                            Color.clear
                                .frame(height: 1)
                                .id(chatContentEndID)
                            Color.clear
                                .frame(height: needsReviewDockExpanded ? needsReviewDockHeight + 28 : 54)
                                .id(chatBottomID)
                        }
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    if viewModel.session.studyStatus == .needsReview {
                        needsReviewDock
                            .padding(14)
                            .background(
                                GeometryReader { geometry in
                                    Color.clear.preference(key: LearningDockHeightKey.self, value: geometry.size.height)
                                }
                            )
                    }
                }
                .onPreferenceChange(LearningDockHeightKey.self) { needsReviewDockHeight = $0 }
                .onChange(of: chatScrollSignal) {
                    scrollChatToVisibleEnd(proxy)
                }
                .onAppear {
                    scrollChatToVisibleEnd(proxy, animated: false)
                }
                .onChange(of: viewModel.session.learningMetadata.needsReviewFlow.stage) {
                    withAnimation(.easeOut(duration: 0.18)) {
                        needsReviewDockExpanded = true
                    }
                }
                .onChange(of: viewModel.session.studyStatus) {
                    if viewModel.session.studyStatus == .needsReview {
                        needsReviewDockExpanded = true
                    }
                }
                .onChange(of: viewModel.isStreaming) {
                    if viewModel.isStreaming && shouldMinimizeLearningDockWhileStreaming {
                        withAnimation(.easeOut(duration: 0.18)) {
                            needsReviewDockExpanded = false
                        }
                    }
                    scrollChatToVisibleEnd(proxy, animated: false, afterLayoutDelay: 0.22)
                }
                .onChange(of: needsReviewDockExpanded) {
                    scrollChatToVisibleEnd(proxy, animated: false, afterLayoutDelay: 0.22)
                }
            }

            if let error = viewModel.errorMessage {
                HStack(spacing: 8) {
                    Text(error)
                        .font(.system(size: 12))
                        .foregroundStyle(.red)
                    Spacer()
                    Button(viewModel.text("设置", "Settings")) { viewModel.showSettings() }
                    Button(viewModel.text("重试", "Retry")) { viewModel.retryLastRequest() }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 6)
            }

            Divider()
            HStack(alignment: .bottom, spacing: 8) {
                TextField(viewModel.text("输入你的问题...", "Ask a question..."), text: $viewModel.inputText, axis: .vertical)
                    .textFieldStyle(.plain)
                    .lineLimit(1...4)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .background(Color.primary.opacity(0.045))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(Color.primary.opacity(0.07), lineWidth: 1)
                    )
                    .onSubmit { viewModel.sendCustomQuestion() }
                Button(viewModel.text("发送", "Send")) { viewModel.sendCustomQuestion() }
                    .buttonStyle(PrimaryCapsuleButtonStyle())
                    .disabled(viewModel.isStreaming)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Color.primary.opacity(0.015))
        }
    }

    @ViewBuilder
    private var needsReviewDock: some View {
        if needsReviewDockExpanded {
            VStack(alignment: .trailing, spacing: 6) {
                Button {
                    withAnimation(.easeOut(duration: 0.18)) {
                        needsReviewDockExpanded = false
                    }
                } label: {
                    Label(viewModel.text("收起学习操作台", "Collapse Learning Dock"), systemImage: "chevron.down")
                }
                .buttonStyle(ChromeButtonStyle())
                ScrollView {
                    NeedsReviewGuidanceView(viewModel: viewModel)
                }
                .frame(maxHeight: 360)
            }
            .frame(maxWidth: 560)
            .padding(8)
            .background(Color(nsColor: .windowBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.primary.opacity(0.10), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.16), radius: 10, y: 4)
        } else {
            Button {
                withAnimation(.easeOut(duration: 0.18)) {
                    needsReviewDockExpanded = true
                }
            } label: {
                if viewModel.isStreaming && shouldMinimizeLearningDockWhileStreaming {
                    ProgressView()
                        .controlSize(.small)
                        .frame(width: 18, height: 18)
                } else {
                    Label(needsReviewFloatingTitle, systemImage: "graduationcap.fill")
                }
            }
            .buttonStyle(PrimaryCapsuleButtonStyle())
            .shadow(color: .black.opacity(0.14), radius: 8, y: 3)
            .help(viewModel.isStreaming
                  ? viewModel.text("基础讲解生成中", "Generating Foundation Explanation")
                  : viewModel.text("展开学习操作台", "Expand Learning Dock"))
        }
    }

    private var shouldMinimizeLearningDockWhileStreaming: Bool {
        guard viewModel.session.learningMetadata.needsReviewFlow.stage == .foundation else { return false }
        switch viewModel.learningLoadingAction {
        case .foundation, .alternativeExplanation, .prerequisiteExplanation:
            return true
        default:
            return false
        }
    }

    private var needsReviewFloatingTitle: String {
        switch viewModel.session.learningMetadata.needsReviewFlow.stage {
        case .chooseGap:
            return viewModel.text("选择卡点", "Choose Learning Gap")
        case .chooseEnglishBarrier:
            return viewModel.text("选择英文障碍 1/4", "Choose English Barrier 1/4")
        case .planReady:
            return viewModel.text("开始不会题学习", "Start Review Learning")
        case .foundation:
            return viewModel.text("基础讲解 1/3", "Foundation 1/3")
        case .microCheck:
            return viewModel.text("微型检查 2/3", "Quick Check 2/3")
        case .easyPractice:
            return viewModel.text("简单同类题 3/3", "Easy Practice 3/3")
        case .returnToOriginal:
            return viewModel.text("回到原题 4/4", "Return to Original 4/4")
        case .originalQuestion:
            return viewModel.text("重新尝试原题", "Retry Original Question")
        case .pendingVerification:
            return viewModel.text("挑战原难度", "Try Original Difficulty")
        case .scheduled:
            return viewModel.text("查看复习计划", "View Review Plan")
        case .inactive:
            return viewModel.text("继续不会题学习", "Continue Review Learning")
        }
    }

    private var emptyChat: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(viewModel.text("选择左侧操作，或直接提问。", "Choose an action on the left, or ask directly."))
                .font(.system(size: 15, weight: .medium))
            Text(viewModel.text("TutorClip 会把 OCR 文本作为上下文交给 DeepSeek，并按 SAT 老师的方式用中文讲解。", "TutorClip sends OCR text as context to DeepSeek and explains it as an SAT tutor."))
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.045))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var learningTimeline: [LearningTimelineEntry] {
        let messages = sessionMessages.map { LearningTimelineEntry(message: $0) }
        let checks = viewModel.session.learningMetadata.needsReviewFlow.completedMicroChecks.map {
            LearningTimelineEntry(check: $0)
        }
        return (messages + checks).sorted { $0.date < $1.date }
    }

    @ViewBuilder
    private func timelineView(_ entry: LearningTimelineEntry) -> some View {
        switch entry.content {
        case .message(let message):
            MessageBubble(message: message, language: viewModel.language)
                .opacity(isArchived(message) ? 0.82 : 1)
                .transaction { transaction in
                    if viewModel.isStreaming { transaction.animation = nil }
                }
        case .check(let attempt):
            CompletedMicroCheckView(attempt: attempt, language: viewModel.language)
        }
    }

    private func isArchived(_ message: ChatMessage) -> Bool {
        guard let context = message.contextDocumentID else { return false }
        return context != viewModel.session.ocrDocument.id
    }

    private var currentMessages: [ChatMessage] {
        sessionMessages.filter { message in
            message.contextDocumentID == nil || message.contextDocumentID == viewModel.session.ocrDocument.id
        }
    }

    private var sessionMessages: [ChatMessage] {
        viewModel.session.messages
    }

    private var chatScrollSignal: String {
        guard let last = viewModel.session.messages.last else {
            return "empty"
        }
        return "\(viewModel.session.messages.count)-\(last.id.uuidString)-\(viewModel.isStreaming)"
    }

    private func scrollChatToVisibleEnd(
        _ proxy: ScrollViewProxy,
        animated: Bool = true,
        afterLayoutDelay delay: TimeInterval = 0
    ) {
        let targetID = needsReviewDockExpanded ? chatBottomID : chatContentEndID
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            if animated && !viewModel.isStreaming {
                withAnimation(.easeOut(duration: 0.16)) {
                    proxy.scrollTo(targetID, anchor: .bottom)
                }
            } else {
                proxy.scrollTo(targetID, anchor: .bottom)
            }
        }
    }
}

private struct LearningDockHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private struct LearningTimelineEntry: Identifiable {
    enum Content {
        case message(ChatMessage)
        case check(SATMicroCheckAttempt)
    }

    let id: String
    let date: Date
    let content: Content

    init(message: ChatMessage) {
        id = "message-\(message.id.uuidString)"
        date = message.createdAt
        content = .message(message)
    }

    init(check: SATMicroCheckAttempt) {
        id = "check-\(check.id.uuidString)"
        date = check.completedAt
        content = .check(check)
    }
}
