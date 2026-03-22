import SwiftUI

struct DeployProgressView: View {
    let steps: [ProcessingStep]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(steps) { step in
                HStack(spacing: 8) {
                    statusIcon(for: step.status)
                        .frame(width: 16)

                    Text(step.label)
                        .font(.callout)
                        .foregroundStyle(foregroundColor(for: step.status))

                    Spacer()

                    if !step.detail.isEmpty {
                        Text(step.detail)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
                .padding(.vertical, 3)
            }
        }
        .padding(12)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder
    private func statusIcon(for status: StepStatus) -> some View {
        switch status {
        case .pending:
            Image(systemName: "circle")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        case .active:
            ProgressView()
                .controlSize(.small)
        case .completed:
            Image(systemName: "checkmark.circle.fill")
                .font(.caption)
                .foregroundStyle(.green)
        case .skipped:
            Image(systemName: "arrow.right.circle.fill")
                .font(.caption)
                .foregroundStyle(.secondary)
        case .error:
            Image(systemName: "xmark.circle.fill")
                .font(.caption)
                .foregroundStyle(.red)
        }
    }

    private func foregroundColor(for status: StepStatus) -> Color {
        switch status {
        case .pending: .secondary
        case .active: .primary
        case .completed: .primary
        case .skipped: .secondary
        case .error: .red
        }
    }
}
