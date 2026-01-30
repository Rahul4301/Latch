import Foundation

/// Delegate for medium-risk approval. Reply with the IDs of actions the user approved.
protocol AgentOrchestratorApprovalDelegate: AnyObject {
    func requestApproval(actions: [ProposedAction], reply: @escaping ([UUID]) -> Void)
}

/// Headless loop: user message → plan → validate → approve (if medium) → execute → templated reply. Fail-closed (SRS, AGENTS.md).
final class AgentOrchestrator {

    private var messages: [ChatMessage] = []
    private let llm: LLMClient = MockLLMClient()
    private let policy: PolicyEngine = .shared
    private let fileSearch = FileSearchCapability()
    private let fileRead = FileReadCapability()
    private let commandExec = CommandExecCapability()

    weak var approvalDelegate: AgentOrchestratorApprovalDelegate?

    func handleUserMessage(_ text: String, completion: @escaping (ChatMessage) -> Void) {
        let userMsg = ChatMessage(role: .user, content: text)
        messages.append(userMsg)

        AuditLog.shared.log(eventType: "user_message", payload: [
            "messageId": .string(userMsg.id.uuidString),
            "length": .number(Double(text.count))
        ])

        let workspaceRoot = WorkspaceManager.shared.getWorkspaceRoot()

        Task { @MainActor in
            let plan: AgentPlan = await self.llm.plan(messages: self.messages)

            AuditLog.shared.log(eventType: "plan_received", payload: [
                "summary": .string(plan.summary),
                "questionsCount": .number(Double(plan.questions.count)),
                "actionsCount": .number(Double(plan.actions.count))
            ])

            if !plan.questions.isEmpty {
                let content: String = plan.questions.joined(separator: " ")
                let assistantMsg = ChatMessage(role: .assistant, content: content)
                self.messages.append(assistantMsg)
                AuditLog.shared.log(eventType: "clarification_emitted", payload: [
                    "messageId": .string(assistantMsg.id.uuidString)
                ])
                completion(assistantMsg)
                return
            }

            let maxActions = self.policy.config.maxActionsPerTurn
            if plan.actions.count > maxActions {
                let content = "Denied: Plan has \(plan.actions.count) actions; max allowed is \(maxActions)."
                let assistantMsg = ChatMessage(role: .assistant, content: content)
                self.messages.append(assistantMsg)
                AuditLog.shared.log(eventType: "action_denied", payload: [
                    "reason": .string("Exceeded maxActionsPerTurn.")
                ])
                completion(assistantMsg)
                return
            }

            var allowedActions: [ProposedAction] = []
            for action in plan.actions {
                let (allowed, risk, reason) = self.policy.evaluate(action.toolCall, workspaceRoot: workspaceRoot)
                if !allowed {
                    let content = "Denied: \(reason)"
                    let assistantMsg = ChatMessage(role: .assistant, content: content)
                    self.messages.append(assistantMsg)
                    AuditLog.shared.log(eventType: "action_denied", payload: [
                        "actionId": .string(action.id.uuidString),
                        "tool": .string(action.toolCall.name),
                        "reason": .string(reason)
                    ])
                    completion(assistantMsg)
                    return
                }
                if risk == .high {
                    let content = "Denied: High-risk actions are blocked in MVP."
                    let assistantMsg = ChatMessage(role: .assistant, content: content)
                    self.messages.append(assistantMsg)
                    AuditLog.shared.log(eventType: "action_denied", payload: [
                        "actionId": .string(action.id.uuidString),
                        "reason": .string("High-risk blocked.")
                    ])
                    completion(assistantMsg)
                    return
                }
                allowedActions.append(action)
            }

            let mediumActions = allowedActions.filter { $0.risk == .medium }
            if !mediumActions.isEmpty {
                guard let delegate = self.approvalDelegate else {
                    let content = "Approval required but UI not ready."
                    let assistantMsg = ChatMessage(role: .assistant, content: content)
                    self.messages.append(assistantMsg)
                    AuditLog.shared.log(eventType: "approval_skipped", payload: [
                        "reason": .string("No approvalDelegate.")
                    ])
                    completion(assistantMsg)
                    return
                }
                let allAllowed = allowedActions
                delegate.requestApproval(actions: mediumActions) { [weak self] approvedIds in
                    guard let self = self else { return }
                    let approvedSet = Set(approvedIds)
                    let toExecute = allAllowed.filter { approvedSet.contains($0.id) || $0.risk != .medium }
                    AuditLog.shared.log(eventType: "approval_reply", payload: [
                        "approvedCount": .number(Double(approvedIds.count)),
                        "toExecuteCount": .number(Double(toExecute.count))
                    ])
                    self.executeActions(toExecute, workspaceRoot: workspaceRoot, completion: completion)
                }
                return
            }

            self.executeActions(allowedActions, workspaceRoot: workspaceRoot, completion: completion)
        }
    }

    private func executeActions(
        _ actions: [ProposedAction],
        workspaceRoot: URL?,
        completion: @escaping (ChatMessage) -> Void
    ) {
        Task { @MainActor in
            if actions.isEmpty {
                let content = "No actions to run."
                let assistantMsg = ChatMessage(role: .assistant, content: content)
                self.messages.append(assistantMsg)
                completion(assistantMsg)
                return
            }

            guard let root = workspaceRoot else {
                let content = "Error: Workspace root is not set."
                let assistantMsg = ChatMessage(role: .assistant, content: content)
                self.messages.append(assistantMsg)
                AuditLog.shared.log(eventType: "fail_closed", payload: [
                    "reason": .string("Workspace root not set.")
                ])
                completion(assistantMsg)
                return
            }

            var results: [ToolResult] = []
            for action in actions {
                let result: ToolResult
                switch action.toolCall.name {
                case "file_search":
                    result = self.fileSearch.handle(toolCall: action.toolCall, workspaceRoot: root, policy: self.policy)
                case "file_read":
                    result = self.fileRead.handle(toolCall: action.toolCall, workspaceRoot: root, policy: self.policy)
                case "command_exec":
                    result = await self.commandExec.handle(toolCall: action.toolCall, workspaceRoot: root, policy: self.policy)
                default:
                    let content = "Error: Unknown tool \(action.toolCall.name)."
                    let assistantMsg = ChatMessage(role: .assistant, content: content)
                    self.messages.append(assistantMsg)
                    AuditLog.shared.log(eventType: "fail_closed", payload: [
                        "reason": .string("Unknown tool: \(action.toolCall.name).")
                    ])
                    completion(assistantMsg)
                    return
                }
                results.append(result)
                AuditLog.shared.log(eventType: "action_executed", payload: [
                    "toolCallId": .string(result.toolCallId.uuidString),
                    "name": .string(result.name),
                    "isError": .bool(result.isError)
                ])
            }

            let errorCount = results.filter { $0.isError }.count
            let content: String
            if errorCount > 0 {
                let firstError = results.first { $0.isError }?.errorMessage ?? "Unknown error"
                content = "Completed with errors (\(errorCount)/\(results.count)). First error: \(firstError)"
            } else {
                content = "Completed \(results.count) action(s) successfully."
            }
            let assistantMsg = ChatMessage(role: .assistant, content: content)
            self.messages.append(assistantMsg)
            completion(assistantMsg)
        }
    }
}
