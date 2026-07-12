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

    private static let automaticAcceptanceConfidence = 0.90
    private static let minimumVerifiedConfidence = 0.8

    func verify(question: String) async throws -> AnswerVerification? {
        guard TutorQuestionParsing.answerChoices(from: question).count >= 2 else { return nil }
        let solver = try await request(promptBuilder.answerSolverPrompt(question: question), thinkingMode: .disabled)
        guard let solver else {
            RuntimeLog.write("answer-verification-unverified stage=solver")
            return nil
        }
        guard solver.confidence < Self.automaticAcceptanceConfidence else {
            RuntimeLog.write("answer-verification-passed answer=\(solver.answer) mode=standard confidence=\(solver.confidence)")
            return solver
        }

        RuntimeLog.write("answer-verification-escalated confidence=\(solver.confidence)")
        let reasoningResult = try await request(promptBuilder.answerSolverPrompt(question: question), thinkingMode: .high)
        guard let reasoningResult, reasoningResult.confidence >= Self.minimumVerifiedConfidence else {
            RuntimeLog.write("answer-verification-unverified stage=reasoning")
            return nil
        }
        RuntimeLog.write("answer-verification-passed answer=\(reasoningResult.answer) mode=reasoning confidence=\(reasoningResult.confidence)")
        return reasoningResult
    }

    private func request(_ messages: [DeepSeekMessage], thinkingMode: DeepSeekThinkingMode) async throws -> AnswerVerification? {
        var response = ""
        do {
            try await client.stream(
                messages: messages,
                temperatureOverride: 0,
                modelOverride: DeepSeekModel.pro.rawValue,
                thinkingMode: thinkingMode
            ) { response += $0 }
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
