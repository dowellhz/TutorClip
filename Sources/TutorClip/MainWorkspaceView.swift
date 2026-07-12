import SwiftUI

enum MainWorkspaceRoute: String, CaseIterable, Identifiable {
    case today
    case question
    case knowledge
    case history
    case vocabulary

    var id: String { rawValue }
}

@MainActor
final class MainWorkspaceRouter: ObservableObject {
    @Published var route: MainWorkspaceRoute = .today
}

struct MainWorkspaceView: View {
    @ObservedObject var tutorViewModel: TutorViewModel
    @ObservedObject var historyViewModel: HistoryViewModel
    @ObservedObject var router: MainWorkspaceRouter
    let onStartToday: () -> Void
    let onStartChallenge: () -> Void
    let onCapture: () -> Void
    let onSettings: () -> Void

    var body: some View {
        NavigationSplitView {
            List(selection: $router.route) {
                Label(text("今日学习", "Today"), systemImage: "sparkles")
                    .tag(MainWorkspaceRoute.today)
                    .accessibilityIdentifier("sidebar.today")
                Label(text("当前题目", "Question"), systemImage: "doc.text")
                    .tag(MainWorkspaceRoute.question)
                    .accessibilityIdentifier("sidebar.question")
                Label(text("知识图谱", "Knowledge"), systemImage: "point.3.connected.trianglepath.dotted")
                    .tag(MainWorkspaceRoute.knowledge)
                    .accessibilityIdentifier("sidebar.knowledge")
                Label(text("历史", "History"), systemImage: "clock.arrow.circlepath")
                    .tag(MainWorkspaceRoute.history)
                    .accessibilityIdentifier("sidebar.history")
                Label(text("生词", "Vocabulary"), systemImage: "character.book.closed")
                    .tag(MainWorkspaceRoute.vocabulary)
                    .accessibilityIdentifier("sidebar.vocabulary")
            }
            .focusable(false)
            .scrollContentBackground(.hidden)
            .background(Color(nsColor: .windowBackgroundColor))
            .navigationSplitViewColumnWidth(min: 160, ideal: 190, max: 230)
            .safeAreaInset(edge: .bottom) {
                VStack(alignment: .leading, spacing: 12) {
                    Button(action: onCapture) { Label(text("截图提问", "Capture"), systemImage: "viewfinder") }
                        .focusable(false)
                    Divider()
                    Button(action: onSettings) { Label(text("设置", "Settings"), systemImage: "gearshape") }
                        .focusable(false)
                }
                .buttonStyle(.plain)
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        } detail: {
            Group {
                switch router.route {
                case .today:
                    TodayPracticeView(
                        tutorViewModel: tutorViewModel,
                        onStart: {
                            router.route = .question
                            onStartToday()
                        },
                        onChallenge: onStartChallenge
                    )
                case .question:
                    TutorWindowView(viewModel: tutorViewModel)
                case .knowledge:
                    KnowledgeMapView(viewModel: historyViewModel)
                case .history:
                    HistoryView(viewModel: historyViewModel)
                case .vocabulary:
                    VocabularyWorkspaceView(historyViewModel: historyViewModel, language: tutorViewModel.language)
                }
            }
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .onChange(of: router.route) {
            if router.route != .question {
                tutorViewModel.session.discardScreenshot()
            }
        }
    }

    private func text(_ chinese: String, _ english: String) -> String {
        tutorViewModel.text(chinese, english)
    }
}

private struct VocabularyWorkspaceView: View {
    private enum CardFilter: String, CaseIterable, Identifiable {
        case all, due, learning, mastered
        var id: String { rawValue }
    }

    @ObservedObject var historyViewModel: HistoryViewModel
    let language: AppLanguage
    @State private var query = ""
    @State private var filter: CardFilter = .all
    @State private var answerRevealed = false
    @State private var editingCard: VocabularyCard?
    @State private var deletingCard: VocabularyCard?

    private var cards: [VocabularyCard] {
        return historyViewModel.vocabularyCards
            .filter(matchesQuery)
            .filter(matchesFilter)
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    private var dueCards: [VocabularyCard] {
        historyViewModel.vocabularyCards.filter(\.isDue).sorted { $0.nextReviewAt < $1.nextReviewAt }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            if let due = dueCards.first {
                reviewCard(due)
            }
            controls
            if historyViewModel.vocabularyCards.isEmpty {
                ContentUnavailableView(
                    language.text("还没有生词", "No vocabulary yet"),
                    systemImage: "character.book.closed",
                    description: Text(language.text("在题目中选择文字并使用“生词”即可收集。", "Select text in a question and use Vocabulary to collect it."))
                )
            } else if cards.isEmpty {
                ContentUnavailableView.search(text: query)
            } else {
                List(cards) { vocabularyRow($0) }
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .sheet(item: $editingCard) { card in
            VocabularyCardEditor(card: card, language: language) { historyViewModel.saveVocabularyCard($0) }
        }
        .confirmationDialog(
            language.text("删除这张词卡？", "Delete this vocabulary card?"),
            isPresented: Binding(get: { deletingCard != nil }, set: { if !$0 { deletingCard = nil } })
        ) {
            Button(language.text("删除", "Delete"), role: .destructive) {
                if let deletingCard { historyViewModel.deleteVocabularyCard(deletingCard) }
                deletingCard = nil
            }
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(language.text("生词", "Vocabulary")).font(.system(size: 26, weight: .bold))
            Spacer()
            Text(language.text("今日待复习 \(dueCards.count)", "\(dueCards.count) due today"))
                .foregroundStyle(dueCards.isEmpty ? Color.secondary : Color.teal)
        }
    }

    private var controls: some View {
        HStack(spacing: 10) {
            TextField(language.text("搜索单词、释义或例句", "Search words, meanings, or examples"), text: $query)
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("vocabulary.search")
            Picker("", selection: $filter) {
                Text(language.text("全部", "All")).tag(CardFilter.all)
                Text(language.text("待复习", "Due")).tag(CardFilter.due)
                Text(language.text("学习中", "Learning")).tag(CardFilter.learning)
                Text(language.text("已掌握", "Mastered")).tag(CardFilter.mastered)
            }
            .labelsHidden().frame(width: 120)
        }
    }

    private func reviewCard(_ card: VocabularyCard) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(language.text("今日复习", "Review Now")).font(.headline).foregroundStyle(.teal)
            Text(card.term).font(.system(size: 24, weight: .semibold))
            if !card.source.isEmpty { Text(card.source).foregroundStyle(.secondary) }
            if answerRevealed {
                Divider()
                Text(card.meaning).font(.system(size: 16, weight: .medium))
                if !card.note.isEmpty { Text(card.note).foregroundStyle(.secondary) }
                if let example = card.example, !example.isEmpty { Text(example).italic().foregroundStyle(.secondary) }
                HStack {
                    reviewButton(language.text("不认识", "Again"), card: card, rating: .unknown)
                    reviewButton(language.text("模糊", "Unsure"), card: card, rating: .unsure)
                    reviewButton(language.text("认识", "Known"), card: card, rating: .known, prominent: true)
                }
            } else {
                Button(language.text("显示答案", "Show Answer")) { answerRevealed = true }
                    .buttonStyle(ChromeButtonStyle())
                    .accessibilityIdentifier("vocabulary.showAnswer")
            }
        }
        .padding(16)
        .background(Color.teal.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    @ViewBuilder
    private func reviewButton(
        _ title: String, card: VocabularyCard, rating: VocabularyReviewRating, prominent: Bool = false
    ) -> some View {
        if prominent {
            Button(title) { submitReview(card, rating: rating) }
                .buttonStyle(PrimaryCapsuleButtonStyle())
                .accessibilityIdentifier(reviewIdentifier(rating))
        } else {
            Button(title) { submitReview(card, rating: rating) }
                .buttonStyle(ChromeButtonStyle())
                .accessibilityIdentifier(reviewIdentifier(rating))
        }
    }

    private func reviewIdentifier(_ rating: VocabularyReviewRating) -> String {
        switch rating {
        case .unknown: return "vocabulary.review.unknown"
        case .unsure: return "vocabulary.review.unsure"
        case .known: return "vocabulary.review.known"
        }
    }

    private func submitReview(_ card: VocabularyCard, rating: VocabularyReviewRating) {
        historyViewModel.reviewVocabularyCard(card, rating: rating)
        answerRevealed = false
    }

    private func vocabularyRow(_ card: VocabularyCard) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(card.term).font(.headline)
                Text(stateTitle(card.learningState)).font(.caption).foregroundStyle(card.learningState == .mastered ? .teal : .secondary)
                Spacer()
                Button(language.text("编辑", "Edit")) { editingCard = card }
                    .accessibilityIdentifier("vocabulary.edit.\(card.term)")
                Button(language.text("删除", "Delete"), role: .destructive) { deletingCard = card }
            }
            if !card.meaning.isEmpty { Text(card.meaning).foregroundStyle(.teal) }
            if !card.note.isEmpty { Text(card.note).foregroundStyle(.secondary) }
            if let example = card.example, !example.isEmpty { Text(example).font(.callout).foregroundStyle(.secondary) }
            HStack {
                Text(language.text("复习 \(card.reviewCount) 次", "Reviewed \(card.reviewCount) times"))
                if card.sourceSessionID != nil {
                    Button(language.text("打开原题", "Open Source")) { historyViewModel.openVocabularySource(card) }
                        .buttonStyle(.link)
                }
            }
            .font(.caption).foregroundStyle(.secondary)
        }
        .padding(.vertical, 6)
    }

    private func matchesQuery(_ card: VocabularyCard) -> Bool {
        VocabularyCardSearch.matches(card, query: query)
    }

    private func matchesFilter(_ card: VocabularyCard) -> Bool {
        switch filter {
        case .all: return true
        case .due: return card.isDue
        case .learning: return card.learningState == .learning
        case .mastered: return card.learningState == .mastered
        }
    }

    private func stateTitle(_ state: VocabularyLearningState) -> String {
        switch state {
        case .new: return language.text("新词", "New")
        case .learning: return language.text("学习中", "Learning")
        case .mastered: return language.text("已掌握", "Mastered")
        }
    }
}

enum VocabularyCardSearch {
    static func matches(_ card: VocabularyCard, query: String) -> Bool {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return true }
        return [card.term, card.meaning, card.note, card.example ?? ""]
            .contains { $0.localizedCaseInsensitiveContains(needle) }
    }
}

