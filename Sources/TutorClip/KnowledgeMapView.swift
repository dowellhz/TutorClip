import SwiftUI

struct KnowledgeMapView: View {
    @ObservedObject var viewModel: HistoryViewModel

    private var known: [SATKnowledgePointProfile] { viewModel.knowledgePointProfiles.filter { $0.state == .mastered } }
    private var learning: [SATKnowledgePointProfile] { viewModel.knowledgePointProfiles.filter { $0.state != .mastered } }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            HSplitView {
                knowledgeList(title: viewModel.language.text("已经会", "Known"), points: known, knownColumn: true)
                knowledgeList(title: viewModel.language.text("不会 / 学习中", "Not Yet / Learning"), points: learning, knownColumn: false)
            }
        }
        .frame(minWidth: 760, minHeight: 540)
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(viewModel.language.text("SAT 知识地图", "SAT Knowledge Map"))
                    .font(.system(size: 20, weight: .semibold))
                Text(viewModel.language.text("点击知识点即可标记为会或不会；练习记录也会自动更新掌握状态。", "Click a point to mark it known or not yet; practice evidence also updates mastery."))
                    .font(.system(size: 12)).foregroundStyle(.secondary)
                HStack(spacing: 14) {
                    legend(viewModel.language.text("未开始", "Not Started"), state: .new)
                    legend(viewModel.language.text("学习中", "Learning"), state: .learning)
                    legend(viewModel.language.text("待验证", "Verify"), state: .pendingVerification)
                    legend(viewModel.language.text("已掌握", "Mastered"), state: .mastered)
                }
                .padding(.top, 4)
            }
            Spacer()
            Text("\(known.count) / \(viewModel.knowledgePointProfiles.count)")
                .font(.system(size: 16, weight: .medium)).foregroundStyle(.teal)
        }
        .padding(18)
    }

    private func knowledgeList(title: String, points: [SATKnowledgePointProfile], knownColumn: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("\(title)  \(points.count)")
                .font(.system(size: 14, weight: .semibold)).padding(14)
            Divider()
            List {
                ForEach(SATKnowledgeCatalog.questionTypes) { type in
                    let matching = points.filter { $0.definition.questionTypeID == type.id }
                    if !matching.isEmpty {
                        Section(viewModel.language.text(type.titleZH, type.titleEN)) {
                            ForEach(matching) { point in
                                HStack(alignment: .top, spacing: 8) {
                                  Button { viewModel.toggleKnowledgePoint(point) } label: {
                                    HStack(alignment: .top, spacing: 8) {
                                        Image(systemName: knownColumn ? "checkmark.circle.fill" : statusIcon(point.state))
                                            .foregroundStyle(progressColor(point.state))
                                        VStack(alignment: .leading, spacing: 3) {
                                            Text(viewModel.language.text(point.definition.titleZH, point.definition.titleEN))
                                                .foregroundStyle(progressColor(point.state))
                                            if point.attemptCount > 0 {
                                                Text(viewModel.language.text("\(point.independentCorrectCount) 次独立答对 · \(Int(point.mastery))%", "\(point.independentCorrectCount) independent correct · \(Int(point.mastery))%"))
                                                    .font(.system(size: 10)).foregroundStyle(.secondary)
                                            }
                                        }
                                    }
                                  }
                                  .buttonStyle(.plain)
                                  Spacer()
                                  if !knownColumn {
                                      Button(viewModel.language.text("生成例题", "Generate Example")) {
                                          viewModel.practice(point)
                                      }
                                      .controlSize(.small)
                                  }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private func statusIcon(_ state: SATMasteryState) -> String {
        switch state {
        case .new: return "circle"
        case .learning: return "clock"
        case .pendingVerification: return "checkmark.circle"
        case .mastered: return "checkmark.circle.fill"
        }
    }

    private func progressColor(_ state: SATMasteryState) -> Color {
        switch state {
        case .new: return .secondary
        case .learning: return .orange
        case .pendingVerification: return .blue
        case .mastered: return .teal
        }
    }

    private func legend(_ title: String, state: SATMasteryState) -> some View {
        HStack(spacing: 4) {
            Circle().fill(progressColor(state)).frame(width: 7, height: 7)
            Text(title).font(.system(size: 10)).foregroundStyle(progressColor(state))
        }
    }
}
