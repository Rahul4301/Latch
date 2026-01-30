import Foundation

/// Configuration loaded from DefaultPolicy.json. Deny-by-default if file missing or invalid.
struct PolicyConfig: Codable {
    let allowedTools: [String]
    let allowedExecutables: [String]
    let blockedTokens: [String]
    let maxActionsPerTurn: Int
    let defaultTimeoutSeconds: Int
    let maxStdoutBytes: Int
    let maxStderrBytes: Int

    /// Safe deny-by-default used when bundle JSON is missing or invalid (AGENTS.md fail-closed).
    static var denyByDefault: PolicyConfig {
        PolicyConfig(
            allowedTools: [],
            allowedExecutables: [],
            blockedTokens: ["rm", "sudo", "chmod", "chown", "launchctl", "cron", "osascript", "curl", "wget", "ssh", "scp", "rsync", "nc", "telnet", "|", "&&", ";", ">", ">>", "`", "$(", "mkfs", "dd"],
            maxActionsPerTurn: 0,
            defaultTimeoutSeconds: 10,
            maxStdoutBytes: 200_000,
            maxStderrBytes: 200_000
        )
    }
}

final class PolicyEngine {

    static let shared = PolicyEngine()

    private(set) var config: PolicyConfig

    init() {
        if let url = Bundle.main.url(forResource: "DefaultPolicy", withExtension: "json"),
           let data = try? Data(contentsOf: url),
           let decoded = try? JSONDecoder().decode(PolicyConfig.self, from: data) {
            self.config = decoded
        } else {
            self.config = .denyByDefault
        }
    }

    /// Returns (allowed, risk, reason). Deterministic; no file writes or network.
    func evaluate(_ toolCall: ToolCall, workspaceRoot: URL?) -> (allowed: Bool, risk: RiskLevel, reason: String) {
        let name = toolCall.name
        guard config.allowedTools.contains(name) else {
            return (false, .high, "Tool '\(name)' is not in allowedTools.")
        }

        switch name {
        case "file_search":
            return (true, .low, "")

        case "file_read":
            guard let root = workspaceRoot else {
                return (false, .high, "Workspace root is not set.")
            }
            guard let obj = toolCall.arguments.asObject,
                  let pathVal = obj["path"],
                  let path = pathVal.asString else {
                return (false, .high, "file_read requires arguments.path (string).")
            }
            let fileURL = URL(fileURLWithPath: path)
            if !isPathUnderRoot(fileURL, root: root) {
                return (false, .high, "Path is outside workspace root.")
            }
            return (true, .low, "")

        case "command_exec":
            guard let obj = toolCall.arguments.asObject,
                  let execVal = obj["executablePath"],
                  let execPath = execVal.asString,
                  execPath.hasPrefix("/") else {
                return (false, .high, "command_exec requires arguments.executablePath (absolute path string).")
            }
            guard config.allowedExecutables.contains(execPath) else {
                return (false, .high, "Executable '\(execPath)' is not in allowedExecutables.")
            }
            guard let argsVal = obj["args"] else {
                return (false, .high, "command_exec requires arguments.args (array).")
            }
            guard let argsArray = argsVal.asArray else {
                return (false, .high, "arguments.args must be an array of strings.")
            }
            var allStrings: [String] = [execPath]
            for v in argsArray {
                if let s = v.asString {
                    allStrings.append(s)
                } else {
                    return (false, .high, "arguments.args must contain only strings.")
                }
            }
            for token in config.blockedTokens {
                for s in allStrings {
                    if s.contains(token) {
                        return (false, .high, "Argument contains blocked token '\(token)'.")
                    }
                }
            }
            // optional timeoutSeconds number is accepted; executor enforces range
            return (true, .medium, "")

        default:
            return (false, .high, "Tool '\(name)' is not allowed.")
        }
    }

    /// One-line preview for UI; max 200 chars; redact strings longer than 80 chars as [REDACTED].
    func sanitizedPreview(_ toolCall: ToolCall) -> String {
        let name = toolCall.name
        var parts: [String] = [name]
        if let obj = toolCall.arguments.asObject {
            for (key, val) in obj.sorted(by: { $0.key < $1.key }) {
                let desc: String
                switch val {
                case .string(let s):
                    desc = s.count > 80 ? "[REDACTED]" : s
                case .array(let a):
                    desc = "[\(a.count) items]"
                case .object(let o):
                    desc = "[\(o.count) keys]"
                case .number(let n):
                    desc = "\(n)"
                case .bool(let b):
                    desc = b ? "true" : "false"
                case .null:
                    desc = "null"
                }
                parts.append("\(key)=\(desc)")
            }
        }
        let oneLine = parts.joined(separator: " ")
        if oneLine.count <= 200 {
            return oneLine
        }
        return String(oneLine.prefix(197)) + "..."
    }

    // MARK: - Private

    /// Same containment logic as WorkspaceManager: normalize with resolvingSymlinksInPath + standardized, then prefix check.
    private func isPathUnderRoot(_ url: URL, root: URL) -> Bool {
        let normalizedRoot = root.resolvingSymlinksInPath().standardized.path
        let normalizedCandidate = url.resolvingSymlinksInPath().standardized.path
        if normalizedCandidate == normalizedRoot { return true }
        let prefix = normalizedRoot.hasSuffix("/") ? normalizedRoot : normalizedRoot + "/"
        return normalizedCandidate.hasPrefix(prefix)
    }
}
