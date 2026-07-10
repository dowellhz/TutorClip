import SwiftUI

struct TutorWindowView: View {
    @ObservedObject var viewModel: TutorViewModel
    @State private var sourceTextEditing = false
    private let chatBottomID = "chat-bottom"
    private let panelCornerRadius: CGFloat = 16

    var body: some View {
        VStack(spacing: 0) {
            header
            horizontalDivider
            HStack(spacing: 0) {
                TutorSourcePanel(viewModel: viewModel, sourceTextEditing: $sourceTextEditing)
                    .frame(minWidth: 480)
                verticalDivider
                chatPanel
                    .frame(minWidth: 380)
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
        ZStack {
            Color(nsColor: .windowBackgroundColor).opacity(0.96)
            Color.white.opacity(0.035)
        }
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
                StudyStatusControl(viewModel: viewModel)
                    .padding(.horizontal, 16)
                    .padding(.top, 4)
                    .padding(.bottom, 10)
                horizontalDivider
            }

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        if viewModel.session.messages.isEmpty {
                            emptyChat
                        }
                        if !viewModel.session.vocabularyCards.isEmpty {
                            VocabularyCardsPanel(cards: viewModel.session.vocabularyCards, language: viewModel.language)
                        }
                        ForEach(viewModel.session.messages) { message in
                            MessageBubble(message: message, language: viewModel.language)
                        }
                        Color.clear
                            .frame(height: 1)
                            .id(chatBottomID)
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .onChange(of: chatScrollSignal) {
                    scrollChatToBottom(proxy)
                }
                .onAppear {
                    scrollChatToBottom(proxy, animated: false)
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

    private var chatScrollSignal: String {
        guard let last = viewModel.session.messages.last else {
            return "empty"
        }
        return "\(viewModel.session.messages.count)-\(last.id.uuidString)-\(last.content.count)"
    }

    private func scrollChatToBottom(_ proxy: ScrollViewProxy, animated: Bool = true) {
        DispatchQueue.main.async {
            if animated {
                withAnimation(.easeOut(duration: 0.16)) {
                    proxy.scrollTo(chatBottomID, anchor: .bottom)
                }
            } else {
                proxy.scrollTo(chatBottomID, anchor: .bottom)
            }
        }
    }
}
