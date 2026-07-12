import SwiftUI

struct AnswerSummaryCard: View {
    let summary: AnswerSummary
    let language: AppLanguage

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(language.text("答案", "Answer"))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                Text(summary.answer)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(.teal)
                    .lineLimit(1)
                Spacer()
            }
            if !summary.reason.isEmpty {
                labeledLine(language.text("理由", "Reason"), summary.reason)
            }
            if !summary.evidence.isEmpty {
                labeledLine(language.text("证据", "Evidence"), summary.evidence)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.teal.opacity(0.10))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.teal.opacity(0.16), lineWidth: 1)
        )
    }

    private func labeledLine(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(label)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: language == .chinese ? 32 : 56, alignment: .leading)
            Text(value)
                .font(.system(size: 13))
                .foregroundStyle(.primary)
                .lineLimit(2)
                .truncationMode(.tail)
        }
    }
}

struct MessageBubble: View {
    let message: ChatMessage
    let language: AppLanguage

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(message.role == .user ? language.text("你", "You") : "SAT Tutor")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
            ChatMessageContentText(message: message)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(message.role == .user ? Color.teal.opacity(0.12) : Color.primary.opacity(0.045))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.primary.opacity(message.role == .user ? 0.04 : 0.055), lineWidth: 1)
        )
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct VocabularyCardsPanel: View {
    let cards: [VocabularyCard]
    let language: AppLanguage

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(language.text("词汇卡片", "Vocabulary Cards"))
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)
            ForEach(cards) { card in
                VStack(alignment: .leading, spacing: 5) {
                    Text(card.term)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.primary)
                    if !card.meaning.isEmpty {
                        labeledVocabularyLine(language.text("文中", "Context"), card.meaning)
                            .font(.system(size: 13))
                            .foregroundStyle(.teal)
                    }
                    if !card.note.isEmpty {
                        labeledVocabularyLine(language.text("释义", "Meaning"), card.note)
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                    if let example = card.example, !example.isEmpty {
                        labeledVocabularyLine(language.text("例句", "Example"), example)
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                    if !card.source.isEmpty {
                        labeledVocabularyLine(language.text("原文", "Source"), card.source)
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.primary.opacity(0.04))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
        }
        .padding(12)
        .background(Color.teal.opacity(0.07))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.teal.opacity(0.12), lineWidth: 1)
        )
    }

    private func labeledVocabularyLine(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            Text("\(label)：").fontWeight(.semibold)
            Text(value)
        }
    }
}

