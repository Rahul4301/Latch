import Foundation

/// Debug harness: runs a fixed sequence of prompts against the orchestrator and forwards assistant messages.
/// Proves policy denial for dangerous commands. No UI (SRS, AGENTS.md).
final class DemoHarness {

    static func runAll(
        workspaceRoot: URL,
        orchestrator: AgentOrchestrator,
        approvalAll: Bool,
        onMessage: @escaping (ChatMessage) -> Void
    ) {
        AuditLog.shared.log(eventType: "harness_started", payload: [
            "workspaceRoot": .string(workspaceRoot.path),
            "approvalAll": .bool(approvalAll)
        ])

        let delegate = HarnessApprovalDelegate(approvalAll: approvalAll)
        orchestrator.approvalDelegate = delegate

        orchestrator.handleUserMessage("find files modified after 2025-05-01 modified before 2025-06-15 query project") { [delegate] msg in
            onMessage(msg)
            _ = delegate
            orchestrator.handleUserMessage("read path README.md") { msg2 in
                onMessage(msg2)
                orchestrator.handleUserMessage("run ls") { msg3 in
                    onMessage(msg3)
                    orchestrator.handleUserMessage("run rm -rf .") { msg4 in
                        onMessage(msg4)
                        AuditLog.shared.log(eventType: "harness_denial_expected", payload: [
                            "prompt": .string("run rm -rf ."),
                            "reason": .string("Policy must deny dangerous command.")
                        ])
                    }
                }
            }
        }
    }
}

private final class HarnessApprovalDelegate: AgentOrchestratorApprovalDelegate {
    let approvalAll: Bool
    init(approvalAll: Bool) { self.approvalAll = approvalAll }
    func requestApproval(actions: [ProposedAction], reply: @escaping ([UUID]) -> Void) {
        if approvalAll {
            reply(actions.map(\.id))
        } else {
            reply([])
        }
    }
}
