import Foundation

@MainActor
extension AppCoordinator {
    func startTodayPractice(respectsDailyLimit: Bool = true) {
        let decision = teachingScheduler.nextDecision(
            evidence: masteryEvidenceStore.evidence,
            manuallyMasteredIDs: historyStore.manuallyMasteredKnowledgePointIDs,
            respectsDailyLimit: respectsDailyLimit
        )
        guard let decision else {
            let session = TutorSession.newSession(screenshot: nil)
            session.title = settingsStore.settings.appLanguage.text(
                "今天的学习已完成",
                "Today's learning is complete"
            )
            openTutorWindow(session: session)
            tutorWindowController?.showDailyPracticeComplete()
            return
        }
        guard let point = SATKnowledgeCatalog.knowledgePoint(id: decision.knowledgePointID),
              let type = SATKnowledgeCatalog.questionType(id: point.questionTypeID) else { return }
        openGeneratedPractice(point: point, type: type, decision: decision)
    }

    func startChallengePractice() {
        let profiles = SATLearningAnalytics.knowledgePointProfiles(from: masteryEvidenceStore.evidence)
        let masteredIDs = Set(profiles.filter { $0.stage == .stablyMastered }.map(\.id))
            .union(historyStore.manuallyMasteredKnowledgePointIDs)
        var candidates = SATKnowledgeCatalog.knowledgePoints.filter { masteredIDs.contains($0.id) }
        if candidates.isEmpty,
           let strongest = profiles.max(by: { $0.mastery < $1.mastery }) {
            candidates = [strongest.definition]
        }
        candidates.sort { $0.id.localizedStandardCompare($1.id) == .orderedAscending }
        let day = Calendar.autoupdatingCurrent.ordinality(of: .day, in: .era, for: Date()) ?? 0
        guard !candidates.isEmpty,
              let point = candidates.dropFirst(day % candidates.count).first,
              let type = SATKnowledgeCatalog.questionType(id: point.questionTypeID) else { return }
        let decision = TeachingDecision(
            knowledgePointID: point.id,
            purpose: .transfer,
            difficulty: .hard,
            reason: "student-selected-optional-challenge"
        )
        openGeneratedPractice(point: point, type: type, decision: decision)
    }

    func startKnowledgePointPractice(_ profile: SATKnowledgePointProfile) {
        guard let type = SATKnowledgeCatalog.questionType(id: profile.definition.questionTypeID) else { return }
        let difficulty: SATDifficulty = profile.state == .pendingVerification ? .medium : .easy
        let decision = TeachingDecision(
            knowledgePointID: profile.id,
            purpose: .consolidation,
            difficulty: difficulty,
            reason: "student-selected-knowledge-point"
        )
        openGeneratedPractice(point: profile.definition, type: type, decision: decision)
    }

    func startSkillPractice(_ profile: SATSkillProfile) {
        let matchingTypes = SATKnowledgeCatalog.questionTypes.filter {
            profile.section == .readingWriting && $0.domain == profile.domain && $0.skill == profile.skill
        }
        let matchingTypeIDs = Set(matchingTypes.map(\.id))
        let candidates = SATKnowledgeCatalog.knowledgePoints.filter {
            matchingTypeIDs.contains($0.questionTypeID)
        }
        let progress = Dictionary(uniqueKeysWithValues:
            SATLearningAnalytics.knowledgePointProfiles(from: masteryEvidenceStore.evidence).map { ($0.id, $0) }
        )
        guard let point = candidates.min(by: {
            (progress[$0.id]?.mastery ?? 0) < (progress[$1.id]?.mastery ?? 0)
        }), let type = SATKnowledgeCatalog.questionType(id: point.questionTypeID) else {
            RuntimeLog.write("targeted-skill-practice-missing-catalog-match profile=\(profile.id)")
            return
        }
        let decision = TeachingDecision(
            knowledgePointID: point.id,
            purpose: .consolidation,
            difficulty: profile.recommendedDifficulty,
            reason: "student-selected-skill"
        )
        openGeneratedPractice(point: point, type: type, decision: decision)
    }

    func startReviewQueue(_ sessions: [TutorSession], limit: Int) {
        detachAndCloseTutorWindow()
        pendingReviewSessions = Array(sessions.prefix(limit))
        openNextReviewSession()
    }

    func openNextReviewSession() {
        guard !pendingReviewSessions.isEmpty else { return }
        openTutorWindow(session: pendingReviewSessions.removeFirst())
    }

    private func openGeneratedPractice(
        point: SATKnowledgePointDefinition,
        type: SATQuestionTypeDefinition,
        decision: TeachingDecision
    ) {
        pendingReviewSessions = []
        var document = OCRDocument.empty()
        let prerequisites = SATKnowledgeGraph.prerequisites(of: point.id)
        document.fullText = "SAT adaptive practice. Purpose: \(decision.purpose.rawValue). Teaching reason: \(decision.reason). Question type: \(type.titleEN). Knowledge point: \(point.titleEN) [\(point.id)]. Prerequisites: \(prerequisites.isEmpty ? "none" : prerequisites.joined(separator: ", ")). Difficulty: \(decision.difficulty.rawValue)."
        document.editedText = document.fullText
        let session = TutorSession.newSession(screenshot: nil)
        session.ocrDocument = document
        session.title = settingsStore.settings.appLanguage.text(
            "今日练习：\(point.titleZH)",
            "Today: \(point.titleEN)"
        )
        session.category = category(for: type)
        session.learningMetadata.section = .readingWriting
        session.learningMetadata.domain = type.domain
        session.learningMetadata.skill = type.skill
        session.learningMetadata.questionTypeID = type.id
        session.learningMetadata.knowledgePointIDs = [point.id]
        session.learningMetadata.difficulty = decision.difficulty
        session.learningMetadata.teachingPurpose = decision.purpose
        session.learningMetadata.isAIGenerated = true
        openTutorWindow(session: session)
        tutorWindowController?.generatePracticeQuestion()
    }

    private func category(for type: SATQuestionTypeDefinition) -> SessionCategory {
        return type.domain == "Standard English Conventions" ? .grammar : .reading
    }
}
