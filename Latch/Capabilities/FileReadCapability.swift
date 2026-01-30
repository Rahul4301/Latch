import Foundation

/// Read-only, bounded file read. Policy-gated; enforces workspace containment and byte limits (SRS FR-10–FR-13, AGENTS.md).
final class FileReadCapability {

    private let defaultMaxBytes = 50_000
    private let hardCapBytes = 200_000

    func handle(toolCall: ToolCall, workspaceRoot: URL, policy: PolicyEngine) -> ToolResult {
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
              let pathVal = obj["path"],
              let path = pathVal.asString else {
            let output: JSONValue = .object([
                "denied": .bool(true),
                "reason": .string("file_read requires arguments.path (string).")
            ])
            return ToolResult(
                toolCallId: toolCall.id,
                name: toolCall.name,
                output: output,
                isError: true,
                errorMessage: "file_read requires arguments.path (string)."
            )
        }

        let url: URL = path.hasPrefix("/")
            ? URL(fileURLWithPath: path)
            : workspaceRoot.appendingPathComponent(path)

        if !FileManager.default.fileExists(atPath: url.path) {
            let output: JSONValue = .object([
                "denied": .bool(true),
                "reason": .string("File does not exist.")
            ])
            return ToolResult(
                toolCallId: toolCall.id,
                name: toolCall.name,
                output: output,
                isError: true,
                errorMessage: "File does not exist."
            )
        }

        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
              !isDirectory.boolValue else {
            let output: JSONValue = .object([
                "denied": .bool(true),
                "reason": .string("Path is a directory or does not exist.")
            ])
            return ToolResult(
                toolCallId: toolCall.id,
                name: toolCall.name,
                output: output,
                isError: true,
                errorMessage: "Path is a directory or does not exist."
            )
        }

        if !isPathUnderRoot(url, root: workspaceRoot) {
            let output: JSONValue = .object([
                "denied": .bool(true),
                "reason": .string("Path is outside workspace root.")
            ])
            return ToolResult(
                toolCallId: toolCall.id,
                name: toolCall.name,
                output: output,
                isError: true,
                errorMessage: "Path is outside workspace root."
            )
        }

        var maxBytes: Int = defaultMaxBytes
        if let maxVal = obj["maxBytes"], case .number(let n) = maxVal {
            maxBytes = min(hardCapBytes, max(0, Int(n)))
        }
        maxBytes = min(hardCapBytes, max(0, maxBytes))

        guard let fileSize = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.intValue else {
            let output: JSONValue = .object([
                "denied": .bool(true),
                "reason": .string("Could not read file attributes.")
            ])
            return ToolResult(
                toolCallId: toolCall.id,
                name: toolCall.name,
                output: output,
                isError: true,
                errorMessage: "Could not read file attributes."
            )
        }

        let toRead: Int = min(fileSize, maxBytes)
        let truncated: Bool = fileSize > maxBytes

        guard let fh = try? FileHandle(forReadingFrom: url) else {
            let output: JSONValue = .object([
                "denied": .bool(true),
                "reason": .string("Could not open file for reading.")
            ])
            return ToolResult(
                toolCallId: toolCall.id,
                name: toolCall.name,
                output: output,
                isError: true,
                errorMessage: "Could not open file for reading."
            )
        }
        defer { try? fh.close() }

        let data: Data = fh.readData(ofLength: toRead)

        let isBinary: Bool = data.contains(0) || (!data.isEmpty && String(data: data, encoding: .utf8) == nil)

        let content: String
        if isBinary {
            content = data.base64EncodedString()
        } else {
            content = String(data: data, encoding: .utf8) ?? ""
        }

        let output: JSONValue = .object([
            "content": .string(content),
            "isBinary": .bool(isBinary),
            "truncated": .bool(truncated)
        ])

        return ToolResult(
            toolCallId: toolCall.id,
            name: toolCall.name,
            output: output,
            isError: false,
            errorMessage: nil
        )
    }

    private func isPathUnderRoot(_ url: URL, root: URL) -> Bool {
        let normalizedRoot = root.resolvingSymlinksInPath().standardized.path
        let normalizedCandidate = url.resolvingSymlinksInPath().standardized.path
        if normalizedCandidate == normalizedRoot { return true }
        let prefix = normalizedRoot.hasSuffix("/") ? normalizedRoot : normalizedRoot + "/"
        return normalizedCandidate.hasPrefix(prefix)
    }
}
