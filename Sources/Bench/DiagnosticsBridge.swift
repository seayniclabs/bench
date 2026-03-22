import Foundation

/// Queries macOS system logs and IOKit for USB errors related to a device.
enum DiagnosticsBridge {

    /// Diagnostic result for a device
    struct DiagnosticResult: Sendable {
        let identifier: String
        let timeframe: String
        let errorCount: Int
        let errorTypes: [String: Int]   // error type -> count
        let lastErrorTimestamp: String?
        let logEntries: [String]        // relevant log lines (capped)
    }

    /// Diagnose USB errors for a device using system logs
    static func diagnose(identifier: String, timeframe: String) -> DiagnosticResult {
        let device = IOKitBridge.findDevice(identifier: identifier)

        // Build search terms from device info
        var searchTerms: [String] = []
        if let device = device {
            let vid = String(format: "%04x", device.vendorID)
            let pid = String(format: "%04x", device.productID)
            searchTerms.append(vid)
            searchTerms.append(pid)
            if !device.serialNumber.isEmpty {
                searchTerms.append(device.serialNumber)
            }
            // Add device name words (skip very short/common words)
            let nameWords = device.name.split(separator: " ").map(String.init)
            for word in nameWords where word.count > 3 {
                searchTerms.append(word)
            }
        } else {
            // No device found, search by raw identifier
            searchTerms.append(identifier)
        }

        // Run log show
        let logLines = querySystemLogs(timeframe: timeframe, searchTerms: searchTerms)

        // Parse results
        var errorTypes: [String: Int] = [:]
        var lastTimestamp: String?

        for line in logLines {
            let lower = line.lowercased()

            // Categorize error types
            if lower.contains("error") || lower.contains("fault") || lower.contains("fail") {
                let errorType = categorizeError(line)
                errorTypes[errorType, default: 0] += 1
            }

            // Extract timestamp (log show compact format: YYYY-MM-DD HH:MM:SS.xxx)
            if let ts = extractTimestamp(line) {
                lastTimestamp = ts
            }
        }

        let totalErrors = errorTypes.values.reduce(0, +)

        // Cap log entries to avoid overwhelming output
        let cappedEntries = Array(logLines.prefix(25))

        return DiagnosticResult(
            identifier: device?.name ?? identifier,
            timeframe: timeframe,
            errorCount: totalErrors,
            errorTypes: errorTypes,
            lastErrorTimestamp: lastTimestamp,
            logEntries: cappedEntries
        )
    }

    // MARK: - Private

    /// Query system logs for USB-related entries matching search terms
    private static func querySystemLogs(timeframe: String, searchTerms: [String]) -> [String] {
        let predicate = "subsystem == \"com.apple.usb\" OR subsystem == \"com.apple.iokit\""

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/log")
        process.arguments = [
            "show",
            "--predicate", predicate,
            "--last", timeframe,
            "--style", "compact"
        ]

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return ["Failed to query system logs: \(error.localizedDescription)"]
        }

        let outData = stdout.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: outData, encoding: .utf8) else {
            return []
        }

        let allLines = output.components(separatedBy: "\n")

        // Filter lines that match any search term
        let lowerTerms = searchTerms.map { $0.lowercased() }
        let matched = allLines.filter { line in
            let lower = line.lowercased()
            return lowerTerms.contains { term in lower.contains(term) }
        }

        return matched
    }

    /// Categorize a log line into an error type
    private static func categorizeError(_ line: String) -> String {
        let lower = line.lowercased()

        if lower.contains("overcurrent") { return "Overcurrent" }
        if lower.contains("timeout") { return "Timeout" }
        if lower.contains("stall") { return "Endpoint Stall" }
        if lower.contains("reset") { return "Device Reset" }
        if lower.contains("disconnect") || lower.contains("detach") { return "Unexpected Disconnect" }
        if lower.contains("enumerat") { return "Enumeration Error" }
        if lower.contains("power") { return "Power Error" }
        if lower.contains("bandwidth") { return "Bandwidth Error" }
        if lower.contains("pipe") { return "Pipe Error" }
        if lower.contains("suspend") { return "Suspend Error" }
        if lower.contains("not responding") { return "Device Not Responding" }

        return "General Error"
    }

    /// Extract timestamp from a log show compact line
    private static func extractTimestamp(_ line: String) -> String? {
        // Compact format: "2026-03-22 14:30:00.123456-0500  ..."
        let pattern = #"(\d{4}-\d{2}-\d{2}\s+\d{2}:\d{2}:\d{2}\.\d+)"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
              let range = Range(match.range(at: 1), in: line) else {
            return nil
        }
        return String(line[range])
    }
}
