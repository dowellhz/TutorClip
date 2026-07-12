import Foundation

@MainActor
extension TutorViewModel {
    func classifyQuestionCategoryWithAI(_ text: String) async {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        var raw = ""
        do {
            try await deepSeekClient.stream(messages: promptBuilder.classifyQuestionPrompt(text: text)) { token in
                raw += token
            }
            let category = TutorQuestionParsing.category(fromAI: raw)
            if category != .unknown {
                session.category = category
                categorySourceAI = true
                RuntimeLog.write("question-category-ai \(category.rawValue)")
            } else {
                RuntimeLog.writeTextBlock("question-category-ai-unknown", raw)
            }
        } catch is CancellationError {
            RuntimeLog.write("question-category-ai-cancelled")
        } catch {
            RuntimeLog.write("question-category-ai-error \(error.localizedDescription)")
        }
    }

    func updateSATSection(_ section: SATSection) {
        session.learningMetadata.section = section
        discardIncompatibleKnowledgeTarget()
        persistClassification()
    }

    func updateSATDomain(_ domain: String) {
        session.learningMetadata.domain = domain
        discardIncompatibleKnowledgeTarget()
        persistClassification()
    }

    func updateSATSkill(_ skill: String) {
        session.learningMetadata.skill = skill
        discardIncompatibleKnowledgeTarget()
        persistClassification()
    }

    func updateSATDifficulty(_ difficulty: SATDifficulty) {
        session.learningMetadata.difficulty = difficulty
        persistClassification()
    }

    private func persistClassification() {
        session.updatedAt = Date()
        objectWillChange.send()
        saveLearningState(errorMessage: text("SAT 分类保存失败。", "Failed to save SAT classification."))
    }

    private func discardIncompatibleKnowledgeTarget() {
        let metadata = session.learningMetadata
        guard let type = SATKnowledgeCatalog.questionType(id: metadata.questionTypeID) else {
            session.learningMetadata.knowledgePointIDs = []
            return
        }
        let expectedSection: SATSection = .readingWriting
        guard expectedSection == metadata.section,
              type.domain == metadata.domain,
              type.skill == metadata.skill else {
            session.learningMetadata.questionTypeID = ""
            session.learningMetadata.knowledgePointIDs = []
            return
        }
        session.learningMetadata.knowledgePointIDs = SATKnowledgeCatalog.validKnowledgePointIDs(
            metadata.knowledgePointIDs,
            questionTypeID: type.id
        )
    }
}
