import Foundation
import Dispatch
/// Append-only JSONL audit log in Application Support/Latch (AGENTS.md, SRS FR-4).
/// All disk I/O is serialized on a private queue. Redaction applied before write; rotation at 50MB.
final class AuditLog {

    static let shared = AuditLog()

    private let queue: DispatchQueue = DispatchQueue(label: "com.latch.auditlog", qos: .utility)
    private let maxLogBytes: UInt64 = 50 * 1024 * 1024  // 50MB
    private let redactStringLengthThreshold = 80
    private let secretPrefix = "sk-"

    private var appSupportDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Latch", isDirectory: true)
    }

    private func logFileURL() -> URL {
        appSupportDirectory.appendingPathComponent("audit.jsonl", isDirectory: false)
    }

    private init() {}

    /// Appends one JSONL line. Payload is redacted before write (long strings and sk- prefix).
    func log(eventType: String, payload: [String: JSONValue]) {
        queue.async(execute: { [weak self] in
            guard let self = self else { return }
            let redactedPayload: [String: JSONValue] = self.redact(payload)
            let line: String = self.serializeLine(eventType: eventType, payload: redactedPayload)
            let url: URL = self.logFileURL()

            self.ensureDirectory()

            let size: UInt64 = self.currentLogFileSize()
            if size > self.maxLogBytes {
                self.rotateLog()
            }

            guard let data: Data = (line + "\n").data(using: .utf8) else { return }

            if FileManager.default.fileExists(atPath: url.path) {
                guard let h: FileHandle = FileHandle(forWritingAtPath: url.path) else { return }
                h.seekToEndOfFile()
                h.write(data)
                try? h.close()
            } else {
                try? data.write(to: url)
            }
        })
    }


    /// Returns the last `limit` lines. Reads from end of file to stay safe for large files.
    func readRecent(limit: Int) -> [String] {
        queue.sync {
            let url: URL = self.logFileURL()
            guard limit > 0,
                  FileManager.default.fileExists(atPath: url.path) else {
                return []
            }
            let size: UInt64 = self.currentLogFileSize()
            guard size > 0 else { return [] }
            let tailBytes: UInt64 = min(size, 2 * 1024 * 1024)
            guard let f: FileHandle = try? FileHandle(forReadingFrom: url) else { return [] }
            defer { try? f.close() }
            f.seek(toFileOffset: size - tailBytes)
            let data: Data = f.readDataToEndOfFile()
            guard let text: String = String(data: data, encoding: .utf8) else { return [] }
            var lines: [String] = text.components(separatedBy: "\n").filter { !$0.isEmpty }
            if size > tailBytes, !lines.isEmpty {
                lines.removeFirst()
            }
            return Array(lines.suffix(limit))
        }
    }

    /// Copies the current log file to a temp location and returns its URL. Caller may present for export.
    func export() throws -> URL {
        try queue.sync {
            self.ensureDirectory()
            let url: URL = self.logFileURL()
            let tempDir: URL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
            let dest: URL = tempDir.appendingPathComponent("audit.jsonl", isDirectory: false)
            if FileManager.default.fileExists(atPath: url.path) {
                try FileManager.default.copyItem(at: url, to: dest)
            } else {
                try Data().write(to: dest)
            }
            return dest
        }
    }

    // MARK: - Private

    private func redact(_ payload: [String: JSONValue]) -> [String: JSONValue] {
        let result: [String: JSONValue] = payload.mapValues { redactValue($0) }
        return result
    }

    private func redactValue(_ value: JSONValue) -> JSONValue {
        switch value {
        case .string(let s):
            if s.count > redactStringLengthThreshold || s.hasPrefix(secretPrefix) {
                return .string("[REDACTED]")
            }
            return .string(s)
        case .object(let o):
            let redacted: [String: JSONValue] = o.mapValues { redactValue($0) }
            return .object(redacted)
        case .array(let a):
            let redacted: [JSONValue] = a.map { redactValue($0) }
            return .array(redacted)
        case .number, .bool, .null:
            return value
        }
    }

    private func serializeLine(eventType: String, payload: [String: JSONValue]) -> String {
        let timestampString: String = ISO8601DateFormatter().string(from: Date())
        var entry: [String: JSONValue] = [:]
        entry["timestamp"] = .string(timestampString)
        entry["eventType"] = .string(eventType)
        entry["payload"] = .object(payload)
        let encoder = JSONEncoder()
        encoder.outputFormatting = []
        if #available(macOS 10.15, *) {
            encoder.outputFormatting = .withoutEscapingSlashes
        }
        guard let data: Data = try? encoder.encode(JSONValue.object(entry)),
              let line: String = String(data: data, encoding: .utf8) else {
            return "{\"timestamp\":\"\",\"eventType\":\"\",\"payload\":{}}"
        }
        return line
    }

    private func ensureDirectory() -> Void {
        try? FileManager.default.createDirectory(at: appSupportDirectory, withIntermediateDirectories: true)
    }

    private func currentLogFileSize() -> UInt64 {
        let url: URL = logFileURL()
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let num = attrs[.size] as? NSNumber else {
            return 0
        }
        return num.uint64Value
    }

    private func rotateLog() -> Void {
        let url: URL = logFileURL()
        let one: URL = appSupportDirectory.appendingPathComponent("audit.jsonl.1", isDirectory: false)
        let two: URL = appSupportDirectory.appendingPathComponent("audit.jsonl.2", isDirectory: false)
        let three: URL = appSupportDirectory.appendingPathComponent("audit.jsonl.3", isDirectory: false)
        try? FileManager.default.removeItem(at: three)
        if FileManager.default.fileExists(atPath: two.path) {
            try? FileManager.default.moveItem(at: two, to: three)
        }
        if FileManager.default.fileExists(atPath: one.path) {
            try? FileManager.default.moveItem(at: one, to: two)
        }
        if FileManager.default.fileExists(atPath: url.path) {
            try? FileManager.default.moveItem(at: url, to: one)
        }
        try? Data().write(to: url)
    }
}

