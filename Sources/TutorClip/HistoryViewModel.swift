import Combine
import Foundation
@MainActor
final class HistoryViewModel: ObservableObject {
    enum Workspace: String, CaseIterable, Identifiable { case review, skills, history; var id: String { rawValue } }
    enum SourceFilter: String, CaseIterable, Identifiable { case all, captured, aiGenerated; var id: String { rawValue } }
    enum Filter: String, CaseIterable, Identifiable {
        case all, due, needsReview, mistake, known
        var id: String { rawValue }
    }
    @Published var query: String = ""
    @Published var operationStatusMessage: String = ""
    @Published var operationStatusIsError: Bool = false
    @Published private(set) var deletingSessionIDs: Set<UUID> = []
    @Published private(set) var isClearingHistory: Bool = false
    @Published var filter: Filter = .all
    @Published var workspace: Workspace = .review
    @Published var sectionFilter: SATSection?
    @Published var domainFilter = ""
    @Published var skillFilter = ""
    @Published var difficultyFilter: SATDifficulty?
    @Published var errorReasonFilter: SATErrorReason?
    @Published var sourceFilter: SourceFilter = .all
    @Published var recentDays: Int?
    private let settingsStore: SettingsStore
    private let historyStore: HistoryStore
    private let onOpen: (TutorSession) -> Void
    private let onPracticeSkill: (SATSkillProfile) -> Void
    private let onPracticeKnowledgePoint: (SATKnowledgePointProfile) -> Void
    private let onStartReview: ([TutorSession], Int) -> Void
    private var historyCancellable: AnyCancellable?
    private var masteryCancellable: AnyCancellable?

    init(settingsStore: SettingsStore, historyStore: HistoryStore, onOpen: @escaping (TutorSession) -> Void, onPracticeSkill: @escaping (SATSkillProfile) -> Void = { _ in }, onPracticeKnowledgePoint: @escaping (SATKnowledgePointProfile) -> Void = { _ in }, onStartReview: @escaping ([TutorSession], Int) -> Void = { _, _ in }) {
        self.settingsStore = settingsStore
        self.historyStore = historyStore
        self.onOpen = onOpen
        self.onPracticeSkill = onPracticeSkill
        self.onPracticeKnowledgePoint = onPracticeKnowledgePoint
        self.onStartReview = onStartReview
        historyCancellable = historyStore.$sessions.sink { [weak self] _ in self?.objectWillChange.send() }
        masteryCancellable = historyStore.$manuallyMasteredKnowledgePointIDs.sink { [weak self] _ in self?.objectWillChange.send() }
    }

    var language: AppLanguage {
        settingsStore.settings.appLanguage
    }

    var sessions: [TutorSession] {
        historyStore.search(query).filter { session in
            switch filter {
            case .all: return true
            case .due: return session.learningMetadata.isDue
            case .needsReview: return session.studyStatus == .needsReview
            case .mistake: return session.studyStatus == .mistake
            case .known: return session.studyStatus == .known
            }
        }.filter { session in
            let metadata = session.learningMetadata
            if let sectionFilter, metadata.section != sectionFilter { return false }
            if !domainFilter.isEmpty, metadata.domain != domainFilter { return false }
            if !skillFilter.isEmpty, metadata.skill != skillFilter { return false }
            if let difficultyFilter, metadata.difficulty != difficultyFilter { return false }
            if let errorReasonFilter, metadata.errorReason != errorReasonFilter { return false }
            if sourceFilter == .captured, metadata.isAIGenerated { return false }
            if sourceFilter == .aiGenerated, !metadata.isAIGenerated { return false }
            if let recentDays, session.updatedAt < Date().addingTimeInterval(-Double(recentDays) * 86_400) { return false }
            return true
        }
    }
    var availableDomains: [String] { Array(Set(historyStore.sessions.map(\.learningMetadata.domain).filter { !$0.isEmpty })).sorted() }
    var availableSkills: [String] { Array(Set(historyStore.sessions.map(\.learningMetadata.skill).filter { !$0.isEmpty })).sorted() }

    var dueCount: Int { historyStore.sessions.filter { $0.learningMetadata.isDue }.count }
    var mistakeCount: Int { historyStore.sessions.filter { $0.studyStatus == .mistake }.count }
    var reviewCount: Int { historyStore.sessions.filter { $0.studyStatus == .needsReview }.count }
    var averageMastery: Int {
        let values = historyStore.sessions.map(\.learningMetadata.mastery)
        return values.isEmpty ? 0 : Int(values.reduce(0, +) / Double(values.count))
    }
    var reviewQueue: [TutorSession] { SATLearningAnalytics.reviewQueue(from: historyStore.sessions).filter(matchesAdvancedFilters) }
    var skillProfiles: [SATSkillProfile] { SATLearningAnalytics.skillProfiles(from: historyStore.sessions) }
    var knowledgePointProfiles: [SATKnowledgePointProfile] {
        SATLearningAnalytics.knowledgePointProfiles(from: historyStore.sessions).map { profile in
            guard historyStore.manuallyMasteredKnowledgePointIDs.contains(profile.id) else { return profile }
            var updated = profile
            updated.state = .mastered
            return updated
        }
    }

