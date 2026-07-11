import Foundation

@MainActor
extension TutorViewModel {
    func run(tableInteraction selection: TableInteractionSelection) {
        let question: String
        switch selection.scope {
        case .cell:
            question = text("只解释所选表格单元格的含义及单位。", "Explain only the selected table cell, including its meaning and unit.")
        case .row:
            question = text("解释所选表格行各列之间的关系。", "Explain the relationship among the columns in the selected table row.")
        case .compareRows:
            question = text("比较所选的两行，指出最重要的相同点和差异。", "Compare the selected two rows and identify the most important similarity and difference.")
        case .compareColumns:
            question = text("比较所选的两列，解释它们如何共同描述数据。", "Compare the selected two columns and explain how they describe the data together.")
        case .supportsAnswer:
            question = text("说明所选表格数据如何支持本题正确答案。", "Explain how the selected table data supports the correct answer.")
        }
        selectedText = text("表格结构上下文：\n", "Table context:\n") + selection.context
        selectedTextRect = nil
        send(action: .customQuestion, question: question)
        selectedText = ""
    }
}
