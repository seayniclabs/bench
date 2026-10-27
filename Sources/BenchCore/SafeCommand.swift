import Foundation

/// Validation for values that reach an external tool.
public enum DevicePath {
    /// Serial device paths on macOS: /dev/cu.* and /dev/tty.*. `\z` (not `$`)
    /// so a trailing newline cannot match.
    static let pattern = "^/dev/(cu|tty)\\.[A-Za-z0-9._-]+\\z"
    private static let regex = try? NSRegularExpression(pattern: pattern)

    public static func isValid(_ port: String) -> Bool {
        guard let regex else { return false }
        let range = NSRange(port.startIndex..<port.endIndex, in: port)
        return regex.numberOfMatches(in: port, options: [], range: range) == 1
    }

    /// nil when the path is a valid serial device path; otherwise the reason.
    public static func problem(_ port: String) -> String? {
        if isValid(port) { return nil }
        return "Invalid port \(jsonString(port)): a serial port must look like /dev/cu.usbserial-2120 or /dev/tty.usbmodem14101 (letters, digits, dot, underscore, hyphen after /dev/cu. or /dev/tty.)."
    }
}

/// The hid_send actions that only read. Everything else needs approval.
public enum HIDAction {
    public static let readActions: Set<String> = ["get_report", "list_reports"]

    /// The one normalization used by both the handler and the approval check.
    public static func normalize(_ raw: String) -> String {
        raw.lowercased()
    }

    /// Fails closed: a missing or unknown action needs approval.
    public static func isRead(_ raw: String?) -> Bool {
        guard let raw else { return false }
        return readActions.contains(normalize(raw))
    }
}
