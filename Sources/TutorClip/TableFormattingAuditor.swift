import Foundation

@MainActor
struct TableFormattingAuditor {
    let client: any DeepSeekStreaming
    let promptBuilder: PromptBuilder

    func audit(document: OCRDocument, candidate: String) async throws -> String {
        guard !document.structuredTables.isEmpty, !candidate.isEmpty else { return candidate }
        var feedback = ""
        var currentCandidate = candidate
        for attempt in 1...2 {
            var response = ""
            do {
                let messages = promptBuilder.repairTableFormattingPrompt(
                    document: document,
                    candidate: currentCandidate,
                    validationFeedback: feedback
                )
                try await client.stream(
                    messages: messages,
                    temperatureOverride: 0
                ) { token in
                    response += token
                }
                try Task.checkCancellation()
                let repaired = GeneratedQuestion.parse(response, requireQuestionBlock: true).question
                guard isComplete(repaired, comparedWith: candidate, document: document) else {
                    if !repaired.isEmpty { currentCandidate = repaired }
                    feedback = "输出缺少原题内容、选项或表格行列（第 \(attempt) 次）。"
                    RuntimeLog.write("table-format-audit-retrying attempt=\(attempt) incomplete=true")
                    continue
                }
                RuntimeLog.write("table-format-audit-applied chars=\(repaired.count) attempt=\(attempt)")
                return repaired
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                RuntimeLog.write("table-format-audit-fallback \(error.localizedDescription)")
                return candidate
            }
        }
        let fallback = MissingChoiceFallback.restore(source: document.editedText, candidate: currentCandidate)
        if isComplete(fallback, comparedWith: candidate, document: document) {
            RuntimeLog.write("table-format-audit-choice-fallback-applied")
            return fallback
        }
        RuntimeLog.write("table-format-audit-rejected attempts=2")
        return candidate
    }

    private func isComplete(_ repaired: String, comparedWith candidate: String, document: OCRDocument) -> Bool {
        guard !repaired.isEmpty, repaired.count >= Int(Double(candidate.count) * 0.85) else { return false }
        let source = QuestionMarkdownDocument(markdown: candidate)
        let result = QuestionMarkdownDocument(markdown: repaired)
        let sourceTables = source.blocks.compactMap(\.table)
        let resultTables = result.blocks.compactMap(\.table)
        let expectedShapes = document.structuredTables.map { table -> (columns: Int, dataRows: Int) in
            let columns = table.rows.map(\.count).max() ?? 0
            let fullWidthRows = table.rows.filter { $0.count == columns }.count
            let headerIsFullWidth = table.rows.first?.count == columns
            return (columns, max(0, fullWidthRows - (headerIsFullWidth ? 1 : 0)))
        }
        guard sourceTables.count == resultTables.count,
              resultTables.count == expectedShapes.count,
              zip(resultTables, expectedShapes).allSatisfy({ result, expected in
                  result.columnCount == expected.columns
                      && result.rows.count >= expected.dataRows
                      && result.rows.allSatisfy { $0.count == expected.columns }
              }) else { return false }
        let sourceChoices = Set(TutorQuestionParsing.answerChoices(from: document.editedText))
        let resultChoices = Set(TutorQuestionParsing.answerChoices(from: repaired))
        return !sourceChoices.isEmpty && sourceChoices.isSubset(of: resultChoices)
    }
}
