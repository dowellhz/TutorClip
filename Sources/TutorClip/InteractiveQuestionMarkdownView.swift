import AppKit
import MarkdownUI
import SwiftUI

struct InteractiveQuestionMarkdownView: View {
    let markdown: String
    let underlinedTexts: [String]
    let language: AppLanguage
    @Binding var selectedText: String
    @Binding var selectionRect: CGRect?
    let onTableInteraction: (TableInteractionSelection) -> Void

    private var document: QuestionMarkdownDocument { QuestionMarkdownDocument(markdown: markdown) }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 10) {
                ForEach(document.blocks) { block in
                    switch block.kind {
                    case .text:
                        PositionedSelectableMarkdownBlock(
                            markdown: block.markdown,
                            underlinedTexts: underlinedTexts,
                            selectedText: $selectedText,
                            selectionRect: $selectionRect
                        )
                    case .table(let table):
                        InteractiveMarkdownTableBlock(
                            table: table,
                            language: language,
                            onInteraction: onTableInteraction
                        )
                    }
                }
            }
            .padding(.vertical, 8)
        }
        .coordinateSpace(name: "question-document")
    }
}

private struct PositionedSelectableMarkdownBlock: View {
    let markdown: String
    let underlinedTexts: [String]
    @Binding var selectedText: String
    @Binding var selectionRect: CGRect?
    @State private var frame: CGRect = .zero

    var body: some View {
        SelectableMarkdownBlockView(markdown: markdown, underlinedTexts: underlinedTexts) { text, localRect in
            selectedText = text
            guard let localRect, !text.isEmpty else { selectionRect = nil; return }
            selectionRect = localRect.offsetBy(dx: frame.minX, dy: frame.minY)
        }
        .background {
            GeometryReader { geometry in
                Color.clear
                    .onAppear { updateFrame(geometry) }
                    .onChange(of: geometry.frame(in: .named("question-document"))) { _, _ in updateFrame(geometry) }
            }
        }
    }

    private func updateFrame(_ geometry: GeometryProxy) {
        frame = geometry.frame(in: .named("question-document"))
    }
}

private struct InteractiveMarkdownTableBlock: View {
    let table: QuestionMarkdownTable
    let language: AppLanguage
    let onInteraction: (TableInteractionSelection) -> Void
    @State private var selectedCells: [TableCellReference] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ScrollView(.horizontal) {
                Markdown(table.markdown)
                    .markdownImageProvider(.asset)
                    .markdownInlineImageProvider(.asset)
                    .markdownTextStyle { FontSize(15) }
                    .markdownBlockStyle(\.tableCell) { configuration in
                        let cell = TableCellReference(
                            row: configuration.row,
                            column: configuration.column,
                            text: configuration.content.renderPlainText()
                        )
                        configuration.label
                            .markdownTextStyle {
                                if configuration.row == 0 { FontWeight(.semibold) }
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                            .background(cellBackground(cell, isHeader: configuration.row == 0))
                            .contentShape(Rectangle())
                            .onTapGesture { toggle(cell) }
                            .contextMenu { interactionMenu(for: cell) }
                    }
                    .markdownTableBorderStyle(.init(color: Color.secondary.opacity(0.45)))
                    .fixedSize(horizontal: true, vertical: false)
            }
            .padding(.horizontal, 14)

            if !selectedCells.isEmpty {
                tableActionBar
                    .padding(.horizontal, 14)
            }
        }
    }

    private var tableActionBar: some View {
        HStack(spacing: 7) {
            Text(language.text("已选 \(selectedCells.count) 格", "\(selectedCells.count) selected"))
                .foregroundStyle(.secondary)
            Button(language.text("解释单元格", "Explain Cell")) { perform(.cell) }
            Menu(language.text("更多操作", "More")) {
                Button(language.text("解释本行", "Explain Row")) { perform(.row) }
                if Set(selectedCells.map(\.row)).count == 2 {
                    Button(language.text("比较两行", "Compare Rows")) { perform(.compareRows) }
                }
                if Set(selectedCells.map(\.column)).count == 2 {
                    Button(language.text("比较两列", "Compare Columns")) { perform(.compareColumns) }
                }
                Button(language.text("如何支持答案", "Support Answer")) { perform(.supportsAnswer) }
                Divider()
                Button(language.text("复制表格", "Copy Table"), action: copyTable)
            }
        }
        .font(.system(size: 12))
        .buttonStyle(.bordered)
    }

    @ViewBuilder
    private func interactionMenu(for cell: TableCellReference) -> some View {
        Button(language.text("解释这个单元格", "Explain This Cell")) { selectOnly(cell); perform(.cell) }
        Button(language.text("解释这一行", "Explain This Row")) { selectOnly(cell); perform(.row) }
        Button(language.text("这个数据如何支持答案", "How This Supports the Answer")) { selectOnly(cell); perform(.supportsAnswer) }
        Divider()
        Button(language.text("复制表格", "Copy Table"), action: copyTable)
    }

    private func cellBackground(_ cell: TableCellReference, isHeader: Bool) -> Color {
        if selectedCells.contains(cell) { return Color.teal.opacity(0.18) }
        return isHeader ? Color.secondary.opacity(0.10) : Color.clear
    }

    private func toggle(_ cell: TableCellReference) {
        if let index = selectedCells.firstIndex(of: cell) {
            selectedCells.remove(at: index)
        } else if selectedCells.count < 2 {
            selectedCells.append(cell)
        } else {
            selectedCells = [cell]
        }
    }

    private func selectOnly(_ cell: TableCellReference) { selectedCells = [cell] }

    private func perform(_ scope: TableInteractionSelection.Scope) {
        let selection = TableInteractionSelection(scope: scope, cells: selectedCells, context: table.context(for: .init(scope: scope, cells: selectedCells, context: "")))
        onInteraction(selection)
    }

    private func copyTable() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(table.markdown, forType: .string)
    }
}