private struct VocabularyCardEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State private var draft: VocabularyCard
    let language: AppLanguage
    let onSave: (VocabularyCard) -> Void

    init(card: VocabularyCard, language: AppLanguage, onSave: @escaping (VocabularyCard) -> Void) {
        _draft = State(initialValue: card)
        self.language = language
        self.onSave = onSave
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(language.text("编辑词卡", "Edit Vocabulary Card")).font(.title2.bold())
            TextField(language.text("单词或短语", "Word or phrase"), text: $draft.term)
                .accessibilityIdentifier("vocabulary.editor.term")
            TextField(language.text("文中含义", "Meaning in context"), text: $draft.meaning)
                .accessibilityIdentifier("vocabulary.editor.meaning")
            TextField(language.text("一般释义", "General meaning"), text: $draft.note)
            TextField(language.text("例句", "Example"), text: Binding(get: { draft.example ?? "" }, set: { draft.example = $0 }))
            TextField(language.text("原文", "Source"), text: $draft.source)
            HStack {
                Spacer()
                Button(language.text("取消", "Cancel")) { dismiss() }
                Button(language.text("保存", "Save")) {
                    draft.updatedAt = Date()
                    onSave(draft)
                    dismiss()
                }
                .buttonStyle(PrimaryCapsuleButtonStyle())
                .disabled(draft.term.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityIdentifier("vocabulary.editor.save")
            }
        }
        .textFieldStyle(.roundedBorder)
        .padding(22)
        .frame(width: 520)
    }
}

