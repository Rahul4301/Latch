import Foundation

/// Policy-gated command execution. Evaluates via PolicyEngine, then runs via LocalExecutor (AGENTS.md, SRS FR-14–FR-19).
final class CommandExecCapability {

    private let executor = LocalExecutor()

    func handle(toolCall: ToolCall, workspaceRoot: URL, policy: PolicyEngine) async -> ToolResult {
        let (allowed, _, reason) = policy.evaluate(toolCall, workspaceRoot: workspaceRoot)

        if !allowed {
            let output: JSONValue = .object([
                "denied": .bool(true),
                "reason": .string(reason)
            ])
            return ToolResult(
                toolCallId: toolCall.id,
                name: toolCall.name,
                output: output,
                isError: true,
                errorMessage: reason
            )
        }

        guard let obj = toolCall.arguments.asObject,
              let execVal = obj["executablePath"],
              let executablePath = execVal.asString,
              let argsVal = obj["args"],
              let argsArray = argsVal.asArray else {
            let output: JSONValue = .object([
                "denied": .bool(true),
                "reason": .string("command_exec requires executablePath and args.")
            ])
            return ToolResult(
                toolCallId: toolCall.id,
                name: toolCall.name,
                output: output,
                isError: true,
                errorMessage: "command_exec requires executablePath and args."
            )
        }

        var args: [String] = []
        for v in argsArray {
            if let s = v.asString {
                args.append(s)
            } else {
                let output: JSONValue = .object([
                    "denied": .bool(true),
                    "reason": .string("arguments.args must be an array of strings.")
                ])
                return ToolResult(
                    toolCallId: toolCall.id,
                    name: toolCall.name,
                    output: output,
                    isError: true,
                    errorMessage: "arguments.args must be an array of strings."
                )
            }
        }

        var timeoutSeconds: Double = Double(policy.config.defaultTimeoutSeconds)
        if let timeoutVal = obj["timeoutSeconds"] {
            if case .number(let n) = timeoutVal {
                timeoutSeconds = n
            }
        }

        let result = await executor.run(
            executablePath: executablePath,
            args: args,
            workingDirectory: workspaceRoot,
            timeoutSeconds: timeoutSeconds,
            maxStdoutBytes: policy.config.maxStdoutBytes,
            maxStderrBytes: policy.config.maxStderrBytes
        )

        let output: JSONValue = .object([
            "exitCode": .number(Double(result.exitCode)),
            "stdout": .string(result.stdout),
            "stderr": .string(result.stderr),
            "stdoutTruncated": .bool(result.stdoutTruncated),
            "stderrTruncated": .bool(result.stderrTruncated),
            "didTimeout": .bool(result.didTimeout)
        ])

        return ToolResult(
            toolCallId: toolCall.id,
            name: toolCall.name,
            output: output,
            isError: false,
            errorMessage: nil
        )
    }
}
