import Foundation

struct AnswerVerification: Equatable {
    var answer: String
    var confidence: Double
    var evidence: String

    static func parse(_ content: String) -> AnswerVerification? {
        guard let start = content.range(of: "ANSWER_VERIFICATION"),
              let end = content.range(of: "END_ANSWER_VERIFICATION", range: start.upperBound..<content.endIndex) else {
            return nil
        }
        let block = String(content[start.upperBound..<end.lowerBound])
        guard let answer = field("Answer", in: block).uppercased().first.map(String.init),
              ["A", "B", "C", "D"].contains(answer),
              let confidence = Double(field("Confidence", in: block)),
              (0...1).contains(confidence) else {
            return nil
        }
        let evidence = field("Evidence", in: block)
        guard !evidence.isEmpty else { return nil }
        return AnswerVerification(answer: answer, confidence: confidence, evidence: evidence)
    }

    private static func field(_ name: String, in block: String) -> String {
        block.split(whereSeparator: \.isNewline).compactMap { line -> String? in
            let text = String(line).trimmingCharacters(in: .whitespacesAndNewlines)
            let prefix = "\(name):"
            guard text.lowercased().hasPrefix(prefix.lowercased()) else { return nil }
            return String(text.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
        }.first ?? ""
    }
}

@MainActor
struct AnswerVerificationService {
    let client: any DeepSeekStreaming
    let promptBuilder: PromptBuilder

    func verify(question: String) async throws -> AnswerVerification? {
        guard TutorQuestionParsing.answerChoices(from: question).count >= 2 else { return nil }
        let solver = try await request(promptBuilder.answerSolverPrompt(question: question))
        guard let solver, solver.confidence >= 0.8 else {
            RuntimeLog.write("answer-verification-unverified stage=solver")
            return nil
        }
        let critic = try await request(promptBuilder.answerCriticPrompt(question: question, proposal: solver))
        guard let critic,
              critic.confidence >= 0.8,
              critic.answer == solver.answer else {
            RuntimeLog.write("answer-verification-conflict solver=\(solver.answer) critic=\(critic?.answer ?? "nil")")
            return nil
        }
        RuntimeLog.write("answer-verification-passed answer=\(critic.answer)")
        return AnswerVerification(
            answer: critic.answer,
            confidence: min(solver.confidence, critic.confidence),
            evidence: critic.evidence
        )
    }

    private func request(_ messages: [DeepSeekMessage]) async throws -> AnswerVerification? {
        var response = ""
        do {
            try await client.stream(messages: messages, temperatureOverride: 0) { response += $0 }
            try Task.checkCancellation()
            return AnswerVerification.parse(response)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            RuntimeLog.write("answer-verification-request-failed \(error.localizedDescription)")
            return nil
        }
    }
}