    func toggleKnowledgePoint(_ profile: SATKnowledgePointProfile) {
        historyStore.setKnowledgePoint(profile.id, mastered: profile.state != .mastered)
    }

    func startReview(limit: Int) {
        guard !reviewQueue.isEmpty else {
            operationStatusMessage = language.text("今天的复习已完成。", "Today's review is complete.")
            operationStatusIsError = false
            return
        }
        onStartReview(reviewQueue, limit)
    }
    func practice(_ profile: SATSkillProfile) { onPracticeSkill(profile) }
    func practice(_ profile: SATKnowledgePointProfile) { onPracticeKnowledgePoint(profile) }
    func reset(_ profile: SATSkillProfile) {
        let matches = historyStore.sessions.filter {
            $0.learningMetadata.section == profile.section && $0.learningMetadata.domain == profile.domain && $0.learningMetadata.skill == profile.skill
        }
        for session in matches {
            let identity = (session.learningMetadata.section, session.learningMetadata.domain, session.learningMetadata.skill, session.learningMetadata.difficulty)
            session.learningMetadata = SATLearningMetadata()
            session.learningMetadata.section = identity.0
            session.learningMetadata.domain = identity.1
            session.learningMetadata.skill = identity.2
            session.learningMetadata.difficulty = identity.3
            session.studyStatus = .unreviewed
            historyStore.save(session: session, enabled: settingsStore.settings.historyEnabled)
        }
        operationStatusMessage = language.text("技能学习进度已重置。", "Skill progress reset.")
    }

    func snooze(_ session: TutorSession) {
        session.learningMetadata.nextReviewAt = Calendar.current.date(byAdding: .day, value: 1, to: Date())
        historyStore.save(session: session, enabled: settingsStore.settings.historyEnabled)
        operationStatusMessage = language.text("已推迟到明天。", "Snoozed until tomorrow.")
    }

    func workspaceTitle(_ workspace: Workspace) -> String {
        switch workspace {
        case .review: return language.text("今日复习", "Review")
        case .skills: return language.text("技能档案", "Skills")
        case .history: return language.text("全部记录", "History")
        }
    }

    private func matchesAdvancedFilters(_ session: TutorSession) -> Bool {
        let metadata = session.learningMetadata
        if let sectionFilter, metadata.section != sectionFilter { return false }
        if !domainFilter.isEmpty, metadata.domain != domainFilter { return false }
        if !skillFilter.isEmpty, metadata.skill != skillFilter { return false }
        if let difficultyFilter, metadata.difficulty != difficultyFilter { return false }
        return true
    }

    func filterTitle(_ filter: Filter) -> String {
        switch filter {
        case .all: return language.text("全部", "All")
        case .due: return language.text("今日复习", "Due Today")
        case .needsReview: return language.text("不会", "Review")
        case .mistake: return language.text("错题", "Mistakes")
        case .known: return language.text("会了", "Known")
        }
    }

    func open(_ session: TutorSession) {
        onOpen(session)
    }

    func delete(_ session: TutorSession) {
        guard !deletingSessionIDs.contains(session.id) else { return }
        deletingSessionIDs.insert(session.id)
        operationStatusMessage = language.text("正在删除…", "Deleting…")
        operationStatusIsError = false
        historyStore.delete(sessionID: session.id) { [weak self] success in
            guard let self else { return }
            self.deletingSessionIDs.remove(session.id)
            self.operationStatusIsError = !success
            self.operationStatusMessage = success
                ? self.language.text("记录已删除。", "History item deleted.")
                : self.language.text("删除失败，请查看运行日志。", "Delete failed. Check the runtime log.")
        }
    }

    func clear() {
        guard !isClearingHistory else { return }
        isClearingHistory = true
        operationStatusMessage = language.text("正在清空历史…", "Clearing history…")
        operationStatusIsError = false
        historyStore.clear { [weak self] success in
            guard let self else { return }
            self.isClearingHistory = false
            self.operationStatusIsError = !success
            self.operationStatusMessage = success
                ? self.language.text("历史已清空。", "History cleared.")
                : self.language.text("清空失败，请查看运行日志。", "Clear failed. Check the runtime log.")
        }
    }

    func isDeleting(_ session: TutorSession) -> Bool {
        deletingSessionIDs.contains(session.id)
    }
}

