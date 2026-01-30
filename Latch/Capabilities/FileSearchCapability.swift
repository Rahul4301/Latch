import Foundation

/// Metadata-only file search within workspace. No content reads (SRS FR-6–FR-9, AGENTS.md).
final class FileSearchCapability {

    private let defaultLimit = 20
    private let maxLimit = 100
    private let iso8601 = ISO8601DateFormatter()

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

        let obj: [String: JSONValue]? = toolCall.arguments.asObject
        let query: String? = obj?["query"]?.asString
        let modifiedAfterStr: String? = obj?["modifiedAfter"]?.asString
        let modifiedBeforeStr: String? = obj?["modifiedBefore"]?.asString

        var limit: Int = defaultLimit
        if let limitVal = obj?["limit"], case .number(let n) = limitVal {
            limit = min(maxLimit, max(0, Int(n)))
        }
        limit = min(maxLimit, max(0, limit))

        let modifiedAfter: Date? = modifiedAfterStr.flatMap { iso8601.date(from: $0) }
        let modifiedBefore: Date? = modifiedBeforeStr.flatMap { iso8601.date(from: $0) }

        let keys: Set<URLResourceKey> = [.isRegularFileKey, .contentModificationDateKey, .fileSizeKey]
        var results: [JSONValue] = []

        guard let enumerator = FileManager.default.enumerator(
            at: workspaceRoot,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles]
        ) else {
            let output: JSONValue = .object([
                "denied": .bool(true),
                "reason": .string("Could not enumerate workspace.")
            ])
            return ToolResult(
                toolCallId: toolCall.id,
                name: toolCall.name,
                output: output,
                isError: true,
                errorMessage: "Could not enumerate workspace."
            )
        }

        let prefix = workspaceRoot.resolvingSymlinksInPath().standardized.path
        let prefixWithSlash = prefix.hasSuffix("/") ? prefix : prefix + "/"

        for case let itemURL as URL in enumerator {
            if results.count >= limit { break }

            let resolved = itemURL.resolvingSymlinksInPath().standardized
            guard resolved.path.hasPrefix(prefixWithSlash) || resolved.path == prefix else {
                enumerator.skipDescendants()
                continue
            }

            guard let values = try? itemURL.resourceValues(forKeys: keys),
                  values.isRegularFile == true else {
                continue
            }

            let modDate: Date? = values.contentModificationDate
            let fileSize: Int = values.fileSize ?? 0

            if let after = modifiedAfter, let d = modDate, d < after { continue }
            if let before = modifiedBefore, let d = modDate, d > before { continue }

            let pathStr: String = itemURL.path
            let filename: String = itemURL.lastPathComponent
            if let q = query, !q.isEmpty, !pathStr.contains(q) && !filename.contains(q) {
                continue
            }

            let lastModifiedStr: String = modDate.map { iso8601.string(from: $0) } ?? ""

            let entry: JSONValue = .object([
                "path": .string(pathStr),
                "filename": .string(filename),
                "lastModified": .string(lastModifiedStr),
                "fileSizeBytes": .number(Double(fileSize))
            ])
            results.append(entry)
        }

        let output: JSONValue = .array(results)
        return ToolResult(
            toolCallId: toolCall.id,
            name: toolCall.name,
            output: output,
            isError: false,
            errorMessage: nil
        )
    }
}
