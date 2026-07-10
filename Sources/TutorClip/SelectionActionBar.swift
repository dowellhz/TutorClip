import SwiftUI

struct SelectionActionBar: View {
    @ObservedObject var viewModel: TutorViewModel

    var body: some View {
        HStack(spacing: 6) {
            Text(viewModel.text("已选择", "Selected"))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            ForEach(TutorAction.selectedTextActions, id: \.self) { action in
                Button(action.title(language: viewModel.language)) {
                    viewModel.run(action: action)
                }
            }
        }
        .font(.system(size: 12))
        .lineLimit(1)
        .fixedSize(horizontal: true, vertical: false)
        .padding(7)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .shadow(radius: 6, y: 2)
    }
}
