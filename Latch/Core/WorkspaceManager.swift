import Foundation

/// Manages the user-selected workspace root. Path containment is enforced here;
/// all file_search, file_read, and command_exec must be scoped to this root (AGENTS.md, SRS FR-1, FR-7, FR-11, FR-18).
final class WorkspaceManager {

    static let shared = WorkspaceManager()

    private let defaultsKey = "LatchWorkspaceRoot"

    private init() {}

    /// Stores the workspace root path in UserDefaults. Only persists if the URL exists and is a directory.
    /// Uses path string only (no security-scoped bookmark) for MVP.
    /// - Returns: `true` only when the path was stored successfully.
    func setWorkspaceRoot(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            return false
        }
        UserDefaults.standard.set(url.path, forKey: defaultsKey)
        return true
    }

    /// Returns the current workspace root URL, or `nil` if none is set or the path no longer exists / is not a directory.
    func getWorkspaceRoot() -> URL? {
        guard let path = UserDefaults.standard.string(forKey: defaultsKey) else {
            return nil
        }
        let url = URL(fileURLWithPath: path)
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            // Fail-closed: invalid or missing root → return nil so callers never assume a workspace (AGENTS.md).
            return nil
        }
        return url
    }

    /// Returns whether the given URL is under the current workspace root.
    func isUnderWorkspace(_ url: URL) -> Bool {
        guard let root = getWorkspaceRoot() else {
            // Fail-closed: no root means no valid scope—deny all paths so we never act outside workspace (AGENTS.md).
            return false
        }
        // Resolving symlinks matters: a path like /workspace/out-link → /etc would otherwise pass a string-prefix check
        // while pointing outside the workspace; resolving first makes the real location visible for containment.
        let normalizedRoot = root.resolvingSymlinksInPath().standardized.path
        let normalizedCandidate = url.resolvingSymlinksInPath().standardized.path
        if normalizedCandidate == normalizedRoot {
            return true
        }
        // Prefix check after normalization rejects .. and symlink tricks; trailing "/" avoids false prefix matches.
        let prefix = normalizedRoot.hasSuffix("/") ? normalizedRoot : normalizedRoot + "/"
        return normalizedCandidate.hasPrefix(prefix)
    }
}
