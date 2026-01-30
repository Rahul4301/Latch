import Foundation

/// Protocol for the planner that turns chat messages into a structured AgentPlan (SRS: Agent Orchestrator).
protocol LLMClient {
    func plan(messages: [ChatMessage]) async -> AgentPlan
}
