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
    @Published private(set) var resettingSkillIDs: Set<String> = []
    @Published private(set) var snoozingSessionIDs: Set<UUID> = []
    @Published private(set) var isClearingHistory: Bool = false
    @Published var filter: Filter = .all
    @Published var workspace: Workspace = .history
    @Published var sectionFilter: SATSection?
    @Published var domainFilter = ""
    @Published var skillFilter = ""
    @Published var difficultyFilter: SATDifficulty?
    @Published var errorReasonFilter: SATErrorReason?
    @Published var sourceFilter: SourceFilter = .all
    @Published var recentDays: Int?
    private let settingsStore: SettingsStore
    private let historyStore: HistoryStore
    private let masteryEvidenceStore: MasteryEvidenceStore?
    private let onOpen: (TutorSession) -> Void
    private let onPracticeSkill: (SATSkillProfile) -> Void
    private let onPracticeKnowledgePoint: (SATKnowledgePointProfile) -> Void
    private let onStartReview: ([TutorSession], Int) -> Void
    private var historyCancellable: AnyCancellable?
    private var masteryCancellable: AnyCancellable?
    private var evidenceCancellable: AnyCancellable?
    private var vocabularyCancellable: AnyCancellable?

    init(settingsStore: SettingsStore, historyStore: HistoryStore, masteryEvidenceStore: MasteryEvidenceStore? = nil, onOpen: @escaping (TutorSession) -> Void, onPracticeSkill: @escaping (SATSkillProfile) -> Void = { _ in }, onPracticeKnowledgePoint: @escaping (SATKnowledgePointProfile) -> Void = { _ in }, onStartReview: @escaping ([TutorSession], Int) -> Void = { _, _ in }) {
        self.settingsStore = settingsStore
        self.historyStore = historyStore
        self.masteryEvidenceStore = masteryEvidenceStore
        self.onOpen = onOpen
        self.onPracticeSkill = onPracticeSkill
        self.onPracticeKnowledgePoint = onPracticeKnowledgePoint
        self.onStartReview = onStartReview
        historyCancellable = historyStore.$sessions.sink { [weak self] _ in self?.objectWillChange.send() }
        masteryCancellable = historyStore.$manuallyMasteredKnowledgePointIDs.sink { [weak self] _ in self?.objectWillChange.send() }
        evidenceCancellable = masteryEvidenceStore?.$evidence.sink { [weak self] _ in self?.objectWillChange.send() }
        vocabularyCancellable = masteryEvidenceStore?.$vocabularyCards.sink { [weak self] _ in self?.objectWillChange.send() }
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
        }.filter(matchesAdvancedFilters)
    }
    var availableDomains: [String] { Array(Set(historyStore.sessions.map(\.learningMetadata.domain).filter { !$0.isEmpty })).sorted() }
    var availableSkills: [String] { Array(Set(historyStore.sessions.map(\.learningMetadata.skill).filter { !$0.isEmpty })).sorted() }

    var dueCount: Int {
        guard masteryEvidenceStore != nil else {
            return historyStore.sessions.filter { $0.learningMetadata.isDue }.count
        }
        return knowledgePointProfiles.filter { $0.stage == .dueForReview }.count
    }
    var mistakeCount: Int {
        guard let evidence = masteryEvidenceStore?.evidence else {
            return historyStore.sessions.filter { $0.studyStatus == .mistake }.count
        }
        return evidence.filter { $0.isStateSnapshot == true && $0.studyStatus == .mistake }.count
    }
    var reviewCount: Int {
        guard let evidence = masteryEvidenceStore?.evidence else {
            return historyStore.sessions.filter { $0.studyStatus == .needsReview }.count
        }
        return evidence.filter { $0.isStateSnapshot == true && $0.studyStatus == .needsReview }.count
    }
    var averageMastery: Int {
        let values: [Double]
        if masteryEvidenceStore != nil {
            values = knowledgePointProfiles.filter { $0.state != .new }.map {
                $0.state == .mastered ? max($0.mastery, 100) : $0.mastery
            }
        } else {
            values = historyStore.sessions.map(\.learningMetadata.mastery)
        }
        return values.isEmpty ? 0 : Int(values.reduce(0, +) / Double(values.count))
    }
    var reviewQueue: [TutorSession] {
        SATLearningAnalytics.reviewQueue(from: historyStore.search(query)).filter(matchesAdvancedFilters)
    }
    var skillProfiles: [SATSkillProfile] {
        if let evidence = masteryEvidenceStore?.evidence {
            return SATLearningAnalytics.skillProfiles(from: evidence)
        }
        return SATLearningAnalytics.skillProfiles(from: historyStore.sessions)
    }
    var knowledgePointProfiles: [SATKnowledgePointProfile] {
        let profiles: [SATKnowledgePointProfile]
        if let evidence = masteryEvidenceStore?.evidence {
            profiles = SATLearningAnalytics.knowledgePointProfiles(from: evidence)
        } else {
            profiles = SATLearningAnalytics.knowledgePointProfiles(from: historyStore.sessions)
        }
        return profiles.map { profile in
            guard historyStore.manuallyMasteredKnowledgePointIDs.contains(profile.id) else { return profile }
            var updated = profile
            updated.state = .mastered
            return updated
        }
    }

    var vocabularyCards: [VocabularyCard] {
        masteryEvidenceStore?.vocabularyCards ?? historyStore.sessions.flatMap(\.vocabularyCards)
    }

    func saveVocabularyCard(_ card: VocabularyCard) {
        masteryEvidenceStore?.saveVocabularyCard(card) { [weak self] success in
            self?.operationStatusIsError = !success
            self?.operationStatusMessage = success
                ? self?.language.text("词卡已保存。", "Vocabulary card saved.") ?? ""
                : self?.language.text("词卡保存失败。", "Failed to save vocabulary card.") ?? ""
        }
    }

    func reviewVocabularyCard(_ card: VocabularyCard, rating: VocabularyReviewRating) {
        var reviewed = card
        reviewed.applyReview(rating)
        saveVocabularyCard(reviewed)
    }

    func deleteVocabularyCard(_ card: VocabularyCard) {
        masteryEvidenceStore?.deleteVocabularyCard(id: card.id) { [weak self] success in
            self?.operationStatusIsError = !success
            self?.operationStatusMessage = success
                ? self?.language.text("词卡已删除。", "Vocabulary card deleted.") ?? ""
                : self?.language.text("词卡删除失败。", "Failed to delete vocabulary card.") ?? ""
        }
    }

    func openVocabularySource(_ card: VocabularyCard) {
        guard let sessionID = card.sourceSessionID,
              let session = historyStore.sessions.first(where: { $0.id == sessionID }) else {
            operationStatusIsError = true
            operationStatusMessage = language.text("原题未保存在历史中。", "The source question is not available in history.")
            return
        }
        onOpen(session)
    }

    func toggleKnowledgePoint(_ profile: SATKnowledgePointProfile) {
        guard settingsStore.settings.learningProgressEnabled else {
            operationStatusIsError = true
            operationStatusMessage = language.text(
                "请先在设置中开启“保存学习进度”。",
                "Enable Save Learning Progress in Settings first."
            )
            return
        }
        let isManuallyMastered = historyStore.manuallyMasteredKnowledgePointIDs.contains(profile.id)
        if profile.state == .mastered, !isManuallyMastered {
            operationStatusIsError = false
            operationStatusMessage = language.text(
                "该知识点由真实作答证据判定为已掌握；如需清零，请使用对应技能的“重置”。",
                "This point is mastered from answer evidence. Use Reset on its skill to clear that evidence."
            )
            return
        }
        historyStore.setKnowledgePoint(profile.id, mastered: !isManuallyMastered) { [weak self] success in
            guard let self else { return }
            self.operationStatusIsError = !success
            self.operationStatusMessage = success
                ? self.language.text("知识点状态已更新。", "Knowledge-point status updated.")
                : self.language.text("状态更新失败，请查看运行日志。", "Update failed. Check the runtime log.")
        }
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
        guard !resettingSkillIDs.contains(profile.id) else { return }
        resettingSkillIDs.insert(profile.id)
        let pointIDs = Set(SATKnowledgeCatalog.knowledgePoints.filter {
            guard let type = SATKnowledgeCatalog.questionType(id: $0.questionTypeID) else { return false }
            return profile.section == .readingWriting && type.id.hasPrefix("RW.")
                && type.domain == profile.domain && type.skill == profile.skill
        }.map(\.id))
        let matches = historyStore.sessions.filter {
            $0.learningMetadata.section == profile.section && $0.learningMetadata.domain == profile.domain && $0.learningMetadata.skill == profile.skill
        }
        let operationCount = matches.count + pointIDs.count + (masteryEvidenceStore == nil ? 0 : 1)
        let finished = operationTracker(
            count: operationCount,
            successMessage: language.text("技能学习进度已重置。", "Skill progress reset."),
            failureMessage: language.text("重置失败，请查看运行日志。", "Reset failed. Check the runtime log."),
            onFinish: { [weak self] in self?.resettingSkillIDs.remove(profile.id) }
        )
        operationStatusIsError = false
        operationStatusMessage = language.text("正在重置技能进度…", "Resetting skill progress…")
        for session in matches {
            let identity = (session.learningMetadata.section, session.learningMetadata.domain, session.learningMetadata.skill, session.learningMetadata.difficulty)
            session.learningMetadata = SATLearningMetadata()
            session.learningMetadata.section = identity.0
            session.learningMetadata.domain = identity.1
            session.learningMetadata.skill = identity.2
            session.learningMetadata.difficulty = identity.3
            session.studyStatus = .unreviewed
            historyStore.save(
                session: session,
                detailedHistoryEnabled: true,
                learningProgressEnabled: true
            ) { finished($0) }
        }
        for pointID in pointIDs {
            historyStore.setKnowledgePoint(pointID, mastered: false) { finished($0) }
        }
        masteryEvidenceStore?.resetKnowledgePoints(pointIDs) { finished($0) }
        if operationCount == 0 { finished(true) }
    }

    func snooze(_ session: TutorSession) {
        guard !snoozingSessionIDs.contains(session.id) else { return }
        guard settingsStore.settings.learningProgressEnabled else {
            operationStatusIsError = true
            operationStatusMessage = language.text(
                "请先在设置中开启“保存学习进度”。",
                "Enable Save Learning Progress in Settings first."
            )
            return
        }
        snoozingSessionIDs.insert(session.id)
        session.learningMetadata.nextReviewAt = Calendar.autoupdatingCurrent.date(byAdding: .day, value: 1, to: Date())
        session.updatedAt = Date()
        let operationCount = masteryEvidenceStore == nil ? 1 : 2
        let finished = operationTracker(
            count: operationCount,
            successMessage: language.text("已推迟到明天。", "Snoozed until tomorrow."),
            failureMessage: language.text("推迟失败，请查看运行日志。", "Snooze failed. Check the runtime log."),
            onFinish: { [weak self] in self?.snoozingSessionIDs.remove(session.id) }
        )
        operationStatusIsError = false
        operationStatusMessage = language.text("正在推迟…", "Snoozing…")
        historyStore.save(
            session: session,
            detailedHistoryEnabled: true,
            learningProgressEnabled: true
        ) { finished($0) }
        masteryEvidenceStore?.record(
            session: session,
            enabled: settingsStore.settings.learningProgressEnabled
        ) { finished($0) }
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
        if let errorReasonFilter, metadata.errorReason != errorReasonFilter { return false }
        if sourceFilter == .captured, metadata.isAIGenerated { return false }
        if sourceFilter == .aiGenerated, !metadata.isAIGenerated { return false }
        if let recentDays, session.updatedAt < Date().addingTimeInterval(-Double(recentDays) * 86_400) {
            return false
        }
        return true
    }

    private func operationTracker(
        count: Int,
        successMessage: String,
        failureMessage: String,
        onFinish: @escaping () -> Void = {}
    ) -> (Bool) -> Void {
        var remaining = max(count, 1)
        var allSucceeded = true
        return { [weak self] success in
            allSucceeded = allSucceeded && success
            remaining -= 1
            guard remaining == 0, let self else { return }
            self.operationStatusIsError = !allSucceeded
            self.operationStatusMessage = allSucceeded ? successMessage : failureMessage
            onFinish()
        }
    }

    func isResetting(_ profile: SATSkillProfile) -> Bool { resettingSkillIDs.contains(profile.id) }
    func isSnoozing(_ session: TutorSession) -> Bool { snoozingSessionIDs.contains(session.id) }

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
