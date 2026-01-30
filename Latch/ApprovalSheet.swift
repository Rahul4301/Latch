import SwiftUI

/// Approval UI for medium-risk actions. Shows exact sanitized preview; no auto-approve, no “approve all” (AGENTS.md, SRS FR-21).
struct ApprovalSheet: View {

    let actions: [ProposedAction]
    let previewProvider: (ProposedAction) -> String
    let onSubmit: ([UUID]) -> Void
    let onCancel: () -> Void

    @State private var approvedIds: Set<UUID> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Approve actions")
                .font(.headline)

            List {
                ForEach(actions) { action in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(action.title)
                                .font(.subheadline.weight(.medium))
                            Spacer()
                            riskBadge(action.risk)
                        }
                        Text(previewProvider(action))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(3)
                        Toggle("Approve", isOn: Binding(
                            get: { approvedIds.contains(action.id) },
                            set: { isOn in
                                if isOn { approvedIds.insert(action.id) }
                                else { approvedIds.remove(action.id) }
                            }
                        ))
                        .toggleStyle(.switch)
                    }
                    .padding(.vertical, 4)
                }
            }
            .listStyle(.plain)

            HStack(spacing: 12) {
                Button("Cancel") {
                    onCancel()
                }
                .keyboardShortcut(.cancelAction)

                Button("Run Approved") {
                    onSubmit(Array(approvedIds))
                }
                .keyboardShortcut(.defaultAction)
                .disabled(approvedIds.isEmpty)
            }
            .padding(.horizontal)
        }
        .padding()
        .frame(minWidth: 400, minHeight: 300)
    }

    @ViewBuilder
    private func riskBadge(_ risk: RiskLevel) -> some View {
        Text(riskLabel(risk))
            .font(.caption2.weight(.medium))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(riskColor(risk).opacity(0.2))
            .clipShape(RoundedRectangle(cornerRadius: 4))
    }

    private func riskLabel(_ risk: RiskLevel) -> String {
        switch risk {
        case .low: return "low"
        case .medium: return "medium"
        case .high: return "high"
        }
    }

    private func riskColor(_ risk: RiskLevel) -> Color {
        switch risk {
        case .low: return .green
        case .medium: return .orange
        case .high: return .red
        }
    }
}
