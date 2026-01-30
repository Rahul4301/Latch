import Foundation

/// Deterministic mock planner. No network, no randomness. Only SRS tools; at most 1 action per plan (SRS, AGENTS.md).
final class MockLLMClient: LLMClient {

    private let policy: PolicyEngine

    init(policy: PolicyEngine = .shared) {
        self.policy = policy
    }

    func plan(messages: [ChatMessage]) async -> AgentPlan {
        let lastUserContent: String = messages
            .filter { $0.role == .user }
            .last?
            .content ?? ""
        let text: String = lastUserContent.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)

        if hasAmbiguousDate(text) {
            return AgentPlan(
                summary: "Ambiguous date.",
                questions: ["Which year do you mean? (e.g. 2024)"],
                actions: []
            )
        }

        let hasFindSearchLookFor = text.contains("find") || text.contains("search") || text.contains("look for")
        let hasReadOpenShow = text.contains("read") || text.contains("open file") || text.contains("show file")
        let hasRunExecuteListLs = text.contains("run") || text.contains("execute") || text.contains("list files") || text.contains("ls")

        let matchCount: Int = [hasFindSearchLookFor, hasReadOpenShow, hasRunExecuteListLs].filter { $0 }.count
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

        if hasFindSearchLookFor {
            let query: String = lastUserContent.trimmingCharacters(in: .whitespacesAndNewlines)
            let toolCall = ToolCall(
                name: "file_search",
                arguments: .object([
                    "query": .string(query),
                    "limit": .number(20)
                ])
            )
            return AgentPlan(
                summary: "Search files.",
                questions: [],
                actions: [
                    ProposedAction(
                        title: "Search files",
                        risk: .low,
                        toolCall: toolCall,
                        justification: "User asked to find or search.",
                        requiresApproval: false
                    )
                ]
            )
        }

        if hasReadOpenShow {
            let hasObviousPath = lastUserContent.contains("/") || lastUserContent.range(of: #"\S+\.\w+"#, options: .regularExpression) != nil
            if !hasObviousPath {
                return AgentPlan(
                    summary: "Read file requested.",
                    questions: ["Which file path should I read?"],
                    actions: []
                )
            }
            let path: String = extractPathHint(from: lastUserContent) ?? ""
            let toolCall = ToolCall(
                name: "file_read",
                arguments: .object(["path": .string(path)])
            )
            return AgentPlan(
                summary: "Read file.",
                questions: [],
                actions: [
                    ProposedAction(
                        title: "Read file",
                        risk: .low,
                        toolCall: toolCall,
                        justification: "User asked to read or open a file.",
                        requiresApproval: false
                    )
                ]
            )
        }

        if hasRunExecuteListLs {
            if looksDangerous(text) {
                return AgentPlan(
                    summary: "Command requested.",
                    questions: ["Do you want to run a safe command like listing files (/bin/ls), or something else? Please specify."],
                    actions: []
                )
            }
            let toolCall = ToolCall(
                name: "command_exec",
                arguments: .object([
                    "executablePath": .string("/bin/ls"),
                    "args": .array([])
                ])
            )
            return AgentPlan(
                summary: "Run command.",
                questions: [],
                actions: [
                    ProposedAction(
                        title: "Execute /bin/ls",
                        risk: .medium,
                        toolCall: toolCall,
                        justification: "User asked to run or list files.",
                        requiresApproval: true
                    )
                ]
            )
        }

        return AgentPlan(summary: "No action.", questions: [], actions: [])
    }

    private func hasAmbiguousDate(_ text: String) -> Bool {
        let monthPattern = #"last\s+(january|february|march|april|may|june|july|august|september|october|november|december)"#
        let yearPattern = #"20\d{2}|19\d{2}"#
        let hasLastMonth = text.range(of: monthPattern, options: [.regularExpression, .caseInsensitive]) != nil
        let hasYear = text.range(of: yearPattern, options: .regularExpression) != nil
        return hasLastMonth && !hasYear
    }

    private func extractPathHint(from content: String) -> String? {
        if content.contains("/") {
            if let match = content.range(of: #"[^\s]+/[^\s]+"#, options: .regularExpression) {
                return String(content[match])
            }
        }
        if let match = content.range(of: #"\S+\.\w+"#, options: .regularExpression) {
            return String(content[match])
        }
        return nil
    }

    private func looksDangerous(_ text: String) -> Bool {
        let dangerous = ["rm", "sudo", "chmod", "chown", "launchctl", "osascript", "curl", "wget", "ssh", "scp", "dd", "mkfs"]
        return dangerous.contains { text.contains($0) }
    }
}
