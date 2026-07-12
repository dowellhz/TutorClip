import Foundation

@MainActor
extension TutorViewModel {
    func persistBeforeReplacingSession(with replacementID: UUID) {
        guard session.id != replacementID else { return }
        RuntimeLog.write("session-persistence-before-replacement")
        closeAndPersistIfNeeded()
    }

    func closeAndPersistIfNeeded(recordMasteryEvidence: Bool = true) {
        cancelInFlightRequest(reason: "window-closed")
        session.discardScreenshot()
        guard hasPersistableSessionContent else {
            RuntimeLog.write("session-persistence-skipped empty-workspace=true")
            return
        }
        refreshQuestionCategory()
        historyStore.save(
            session: session,
            detailedHistoryEnabled: settingsStore.settings.historyEnabled,
            learningProgressEnabled: settingsStore.settings.learningProgressEnabled
        ) { [weak self] success in
            guard let self, !success else { return }
            self.errorMessage = self.text("历史数据库写入失败。", "History database write failed.")
        }
        if recordMasteryEvidence {
            masteryEvidenceStore?.record(
                session: session,
                enabled: settingsStore.settings.learningProgressEnabled
            )
        }
    }

    private var hasPersistableSessionContent: Bool {
        !session.ocrDocument.editedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !session.messages.isEmpty
            || !session.vocabularyCards.isEmpty
            || !session.learningMetadata.attempts.isEmpty
            || !session.learningMetadata.reviews.isEmpty
            || !session.learningMetadata.knowledgePointIDs.isEmpty
    }
}