private struct TodayPracticeView: View {
    @ObservedObject var tutorViewModel: TutorViewModel
    let onStart: () -> Void
    let onChallenge: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(tutorViewModel.text("今日学习", "Today Practice"))
                .font(.system(size: 30, weight: .bold))
            Text(tutorViewModel.text(
                "TutorClip 会根据知识掌握证据、到期复习和最近错误，选择此刻最值得完成的一题。",
                "TutorClip chooses the most valuable next question from mastery evidence, due review, and recent mistakes."
            ))
            .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 8) {
                if tutorViewModel.isDailyPracticeComplete {
                    Label(
                        tutorViewModel.text("今天的计划已完成", "Today's plan is complete"),
                        systemImage: "checkmark.circle.fill"
                    )
                    .font(.headline)
                    .foregroundStyle(.teal)
                    Text(tutorViewModel.text(
                        "已安排的学习和复习都完成了。你可以到此为止，也可以做一道可选挑战题。",
                        "Scheduled learning and review are complete. You can stop here or try an optional challenge."
                    ))
                    .foregroundStyle(.secondary)
                    Button(tutorViewModel.text("可选挑战题", "Optional challenge"), action: onChallenge)
                        .buttonStyle(.bordered)
                        .accessibilityIdentifier("today.optionalChallenge")
                } else if tutorViewModel.isStreaming {
                    HStack { ProgressView(); Text(tutorViewModel.text("正在准备题目…", "Preparing question…")) }
                } else if let error = tutorViewModel.errorMessage {
                    Text(error).foregroundStyle(.red)
                    Button(tutorViewModel.text("打开当前题目并重试", "Open question and retry"), action: onStart)
                } else {
                    Text(tutorViewModel.session.title).font(.headline)
                    Button(tutorViewModel.text("开始这一题", "Start this question"), action: onStart)
                        .buttonStyle(.borderedProminent)
                        .tint(.teal)
                        .accessibilityIdentifier("today.startQuestion")
                }
            }
            .padding(16)
            .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 12))
            Spacer()
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
