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

    private func labeledVocabularyLine(_ label: String, _ value: String) -> Text {
        Text("\(label)：").fontWeight(.semibold) + Text(value)
    }
}

struct StudyStatusControl: View {
    @ObservedObject var viewModel: TutorViewModel

    var body: some View {
        HStack(spacing: 8) {
            Text(viewModel.session.studyStatus.title(language: viewModel.language))
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
            Spacer()
            statusButton(.known)
            statusButton(.needsReview)
            statusButton(.mistake)
        }
    }

    @ViewBuilder
    private func statusButton(_ status: StudyStatus) -> some View {
        if viewModel.session.studyStatus == status {
            Button(status.title(language: viewModel.language)) {
                viewModel.setStudyStatus(status)
            }
            .buttonStyle(PrimaryCapsuleButtonStyle())
        } else {
            Button(status.title(language: viewModel.language)) {
                viewModel.setStudyStatus(status)
            }
            .buttonStyle(ChromeButtonStyle())
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
        } else {
            Button(choice) {
                viewModel.selectAnswer(choice)
            }
            .buttonStyle(ChromeButtonStyle())
        }
    }

    @ViewBuilder
    private var resultText: some View {
        if let result = viewModel.answerSelectionResult {
            switch result {
            case .correct:
                Text(viewModel.text("正确", "Correct"))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.teal)
            case .incorrect(_, let correct):
                Text(viewModel.text("错误，答案 \(correct)", "Incorrect, answer \(correct)"))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.orange)
            case .selected(let selected):
                Text(viewModel.text("已选择 \(selected)", "Selected \(selected)"))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct ChromeButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
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