struct StudyStatusControl: View {
    @ObservedObject var viewModel: TutorViewModel
    @State private var showsMetadata = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(viewModel.session.studyStatus.title(language: viewModel.language))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                statusButton(.known)
                statusButton(.needsReview)
                statusButton(.mistake)
                Spacer(minLength: 8)
                Menu {
                ForEach(SATErrorReason.allCases.filter { $0 != .unknown }) { reason in
                    Button(reason.title(language: viewModel.language)) { viewModel.setErrorReason(reason) }
                }
                } label: {
                    Text(viewModel.session.learningMetadata.errorReason?.title(language: viewModel.language) ?? viewModel.text("错因", "Reason"))
                }
                .menuStyle(.borderlessButton)
                .frame(maxWidth: 120)
                Button {
                    showsMetadata.toggle()
                } label: {
                    Image(systemName: showsMetadata ? "chevron.up" : "tag")
                }
                .buttonStyle(ChromeButtonStyle())
                .help(viewModel.text("题目标签", "Question Metadata"))
            }
            if showsMetadata {
                metadataEditor
            }
            if viewModel.session.studyStatus != .needsReview, let feedback = viewModel.learningFeedback {
                HStack {
                    Text(feedback).font(.system(size: 11)).foregroundStyle(.secondary)
                    Spacer()
                    switch viewModel.session.studyStatus {
                    case .known:
                        Button(viewModel.text("立即验证", "Verify Now")) { viewModel.startImmediateVerification() }
                    case .needsReview:
                        EmptyView()
                    case .mistake:
                        Button(viewModel.text("错题变式", "Mistake Variant")) { viewModel.startMistakeVariant() }
                    case .unreviewed:
                        EmptyView()
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var metadataEditor: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Picker("", selection: Binding(get: { viewModel.session.learningMetadata.section }, set: viewModel.updateSATSection)) {
                    Text(SATSection.readingWriting.rawValue).tag(SATSection.readingWriting)
                    Text(SATSection.unknown.rawValue).tag(SATSection.unknown)
                }
                .frame(width: 150)
                Picker("", selection: Binding(get: { viewModel.session.learningMetadata.difficulty }, set: viewModel.updateSATDifficulty)) {
                    ForEach(SATDifficulty.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .frame(width: 100)
                if viewModel.session.learningMetadata.isAIGenerated {
                    Text(viewModel.text("AI 生成", "AI Generated"))
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            HStack(spacing: 8) {
                metadataField(viewModel.text("领域", "Domain"), value: Binding(get: { viewModel.session.learningMetadata.domain }, set: viewModel.updateSATDomain))
                metadataField(viewModel.text("技能", "Skill"), value: Binding(get: { viewModel.session.learningMetadata.skill }, set: viewModel.updateSATSkill))
            }
        }
        .padding(.top, 2)
    }

    private func metadataField(_ placeholder: String, value: Binding<String>) -> some View {
        TextField(placeholder, text: value)
            .textFieldStyle(.roundedBorder)
            .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func statusButton(_ status: StudyStatus) -> some View {
        if viewModel.session.studyStatus == status {
            Button(status.title(language: viewModel.language)) {
                viewModel.setStudyStatus(status)
            }
            .buttonStyle(PrimaryCapsuleButtonStyle())
            .accessibilityIdentifier("studyStatus.\(status.rawValue)")
        } else {
            Button(status.title(language: viewModel.language)) {
                viewModel.setStudyStatus(status)
            }
            .buttonStyle(ChromeButtonStyle())
            .accessibilityIdentifier("studyStatus.\(status.rawValue)")
        }
    }
}

struct AnswerChoiceControl: View {
    @ObservedObject var viewModel: TutorViewModel
    let choices: [String]

    var body: some View {
        HStack(spacing: 8) {
            Text(viewModel.text("你的答案", "Your answer"))
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
            ForEach(choices, id: \.self) { choice in
                choiceButton(choice)
            }
            Spacer()
            if viewModel.session.correctAnswer != nil,
               !viewModel.session.learningMetadata.canAutoGradeAnswer {
                Menu(viewModel.text("答案待确认", "Verify Answer")) {
                    ForEach(choices, id: \.self) { choice in
                        Button(viewModel.text("确认 \(choice) 为正确答案", "Confirm \(choice) as Correct")) {
                            viewModel.confirmCorrectAnswer(choice)
                        }
                    }
                }
                .menuStyle(.borderlessButton)
            }
            resultText
        }
    }

    @ViewBuilder
    private func choiceButton(_ choice: String) -> some View {
        if viewModel.session.selectedAnswer == choice {
            Button(choice) {
                viewModel.selectAnswer(choice)
            }
            .buttonStyle(PrimaryCapsuleButtonStyle())
            .disabled(!viewModel.session.learningMetadata.answerSubmissionOpen)
            .accessibilityIdentifier("answer.\(choice)")
        } else {
            Button(choice) {
                viewModel.selectAnswer(choice)
            }
            .buttonStyle(ChromeButtonStyle())
            .disabled(!viewModel.session.learningMetadata.answerSubmissionOpen)
            .accessibilityIdentifier("answer.\(choice)")
        }
    }

    @ViewBuilder
    private var resultText: some View {
        if viewModel.isAnswerVerificationInProgress {
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text(viewModel.text("答案校验中", "Verifying answer"))
            }
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.secondary)
            .accessibilityIdentifier("answer.result.verifying")
        } else if let result = viewModel.answerSelectionResult {
            switch result {
            case .correct:
                Text(viewModel.text("正确", "Correct"))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.teal)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .accessibilityIdentifier("answer.result.correct")
            case .incorrect:
                HStack(spacing: 8) {
                    Text(viewModel.text("错误", "Incorrect"))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.orange)
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                        .accessibilityIdentifier("answer.result.incorrect")
                    if !viewModel.session.learningMetadata.answerSubmissionOpen,
                       viewModel.session.learningMetadata.answerAttemptNumber == 1 {
                        Button(viewModel.text("再试一次", "Try Again")) { viewModel.startAnswerRetry() }
                            .buttonStyle(ChromeButtonStyle())
                            .accessibilityIdentifier("answer.retry")
                    }
                }
            case .selected(let selected):
                Text(viewModel.text("已选择 \(selected)", "Selected \(selected)"))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            case .locked(let selected):
                Text(viewModel.text("首次答案已锁定：\(selected)", "First answer locked: \(selected)"))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct ChromeButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .focusEffectDisabled()
            .font(.system(size: 13, weight: .medium))
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .foregroundStyle(.primary)
            .padding(.horizontal, 11)
            .padding(.vertical, 6)
            .background(Color.primary.opacity(configuration.isPressed ? 0.10 : 0.055))
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .stroke(Color.primary.opacity(0.075), lineWidth: 1)
            )
    }
}

struct PrimaryCapsuleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .focusEffectDisabled()
            .font(.system(size: 13, weight: .semibold))
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(
                LinearGradient(
                    colors: [
                        Color(red: 0.00, green: 0.74, blue: 0.76),
                        Color(red: 0.00, green: 0.58, blue: 0.70)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .opacity(configuration.isPressed ? 0.82 : 1)
            )
            .clipShape(Capsule())
            .shadow(color: Color.teal.opacity(configuration.isPressed ? 0.10 : 0.20), radius: 6, y: 2)
    }
}
