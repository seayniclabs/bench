import Foundation

/// Answers requests that arrive before `initialize`.
///
/// The MCP Swift SDK (0.12.1) rejects them with "Server is not initialized" under a new random
/// id instead of the request's id, so a client waiting on its own id never sees the reply.
/// Antigravity opens with `server/discover` (MCP 2026-07-28) and hung that way. Replying here
/// with the request's id lets the client fall back to `initialize`.
public struct PreInitGuard: Sendable {
    public private(set) var initialized = false

    public init() {}

    /// The reply to send instead of passing `message` on to the server, or nil to pass it on.
    public mutating func intercept(_ message: Data) -> Data? {
        if initialized { return nil }
        guard let request = try? JSONSerialization.jsonObject(with: message) as? [String: Any],
              let method = request["method"] as? String else { return nil }
        if method == "initialize" {
            initialized = true
            return nil
        }
        // Notifications have no id and need no reply.
        guard let id = request["id"], !(id is NSNull) else { return nil }
        var reply: [String: Any] = ["jsonrpc": "2.0", "id": id]
        if method == "ping" {
            reply["result"] = [String: Any]()
        } else {
            reply["error"] = ["code": -32601, "message": "Method not found: \(method). Send initialize first."]
        }
        return try? JSONSerialization.data(withJSONObject: reply)
    }
}
