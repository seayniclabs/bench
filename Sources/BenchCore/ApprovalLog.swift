import Foundation
import MCP

/// Local record of every device-write approval: asked, granted, declined or refused.
/// One JSON object per line. The file never leaves the machine, and bodies are not
/// logged: a value is kept only for the arguments a person approves (port, identifier,
/// action), and every other value is replaced by its length.
public enum ApprovalLog {
    public enum Decision: String, Sendable {
        case requested, approved, declined, refused
    }

    /// Keys whose values are shown in the log, because they name the device.
    static let visibleKeys: Set<String> = ["port", "identifier", "action", "report_type", "device"]

    /// $BENCH_APPROVAL_LOG, else $XDG_STATE_HOME/bench/approvals.jsonl, else
    /// ~/.local/state/bench/approvals.jsonl.
    public static func path(env: [String: String]) -> URL {
        if let explicit = env["BENCH_APPROVAL_LOG"], !explicit.isEmpty {
            return URL(fileURLWithPath: (explicit as NSString).expandingTildeInPath)
        }
        let home = env["HOME"] ?? NSHomeDirectory()
        let base = env["XDG_STATE_HOME"].flatMap { $0.isEmpty ? nil : $0 } ?? "\(home)/.local/state"
        return URL(fileURLWithPath: base).appendingPathComponent("bench/approvals.jsonl")
    }

    /// Arguments with every value except the device-naming ones replaced by a size.
    public static func redact(_ arguments: [String: Value]?) -> [String: String] {
        var out: [String: String] = [:]
        for (key, value) in arguments ?? [:] {
            if visibleKeys.contains(key), let text = value.stringValue {
                out[key] = String(text.prefix(200))
            } else if let text = value.stringValue {
                out[key] = "<redacted \(text.count) chars>"
            } else {
                out[key] = "<redacted>"
            }
        }
        return out
    }

    /// Appends one line. Never throws: a logging failure must not block or break a call.
    public static func record(
        env: [String: String],
        tool: String,
        decision: Decision,
        approvedBy: String?,
        arguments: [String: Value]?
    ) {
        let line: [String: Any] = [
            "ts": ISO8601DateFormatter().string(from: Date()),
            "tool": tool,
            "decision": decision.rawValue,
            "approved_by": approvedBy.map { $0 as Any } ?? NSNull(),
            "arguments": redact(arguments),
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: line, options: [.sortedKeys]) else { return }
        let url = path(env: env)
        let fm = FileManager.default
        do {
            try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            if !fm.fileExists(atPath: url.path) {
                fm.createFile(atPath: url.path, contents: nil, attributes: [.posixPermissions: 0o600])
            }
            let handle = try FileHandle(forWritingTo: url)
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: data + Data([10]))
        } catch {
            return
        }
    }
}
