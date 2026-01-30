import SwiftUI
import Combine
/// Chat UI: message list, input, send; wires to AgentOrchestrator and ApprovalSheet (SRS, AGENTS.md).
struct ChatView: View {

    @State private var inputText: String = ""
    @State private var messages: [ChatMessage] = []
    @State private var pendingActions: [ProposedAction] = []
    @State private var showApprovalSheet: Bool = false
    @StateObject private var controller = ChatController()

    var body: some View {
        VStack(spacing: 0) {
            List {
                ForEach(messages) { msg in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(roleLabel(msg.role))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(msg.content)
                            .textSelection(.enabled)
                    }
                    .padding(.vertical, 4)
                }
            }
            .listStyle(.plain)

            HStack(spacing: 8) {
                TextField("Message", text: $inputText, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(1...6)
                Button("Send") {
                    sendMessage()
                }
                .disabled(inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(8)
        }
        .onAppear {
            controller.onApprovalRequested = { actions, reply in
                pendingActions = actions
                controller.storeReply(reply)
                showApprovalSheet = true
            }
        }
        .sheet(isPresented: $showApprovalSheet) {
            ApprovalSheet(
                actions: pendingActions,
                previewProvider: { PolicyEngine.shared.sanitizedPreview($0.toolCall) },
                onSubmit: { ids in
                    controller.submitApproval(approvedIds: ids)
                    pendingActions = []
                    showApprovalSheet = false
                },
                onCancel: {
                    controller.cancelApproval()
                    pendingActions = []
                    showApprovalSheet = false
                }
            )
        }
    }

    private func roleLabel(_ role: MessageRole) -> String {
        switch role {
        case .user: return "user"
        case .assistant: return "assistant"
        case .system: return "system"
        }
    }

    private func sendMessage() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        let userMsg = ChatMessage(role: .user, content: text)
        messages.append(userMsg)
        inputText = ""
        controller.orchestrator.handleUserMessage(text) { assistantMsg in
            messages.append(assistantMsg)
        }
    }
}

// MARK: - Controller & approval delegate

private final class ApprovalRequestHandler: AgentOrchestratorApprovalDelegate {
    var onRequest: (([ProposedAction], @escaping ([UUID]) -> Void) -> Void)?
    func requestApproval(actions: [ProposedAction], reply: @escaping ([UUID]) -> Void) {
        onRequest?(actions, reply)
    }
}

private final class ChatController: ObservableObject {
    let orchestrator = AgentOrchestrator()
    private let approvalHandler = ApprovalRequestHandler()
    private var pendingReply: (([UUID]) -> Void)?

    var onApprovalRequested: (([ProposedAction], @escaping ([UUID]) -> Void) -> Void)?

    init() {
        orchestrator.approvalDelegate = approvalHandler
        approvalHandler.onRequest = { [weak self] actions, reply in
            DispatchQueue.main.async {
                self?.onApprovalRequested?(actions, reply)
            }
        }
    }

    func storeReply(_ reply: @escaping ([UUID]) -> Void) {
        pendingReply = reply
    }

    func submitApproval(approvedIds: [UUID]) {
        pendingReply?(approvedIds)
        pendingReply = nil
    }

    func cancelApproval() {
        pendingReply?([])
        pendingReply = nil
    }
}
