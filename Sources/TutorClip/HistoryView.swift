import SwiftUI

struct HistoryView: View {
    @ObservedObject var viewModel: HistoryViewModel

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 18) {
                metric(viewModel.language.text("今日复习", "Due"), viewModel.dueCount)
                metric(viewModel.language.text("不会", "Review"), viewModel.reviewCount)
                metric(viewModel.language.text("错题", "Mistakes"), viewModel.mistakeCount)
                metric(viewModel.language.text("平均掌握", "Mastery"), viewModel.averageMastery, suffix: "%")
                Spacer()
            }
            .padding(12)
            Divider()
            HStack {
                Picker("", selection: $viewModel.workspace) {
                    ForEach(HistoryViewModel.Workspace.allCases) { workspace in
                        Text(viewModel.workspaceTitle(workspace))
                            .tag(workspace)
                            .accessibilityIdentifier("history.workspace.\(workspace.rawValue)")
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("history.workspace")
                if viewModel.workspace == .review {
                    Button(viewModel.language.text("快速 5 题", "Quick 5")) { viewModel.startReview(limit: 5) }
                        .buttonStyle(.borderedProminent)
                        .disabled(viewModel.reviewQueue.isEmpty)
                        .accessibilityIdentifier("history.quick5")
                    Button(viewModel.language.text("复习 10 题", "Review 10")) { viewModel.startReview(limit: 10) }
                        .disabled(viewModel.reviewQueue.isEmpty)
                        .accessibilityIdentifier("history.review10")
                }
            }
            .padding(12)
            if viewModel.workspace == .review { advancedFilters }
            HStack {
                TextField(viewModel.language.text("搜索 OCR 和对话", "Search OCR and conversations"), text: $viewModel.query)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityIdentifier("history.search")
                Button(
                    viewModel.isClearingHistory
                        ? viewModel.language.text("正在清空…", "Clearing…")
                        : viewModel.language.text("清空全部", "Clear All")
                ) { viewModel.clear() }
                    .disabled(viewModel.isClearingHistory || viewModel.sessions.isEmpty)
                    .accessibilityIdentifier("history.clear")
            }
            .padding(12)
            if viewModel.workspace == .history {
                Picker("", selection: $viewModel.filter) {
                ForEach(HistoryViewModel.Filter.allCases) { filter in
                    Text(viewModel.filterTitle(filter)).tag(filter)
                }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 12)
                .padding(.bottom, 10)
                advancedFilters
            }
            if !viewModel.operationStatusMessage.isEmpty {
                Text(viewModel.operationStatusMessage)
                    .font(.system(size: 12))
                    .foregroundStyle(viewModel.operationStatusIsError ? Color.red : Color.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 8)
            }
            Divider()

            contentList
        }
        .frame(minWidth: 760, minHeight: 560)
    }

    private var advancedFilters: some View {
        HStack(spacing: 8) {
            Picker(viewModel.language.text("科目", "Section"), selection: $viewModel.sectionFilter) {
                Text(viewModel.language.text("全部科目", "All Sections")).tag(SATSection?.none)
                Text(SATSection.readingWriting.rawValue).tag(Optional(SATSection.readingWriting))
            }
            Picker(viewModel.language.text("领域", "Domain"), selection: $viewModel.domainFilter) {
                Text(viewModel.language.text("全部领域", "All Domains")).tag("")
                ForEach(viewModel.availableDomains, id: \.self) { Text($0).tag($0) }
            }
            Picker(viewModel.language.text("技能", "Skill"), selection: $viewModel.skillFilter) {
                Text(viewModel.language.text("全部技能", "All Skills")).tag("")
                ForEach(viewModel.availableSkills, id: \.self) { Text($0).tag($0) }
            }
            Picker(viewModel.language.text("难度", "Difficulty"), selection: $viewModel.difficultyFilter) {
                Text(viewModel.language.text("全部难度", "All Levels")).tag(SATDifficulty?.none)
                ForEach(SATDifficulty.allCases.filter { $0 != .unknown }, id: \.self) { Text($0.rawValue).tag(Optional($0)) }
            }
            Picker(viewModel.language.text("错因", "Reason"), selection: $viewModel.errorReasonFilter) {
                Text(viewModel.language.text("全部错因", "All Reasons")).tag(SATErrorReason?.none)
                ForEach(SATErrorReason.allCases.filter { $0 != .unknown }) { Text($0.title(language: viewModel.language)).tag(Optional($0)) }
            }
            Picker(viewModel.language.text("来源", "Source"), selection: $viewModel.sourceFilter) {
                Text(viewModel.language.text("全部来源", "All Sources")).tag(HistoryViewModel.SourceFilter.all)
                Text(viewModel.language.text("截图题", "Captured")).tag(HistoryViewModel.SourceFilter.captured)
                Text(viewModel.language.text("AI 生成", "AI Generated")).tag(HistoryViewModel.SourceFilter.aiGenerated)
            }
            Picker(viewModel.language.text("时间", "Date"), selection: $viewModel.recentDays) {
                Text(viewModel.language.text("全部时间", "Any Time")).tag(Int?.none)
                Text(viewModel.language.text("近 7 天", "7 Days")).tag(Optional(7))
                Text(viewModel.language.text("近 30 天", "30 Days")).tag(Optional(30))
            }
        }
        .labelsHidden()
        .padding(.horizontal, 12)
        .padding(.bottom, 10)
    }

    @ViewBuilder
    private var contentList: some View {
        switch viewModel.workspace {
        case .skills:
            List {
                ForEach(SATKnowledgeCatalog.questionTypes) { questionType in
                    let points = viewModel.knowledgePointProfiles.filter { $0.definition.questionTypeID == questionType.id }
                    DisclosureGroup {
                        ForEach(points) { point in
                            Button { viewModel.toggleKnowledgePoint(point) } label: {
                              HStack(spacing: 8) {
                                Image(systemName: point.state == .mastered ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(knowledgeProgressColor(point.state))
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(viewModel.language.text(point.definition.titleZH, point.definition.titleEN))
                                        .foregroundStyle(knowledgeProgressColor(point.state))
                                    Text(viewModel.language.text("\(point.independentCorrectCount) 次独立答对 · \(Int(point.mastery))%", "\(point.independentCorrectCount) independent correct · \(Int(point.mastery))%"))
                                        .font(.system(size: 10)).foregroundStyle(.secondary)
                                }
                              }
                            }
                            .buttonStyle(.plain)
                        }
                    } label: {
                        let mastered = points.filter { $0.state == .mastered }.count
                        Text("\(viewModel.language.text(questionType.titleZH, questionType.titleEN))  \(mastered)/\(points.count)")
                            .font(.system(size: 14, weight: .semibold))
                    }
                }
                ForEach(viewModel.skillProfiles) { profile in
                    VStack(alignment: .leading, spacing: 5) {
                    HStack {
                        Text(profile.skill).font(.system(size: 14, weight: .semibold))
                        Spacer()
                        Button(viewModel.language.text("针对练习", "Practice")) { viewModel.practice(profile) }
                        Button(
                            viewModel.isResetting(profile)
                                ? viewModel.language.text("重置中…", "Resetting…")
                                : viewModel.language.text("重置", "Reset")
                        ) { viewModel.reset(profile) }
                            .disabled(viewModel.isResetting(profile))
                    }
                    Text([profile.domain, "\(Int(profile.mastery))%", "\(Int(profile.accuracy))% accuracy", "\(profile.questionCount) questions"].joined(separator: " · "))
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                    if let reason = profile.commonErrorReason {
                        Text(viewModel.language.text("常见错因：\(reason.title(language: viewModel.language))", "Common error: \(reason.title(language: viewModel.language))"))
                            .font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                    ProgressView(value: profile.mastery, total: 100).tint(.teal)
                    Text(viewModel.language.text("推荐难度：\(profile.recommendedDifficulty.rawValue)", "Recommended: \(profile.recommendedDifficulty.rawValue)"))
                        .font(.system(size: 10)).foregroundStyle(.secondary)
                }
                    .padding(.vertical, 5)
                }
            }
        case .review:
            sessionList(viewModel.reviewQueue)
        case .history:
            sessionList(viewModel.sessions)
        }
    }

    private func sessionList(_ sessions: [TutorSession]) -> some View {
        List {
            ForEach(sessions) { session in
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(SessionTitle.make(from: session.ocrDocument.editedText.isEmpty
                                                   ? session.title
                                                   : session.ocrDocument.editedText))
                                .font(.system(size: 14, weight: .semibold))
                                .lineLimit(1)
                            Text(session.createdAt.formatted(date: .abbreviated, time: .shortened))
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                            Text(session.category.displayName(language: viewModel.language))
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.teal)
                            Text(session.studyStatus.title(language: viewModel.language))
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.secondary)
                            HStack(spacing: 8) {
                                if !session.learningMetadata.domain.isEmpty { Text(session.learningMetadata.domain) }
                                if !session.learningMetadata.skill.isEmpty { Text(session.learningMetadata.skill) }
                                Text("\(Int(session.learningMetadata.mastery))%")
                                if let date = session.learningMetadata.nextReviewAt {
                                    Text(viewModel.language.text("复习 \(date.formatted(date: .abbreviated, time: .omitted))", "Review \(date.formatted(date: .abbreviated, time: .omitted))"))
                                }
                            }
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                            Text(session.ocrDocument.editedText)
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                            if !session.learningMetadata.attempts.isEmpty || !session.learningMetadata.reviews.isEmpty {
                                DisclosureGroup(viewModel.language.text("学习记录", "Learning Timeline")) {
                                    ForEach(session.learningMetadata.attempts.suffix(5)) { attempt in
                                        Text(viewModel.language.text(
                                            "作答 \(attempt.selectedAnswer ?? "-") · \(attempt.wasCorrect ? "正确" : "错误") · \(attempt.answeredAt.formatted(date: .abbreviated, time: .shortened))",
                                            "Answer \(attempt.selectedAnswer ?? "-") · \(attempt.wasCorrect ? "Correct" : "Wrong") · \(attempt.answeredAt.formatted(date: .abbreviated, time: .shortened))"
                                        ))
                                    }
                                    ForEach(session.learningMetadata.reviews.suffix(5)) { review in
                                        Text(viewModel.language.text(
                                            "复习状态：\(review.status.title(language: viewModel.language))",
                                            "Review: \(review.status.title(language: viewModel.language))"
                                        ))
                                    }
                                }
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        Button(viewModel.language.text("打开", "Open")) { viewModel.open(session) }
                            .accessibilityIdentifier("history.open.\(session.id.uuidString)")
                        if viewModel.workspace == .review {
                            Button(
                                viewModel.isSnoozing(session)
                                    ? viewModel.language.text("推迟中…", "Snoozing…")
                                    : viewModel.language.text("明天", "Tomorrow")
                            ) { viewModel.snooze(session) }
                                .disabled(viewModel.isSnoozing(session))
                        }
                        Button(
                            viewModel.isDeleting(session)
                                ? viewModel.language.text("删除中…", "Deleting…")
                                : viewModel.language.text("删除", "Delete")
                        ) { viewModel.delete(session) }
                            .disabled(viewModel.isDeleting(session))
                    }
                    .padding(.vertical, 6)
                }
            }
    }

    private func knowledgeProgressColor(_ state: SATMasteryState) -> Color {
        switch state {
        case .new: return .secondary
        case .learning: return .orange
        case .pendingVerification: return .blue
        case .mastered: return .teal
        }
    }

    private func metric(_ title: String, _ value: Int, suffix: String = "") -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(value)\(suffix)").font(.system(size: 20, weight: .semibold))
            Text(title).font(.system(size: 11)).foregroundStyle(.secondary)
        }
    }
}
