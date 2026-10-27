import BenchCore
import Foundation

struct ToolRunResult {
    let status: Int32
    let stdout: String
    let stderr: String
}

enum ToolRunError: Error, CustomStringConvertible {
    case notFound(String)
    case launchFailed(String)

    var description: String {
        switch self {
        case .notFound(let name):
            return "'\(name)' was not found as an executable. Install it or pass its absolute path."
        case .launchFailed(let reason):
            return "the tool could not be started (\(reason))."
        }
    }
}

/// Runs external tools with an argument array. No shell is ever involved, so
/// values from the caller are passed as data and cannot inject commands.
enum ToolRunner {
    static func run(name: String, arguments: [String]) throws -> ToolRunResult {
        let process = Process()
        process.executableURL = try resolve(name)
        process.arguments = arguments

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        do {
            try process.run()
        } catch {
            throw ToolRunError.launchFailed(error.localizedDescription)
        }
        // Read before waiting, so a full pipe cannot deadlock the child.
        let outData = stdout.fileHandleForReading.readDataToEndOfFile()
        let errData = stderr.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        return ToolRunResult(
            status: process.terminationStatus,
            stdout: String(decoding: outData, as: UTF8.self),
            stderr: String(decoding: errData, as: UTF8.self)
        )
    }

    /// An absolute path is used as given. A bare name is searched on PATH.
    static func resolve(_ name: String) throws -> URL {
        let fm = FileManager.default
        if name.hasPrefix("/") {
            guard fm.isExecutableFile(atPath: name) else { throw ToolRunError.notFound(name) }
            return URL(fileURLWithPath: name)
        }
        guard !name.isEmpty, !name.contains("/") else { throw ToolRunError.notFound(name) }
        let path = ProcessInfo.processInfo.environment["PATH"] ?? "/usr/bin:/bin"
        for dir in path.split(separator: ":") {
            let candidate = "\(dir)/\(name)"
            if fm.isExecutableFile(atPath: candidate) {
                return URL(fileURLWithPath: candidate)
            }
        }
        throw ToolRunError.notFound(name)
    }

    /// A quoted string for display only. It is never executed.
    static func display(_ argv: [String]) -> String {
        let safe = Set("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789/._-:=+")
        return argv.map { arg in
            if !arg.isEmpty && arg.allSatisfy({ safe.contains($0) }) { return arg }
            return "'" + arg.replacingOccurrences(of: "'", with: "'\\''") + "'"
        }.joined(separator: " ")
    }
}
