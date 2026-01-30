import Foundation

/// Deterministic mock planner. No network, no randomness, no guessing. Authoritative for MVP (SRS, AGENTS.md).
final class MockLLMClient: LLMClient {

    private let policy: PolicyEngine
    private let maxActionsPerTurn: Int

    init(policy: PolicyEngine = .shared) {
        self.policy = policy
        self.maxActionsPerTurn = policy.config.maxActionsPerTurn
    }

    func plan(messages: [ChatMessage]) async -> AgentPlan {
        let lastUserContent: String = messages
            .filter { $0.role == .user }
            .last?
            .content ?? ""
        let text: String = lastUserContent.lowercased()

        let hasFindOrSearch = text.contains("find") || text.contains("search")
        let hasRead = text.contains("read")
        let hasRunOrExecute = text.contains("run") || text.contains("execute")

        let matchCount: Int = [hasFindOrSearch, hasRead, hasRunOrExecute].filter { $0 }.count
        if matchCount == 0 {
            return AgentPlan(
                summary: "No matching intent.",
                questions: ["What would you like to do? (find/search, read a file, or run a command)"],
                actions: []
            )
        }
        if matchCount > 1 {
            return AgentPlan(
                summary: "Ambiguous request.",
                questions: ["Please choose one: find/search files, read a file, or run a command."],
                actions: []
            )
        }

        var actions: [ProposedAction] = []

        if hasFindOrSearch {
            let toolCall = ToolCall(
                name: "file_search",
                arguments: .object(["query": .string(lastUserContent)])
            )
            actions.append(ProposedAction(
                title: "Search files",
                risk: .low,
                toolCall: toolCall,
                justification: "User asked to find or search.",
                requiresApproval: false
            ))
        } else if hasRead {
            let toolCall = ToolCall(
                name: "file_read",
                arguments: .object(["path": .string("")])
            )
            actions.append(ProposedAction(
                title: "Read file",
                risk: .low,
                toolCall: toolCall,
                justification: "User asked to read a file.",
                requiresApproval: false
            ))
        } else if hasRunOrExecute {
            let toolCall = ToolCall(
                name: "command_exec",
                arguments: .object([
                    "executablePath": .string("/bin/ls"),
                    "args": .array([])
                ])
            )
            actions.append(ProposedAction(
                title: "Execute command",
                risk: .medium,
                toolCall: toolCall,
                justification: "User asked to run or execute.",
                requiresApproval: true
            ))
        }

        let capped: [ProposedAction] = Array(actions.prefix(maxActionsPerTurn))
        return AgentPlan(
            summary: "Single action plan.",
            questions: [],
            actions: capped
        )
    }
}
