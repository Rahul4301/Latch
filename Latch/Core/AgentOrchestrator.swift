import Foundation

/// Spine: accepts user message, plans via LLMClient, validates via PolicyEngine, requests approval for medium-risk,
/// executes via capabilities, logs via AuditLog. Fail-closed; no UI (SRS, AGENTS.md).
final class AgentOrchestrator {

    private let llm: LLMClient
    private let policy: PolicyEngine
    private let fileSearch = FileSearchCapability()
    private let fileRead = FileReadCapability()
    private let commandExec = CommandExecCapability()

    init(llm: LLMClient, policy: PolicyEngine = .shared) {
        self.llm = llm
        self.policy = policy
    }

    /// Processes one user message: appends to history, plans, validates, requests approval for medium-risk,
    /// executes approved actions, logs, returns templated assistant response.
    func process(
        userMessage: String,
        workspaceRoot: URL?,
        messages: inout [ChatMessage],
        requestApproval: (ProposedAction) async -> Bool
    ) async -> String {
        let userMsg = ChatMessage(role: .user, content: userMessage)
        messages.append(userMsg)

        AuditLog.shared.log(eventType: "user_message", payload: [
            "messageId": .string(userMsg.id.uuidString),
            "length": .number(Double(userMessage.count))
        ])

        let plan: AgentPlan = await llm.plan(messages: messages)

        AuditLog.shared.log(eventType: "plan_received", payload: [
            "summary": .string(plan.summary),
            "questionsCount": .number(Double(plan.questions.count)),
            "actionsCount": .number(Double(plan.actions.count))
        ])

        if !plan.questions.isEmpty && plan.actions.isEmpty {
            let response = "Clarification needed: " + plan.questions.joined(separator: " ")
            return response
        }

        if plan.actions.isEmpty {
            return "No actions to run."
        }

        var toExecute: [ProposedAction] = []
        for action in plan.actions {
            let (allowed, risk, reason) = policy.evaluate(action.toolCall, workspaceRoot: workspaceRoot)
            if !allowed {
                AuditLog.shared.log(eventType: "action_denied", payload: [
                    "actionId": .string(action.id.uuidString),
                    "tool": .string(action.toolCall.name),
                    "reason": .string(reason)
                ])
                return "Denied: \(reason)"
            }
            if risk == .high {
                AuditLog.shared.log(eventType: "action_denied", payload: [
                    "actionId": .string(action.id.uuidString),
                    "tool": .string(action.toolCall.name),
                    "reason": .string("High-risk blocked in MVP.")
                ])
                return "Denied: High-risk actions are blocked in MVP."
            }
            if risk == .medium {
                let approved: Bool = await requestApproval(action)
                AuditLog.shared.log(eventType: "approval_requested", payload: [
                    "actionId": .string(action.id.uuidString),
                    "approved": .bool(approved)
                ])
                if !approved {
                    continue
                }
            }
            toExecute.append(action)
        }

        if toExecute.isEmpty {
            return "No actions were approved to run."
        }

        guard let root = workspaceRoot else {
            AuditLog.shared.log(eventType: "fail_closed", payload: [
                "reason": .string("Workspace root not set.")
            ])
            return "Error: Workspace root is not set."
        }
        var results: [ToolResult] = []
        for action in toExecute {
            let result: ToolResult
            switch action.toolCall.name {
            case "file_search":
                result = fileSearch.handle(toolCall: action.toolCall, workspaceRoot: root, policy: policy)
            case "file_read":
                result = fileRead.handle(toolCall: action.toolCall, workspaceRoot: root, policy: policy)
            case "command_exec":
                result = await commandExec.handle(toolCall: action.toolCall, workspaceRoot: root, policy: policy)
            default:
                AuditLog.shared.log(eventType: "fail_closed", payload: [
                    "reason": .string("Unknown tool: \(action.toolCall.name).")
                ])
                return "Error: Unknown tool \(action.toolCall.name)."
            }
            results.append(result)
            AuditLog.shared.log(eventType: "action_executed", payload: [
                "toolCallId": .string(result.toolCallId.uuidString),
                "name": .string(result.name),
                "isError": .bool(result.isError)
            ])
        }

        let errorCount = results.filter { $0.isError }.count
        if errorCount > 0 {
            let firstError = results.first { $0.isError }?.errorMessage ?? "Unknown error"
            return "Completed with errors (\(errorCount)/\(results.count)). First error: \(firstError)"
        }
        return "Completed \(results.count) action(s) successfully."
    }
}
