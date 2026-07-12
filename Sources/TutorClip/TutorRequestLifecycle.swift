import Foundation

@MainActor
extension TutorViewModel {
    func beginRequest() -> UUID {
        let requestID = UUID()
        activeRequestID = requestID
        isStreaming = true
        return requestID
    }

    func finishRequest(_ requestID: UUID) {
        guard activeRequestID == requestID else { return }
        activeRequestID = nil
        inFlightTask = nil
        isStreaming = false
        learningLoadingAction = nil
    }

    func isCurrentRequest(_ requestID: UUID) -> Bool {
        activeRequestID == requestID && !Task.isCancelled
    }

    func cancelInFlightRequest(reason: String) {
        guard inFlightTask != nil || activeRequestID != nil || answerVerificationTask != nil else { return }
        RuntimeLog.write("request-cancel reason=\(reason)")
        activeRequestID = nil
        inFlightTask?.cancel()
        inFlightTask = nil
        answerVerificationTask?.cancel()
        answerVerificationTask = nil
        isStreaming = false
        learningLoadingAction = nil
    }

    func beginAnswerVerification(for question: String) -> Task<AnswerVerification?, Never>? {
        guard TutorQuestionParsing.answerChoices(from: question).count >= 2 else { return nil }
        answerVerificationTask?.cancel()
        let startedAt = Date()
        let task = Task { [deepSeekClient, promptBuilder] in
            do {
                let result = try await AnswerVerificationService(client: deepSeekClient, promptBuilder: promptBuilder)
                    .verify(question: question)
                PipelineTimingMetrics.record(stage: "Pro answer verification", duration: Date().timeIntervalSince(startedAt))
                return result
            } catch is CancellationError {
                return nil
            } catch {
                RuntimeLog.write("answer-verification-background-failed \(error.localizedDescription)")
                return nil
            }
        }
        answerVerificationTask = task
        return task
    }

    func applyPreflightVerification(
        _ task: Task<AnswerVerification?, Never>?,
        originalQuestion: String,
        formattedQuestion: String,
        sessionID: UUID
    ) {
        guard let task else { return }
        Task { [weak self] in
            let verification = await task.value
            guard let self, !Task.isCancelled, self.session.id == sessionID else { return }
            self.answerVerificationTask = nil
            guard self.answerChoicesMatch(originalQuestion, formattedQuestion) else {
                RuntimeLog.write("answer-verification-retry formatted-choices-changed")
                self.applyVerificationForFormattedQuestion(formattedQuestion, sessionID: sessionID)
                return
            }
            self.applyVerifiedAnswer(verification, sessionID: sessionID)
        }
    }

    private func applyVerificationForFormattedQuestion(_ question: String, sessionID: UUID) {
        guard let task = beginAnswerVerification(for: question) else { return }
        Task { [weak self] in
            let verification = await task.value
            guard let self, self.session.id == sessionID else { return }
            self.answerVerificationTask = nil
            self.applyVerifiedAnswer(verification, sessionID: sessionID)
        }
    }

    private func applyVerifiedAnswer(_ verification: AnswerVerification?, sessionID: UUID) {
        guard session.id == sessionID else { return }
        session.correctAnswer = verification?.answer
        session.learningMetadata.isAIVerified = verification != nil
        session.learningMetadata.answerConfidence = verification?.confidence
        if let verifiedAnswer = verification?.answer {
            replaceConflictingExplanationIfNeeded(verifiedAnswer: verifiedAnswer)
        }
        RuntimeLog.write("answer-verification-background-applied answer=\(verification?.answer ?? "nil")")
    }

    private func replaceConflictingExplanationIfNeeded(verifiedAnswer: String) {
        guard let summaryAnswer = answerSummary?.choiceLetter,
              summaryAnswer != verifiedAnswer,
              let index = session.messages.lastIndex(where: {
                  $0.role == .assistant && $0.actionType == .explainAll
              })
        else { return }

        answerSummary = nil
        session.messages[index].content = text(
            "这段讲解与后台答案校验冲突，正在按已验证答案重新生成。",
            "This explanation conflicted with background answer verification and is being regenerated."
        )
        RuntimeLog.write("explanation-replaced verified=\(verifiedAnswer) summary=\(summaryAnswer)")
        send(action: .explainAll, question: nil)
    }

    private func answerChoicesMatch(_ first: String, _ second: String) -> Bool {
        let normalize: (String) -> String = { choice in
            choice.lowercased()
                .split(whereSeparator: { $0.isWhitespace })
                .joined(separator: " ")
        }
        return TutorQuestionParsing.answerChoices(from: first).map(normalize)
            == TutorQuestionParsing.answerChoices(from: second).map(normalize)
    }
}
