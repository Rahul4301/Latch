import Foundation

enum MessageRole: String, Codable {
    case system
    case user
    case assistant
}

struct ChatMessage: Codable, Identifiable {
    let id: UUID
    let role: MessageRole
    let content: String
    let timestamp: Date

    init(id: UUID = UUID(), role: MessageRole, content: String, timestamp: Date = Date()) {
        self.id = id
        self.role = role
        self.content = content
        self.timestamp = timestamp
    }
}

struct ToolCall: Codable, Identifiable {
    let id: UUID
    let name: String
    let arguments: JSONValue

    init(id: UUID = UUID(), name: String, arguments: JSONValue) {
        self.id = id
        self.name = name
        self.arguments = arguments
    }
}

struct ToolResult: Codable {
    let toolCallId: UUID
    let name: String
    let output: JSONValue
    let isError: Bool
    let errorMessage: String?
}

enum RiskLevel: String, Codable {
    case low
    case medium
    case high
}

struct ProposedAction: Codable, Identifiable {
    let id: UUID
    let title: String
    let risk: RiskLevel
    let toolCall: ToolCall
    let justification: String
    let requiresApproval: Bool

    init(id: UUID = UUID(), title: String, risk: RiskLevel, toolCall: ToolCall, justification: String, requiresApproval: Bool) {
        self.id = id
        self.title = title
        self.risk = risk
        self.toolCall = toolCall
        self.justification = justification
        self.requiresApproval = requiresApproval
    }
}

struct AgentPlan: Codable {
    let summary: String
    let questions: [String]
    let actions: [ProposedAction]
}
