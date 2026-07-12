import SwiftUI

struct TutorSourcePanel: View {
    @ObservedObject var viewModel: TutorViewModel
    @Binding var sourceTextEditing: Bool

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            divider
            content
            divider
            actionBar
        }
    }

    private var toolbar: some View {
        HStack {
            if viewModel.session.learningMetadata.isAIGenerated {
                Text(SourceViewMode.text.title(language: viewModel.language))
                    .font(.headline)
            } else {
                Picker("", selection: $viewModel.viewMode) {
                    ForEach(SourceViewMode.allCases) { mode in
                        Text(mode.title(language: viewModel.language)).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 168)
            }

            Spacer()

            if !viewModel.session.learningMetadata.needsReviewFlow.questionChain.isEmpty {
                Menu(viewModel.viewedQuestionSnapshot?.role.title(language: viewModel.language) ?? viewModel.text("当前题目", "Current Question")) {
                    Button(viewModel.text("当前题目", "Current Question")) { viewModel.viewQuestionSnapshot(nil) }
                    Divider()
                    ForEach(viewModel.session.learningMetadata.needsReviewFlow.questionChain) { snapshot in
                        Button(snapshot.role.title(language: viewModel.language)) { viewModel.viewQuestionSnapshot(snapshot) }
                    }
                }
                .menuStyle(.borderlessButton)
            }

            if viewModel.viewMode == .text && viewModel.viewedQuestionSnapshot == nil {
                Button(sourceTextEditing ? viewModel.text("完成", "Done") : viewModel.text("编辑", "Edit")) {
                    sourceTextEditing.toggle()
                }
                .buttonStyle(ChromeButtonStyle())
            }
            if viewModel.isViewingQuestionSnapshot {
                Text(viewModel.text("只读回看", "Read-only"))
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private var content: some View {
        if viewModel.isAdaptiveQuestionPlaceholder {
            VStack(spacing: 10) {
                if viewModel.isGeneratingPracticeQuestion { ProgressView() }
                Text(viewModel.isGeneratingPracticeQuestion
                     ? viewModel.text("正在准备下一题…", "Preparing the next question…")
                     : viewModel.text("未能生成下一题", "The next question could not be generated"))
                    .font(.system(size: 14, weight: .medium))
                Text(viewModel.isGeneratingPracticeQuestion
                     ? viewModel.text("TutorClip 正在根据你的掌握情况选择题型和难度。", "TutorClip is choosing the question type and difficulty from your mastery.")
                     : viewModel.text("可以重新生成，当前学习进度不会丢失。", "You can regenerate without losing current learning progress."))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                if !viewModel.isGeneratingPracticeQuestion {
                    Button(viewModel.text("重试生成", "Regenerate")) { viewModel.retryLastRequest() }
                        .buttonStyle(PrimaryCapsuleButtonStyle())
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if viewModel.viewMode == .text {
            VStack(spacing: 0) {
                ocrFormatBanner
                ocrQualityBanner
                if sourceTextEditing {
                    ocrEditor
                } else {
                    questionMarkdown
                }
            }
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    screenshotPreview
                }
                .padding(14)
            }
        }
    }

    private var actionBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                Button(viewModel.text("重截", "Capture")) { viewModel.recapture() }
                    .buttonStyle(ChromeButtonStyle())
                ForEach(TutorAction.sourceLeadingActions, id: \.self) { action in
                    Button(action.title(language: viewModel.language)) { viewModel.run(action: action) }
                        .buttonStyle(ChromeButtonStyle())
                        .disabled(viewModel.isViewingQuestionSnapshot)
                }
                ForEach(TutorAction.sourceTrailingActions(language: viewModel.language), id: \.self) { action in
                    actionButton(action)
                        .disabled(viewModel.isViewingQuestionSnapshot)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.015))
    }

    @ViewBuilder
    private func actionButton(_ action: TutorAction) -> some View {
        if action == .practiceSimilar {
            Button { viewModel.run(action: action) } label: {
                HStack(spacing: 6) {
                    if viewModel.isGeneratingPracticeQuestion {
                        ProgressView().controlSize(.small)
                    }
                    Text(viewModel.isGeneratingPracticeQuestion
                         ? viewModel.text("正在出题…", "Generating…")
                         : action.title(language: viewModel.language))
                }
            }
            .buttonStyle(ChromeButtonStyle())
            .disabled(viewModel.isGeneratingPracticeQuestion)
        } else if action == .explainAll {
            Button(action.title(language: viewModel.language)) { viewModel.run(action: action) }
                .buttonStyle(PrimaryCapsuleButtonStyle())
        } else {
            Button(action.title(language: viewModel.language)) { viewModel.run(action: action) }
                .buttonStyle(ChromeButtonStyle())
        }
    }

    private var screenshotPreview: some View {
        Group {
            if let image = viewModel.session.screenshotInMemory {
                ScreenshotOCRPreview(image: image)
            } else {
                Text(viewModel.text("历史记录不保存截图。", "Screenshots are not saved in history."))
                    .frame(maxWidth: .infinity, minHeight: 120)
                    .foregroundStyle(.secondary)
                    .background(Color.secondary.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
    }

    private var ocrEditor: some View {
        OCRTextView(
            text: Binding(
                get: { viewModel.session.ocrDocument.editedText },
                set: { viewModel.updateOCRText($0) }
            ),
            selectedText: $viewModel.selectedText,
            selectionRect: $viewModel.selectedTextRect,
            highlightedText: Binding(
                get: { viewModel.answerEvidence },
                set: { _ in }
            )
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .textBackgroundColor).opacity(0.22))
        .overlay(alignment: .topTrailing) {
            loadingOverlay
        }
        .overlay(alignment: .topLeading) {
            selectedTextActionBar
        }
    }

    private var questionMarkdown: some View {
        InteractiveQuestionMarkdownView(
            markdown: viewModel.visibleQuestionText,
            underlinedTexts: viewModel.viewedQuestionSnapshot == nil ? viewModel.underlinedOCRTexts : [],
            language: viewModel.language,
            selectedText: $viewModel.selectedText,
            selectionRect: $viewModel.selectedTextRect,
            onTableInteraction: viewModel.run(tableInteraction:)
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .textBackgroundColor).opacity(0.22))
        .overlay(alignment: .topTrailing) {
            loadingOverlay
        }
        .overlay(alignment: .topLeading) {
            selectedTextActionBar
        }
    }

    @ViewBuilder
    private var loadingOverlay: some View {
        if viewModel.isLoadingOCR {
            Text(viewModel.text("识别中...", "Recognizing..."))
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .padding(8)
        }
    }

    @ViewBuilder
    private var ocrFormatBanner: some View {
        if viewModel.ocrFormatState.isVisible {
            HStack(spacing: 8) {
                if viewModel.ocrFormatState == .formatting {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Circle()
                        .fill(viewModel.ocrFormatState.isError ? Color.red : Color.teal)
                        .frame(width: 7, height: 7)
                }
                Text(viewModel.ocrFormatState.message(language: viewModel.language))
                    .font(.system(size: 12))
                    .foregroundStyle(viewModel.ocrFormatState.isError ? .red : .secondary)
                    .lineLimit(2)
                Spacer()
                if viewModel.ocrFormatState.isError {
                    Button(viewModel.text("重试", "Retry")) { viewModel.formatOCR() }
                        .buttonStyle(ChromeButtonStyle())
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background((viewModel.ocrFormatState.isError ? Color.red : Color.teal).opacity(0.08))
            divider
        }
    }

    @ViewBuilder
    private var ocrQualityBanner: some View {
        if let warning = viewModel.ocrQualityWarning {
            HStack(spacing: 8) {
                Circle()
                    .fill(Color.orange)
                    .frame(width: 7, height: 7)
                Text(warning)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(Color.orange.opacity(0.08))
            divider
        }
    }

    @ViewBuilder
    private var selectedTextActionBar: some View {
        if !viewModel.selectedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            GeometryReader { geometry in
                SelectionActionBar(viewModel: viewModel)
                    .fixedSize()
                    .position(selectionActionBarPosition(in: geometry.size))
            }
            .allowsHitTesting(true)
        }
    }

    private func selectionActionBarPosition(in size: CGSize) -> CGPoint {
        let fallback = CGPoint(x: min(size.width - 130, max(130, size.width - 210)), y: 36)
        guard let rect = viewModel.selectedTextRect else { return fallback }

        let estimatedWidth: CGFloat = viewModel.language == .chinese ? 150 : 190
        let estimatedHeight: CGFloat = 44
        let margin: CGFloat = 10
        let gap: CGFloat = 12
        let x = clamp(rect.midX, min: estimatedWidth / 2 + margin, max: size.width - estimatedWidth / 2 - margin)
        let preferredY = rect.minY - estimatedHeight / 2 - gap
        let fallbackY = rect.maxY + estimatedHeight / 2 + gap
        let y = preferredY >= margin + estimatedHeight / 2 ? preferredY : fallbackY
        return CGPoint(
            x: x,
            y: clamp(y, min: estimatedHeight / 2 + margin, max: size.height - estimatedHeight / 2 - margin)
        )
    }

    private func clamp(_ value: CGFloat, min minValue: CGFloat, max maxValue: CGFloat) -> CGFloat {
        Swift.max(minValue, Swift.min(value, maxValue))
    }

    private var divider: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.08))
            .frame(height: 1)
    }
}
