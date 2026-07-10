import SwiftUI

struct HistoryView: View {
    @ObservedObject var viewModel: HistoryViewModel

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                TextField(viewModel.language.text("搜索 OCR 和对话", "Search OCR and conversations"), text: $viewModel.query)
                    .textFieldStyle(.roundedBorder)
                Button(
                    viewModel.isClearingHistory
                        ? viewModel.language.text("正在清空…", "Clearing…")
                        : viewModel.language.text("清空全部", "Clear All")
                ) { viewModel.clear() }
                    .disabled(viewModel.isClearingHistory || viewModel.sessions.isEmpty)
            }
            .padding(12)
            if !viewModel.operationStatusMessage.isEmpty {
                Text(viewModel.operationStatusMessage)
                    .font(.system(size: 12))
                    .foregroundStyle(viewModel.operationStatusIsError ? Color.red : Color.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 8)
            }
            Divider()

            List {
                ForEach(viewModel.sessions) { session in
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(session.title)
                                .font(.system(size: 14, weight: .semibold))
                                .lineLimit(1)
                            Text(session.createdAt.formatted(date: .abbreviated, time: .shortened))
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                            Text(session.category.displayName(language: viewModel.language))
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.teal)
                            Text(session.studyStatus.title(language: viewModel.language))
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.secondary)
                            Text(session.ocrDocument.editedText)
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                        Spacer()
                        Button(viewModel.language.text("打开", "Open")) { viewModel.open(session) }
                        Button(
                            viewModel.isDeleting(session)
                                ? viewModel.language.text("删除中…", "Deleting…")
                                : viewModel.language.text("删除", "Delete")
                        ) { viewModel.delete(session) }
                            .disabled(viewModel.isDeleting(session))
                    }
                    .padding(.vertical, 6)
                }
            }
        }
        .frame(minWidth: 720, minHeight: 520)
    }
}
