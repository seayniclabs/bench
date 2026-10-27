import Foundation
import Testing

/// Drives the built Bench binary over stdio, the way an MCP client does.
/// Runs with an empty environment unless a test sets one.
@Suite("Stdio server", .serialized)
struct StdioServerTests {
    static let binaryPath: String = {
        if let override = ProcessInfo.processInfo.environment["BENCH_TEST_BINARY"] {
            return override
        }
        // Tests/BenchTests/StdioServerTests.swift -> repo root
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return root.appendingPathComponent(".build/debug/Bench").path
    }()

    @Test("Starts with an empty environment, reports 0.4.1, lists 24 tools with schemas")
    func emptyEnvironmentStart() throws {
        let client = try StdioClient(env: [:])
        defer { client.close() }
        let initResponse = try client.initialize(capabilities: [:])
        let serverInfo = (initResponse["result"] as? [String: Any])?["serverInfo"] as? [String: Any]
        #expect(serverInfo?["name"] as? String == "bench")
        #expect(serverInfo?["version"] as? String == "0.4.1")

        let tools = try client.listTools()
        #expect(tools.count == 24, "debug is switched off by default, so decode_crash is not listed")
        for tool in tools {
            #expect(tool["outputSchema"] != nil, "\(tool["name"] ?? "?") has no outputSchema")
            #expect(tool["annotations"] != nil, "\(tool["name"] ?? "?") has no annotations")
        }
    }

    @Test("Every tool answers one call without hardware, with the standard shape")
    func oneCallPerTool() throws {
        let client = try StdioClient(env: [:])
        defer { client.close() }
        _ = try client.initialize(capabilities: [:])
        let names = try client.listTools().compactMap { $0["name"] as? String }
        #expect(names.count == 24)

        for name in names {
            let response = try client.call(name, arguments: [:])
            guard let result = response["result"] as? [String: Any] else {
                Issue.record("\(name) returned no result: \(response)")
                continue
            }
            let structured = result["structuredContent"] as? [String: Any]
            #expect(structured?["tool"] as? String == name, "\(name) has no envelope")
            if (result["isError"] as? Bool) == true {
                let text = structured?["text"] as? String ?? ""
                #expect(text.hasPrefix("bench."), "\(name) error is not coded: \(text)")
            }
        }
    }

    @Test("chip_detect rejects an injected port before any tool runs")
    func chipDetectRejectsInjection() throws {
        let client = try StdioClient(env: [:], elicitationAnswer: ["action": "accept"])
        defer { client.close() }
        _ = try client.initialize(capabilities: ["elicitation": [:]])
        let injected = "/dev/cu.x;touch /tmp/bench-injection-test"
        let response = try client.call("chip_detect", arguments: ["identifier": "x", "port": injected])
        let text = ((response["result"] as? [String: Any])?["structuredContent"] as? [String: Any])?["text"] as? String ?? ""
        #expect(text.hasPrefix("bench.firmware.invalid_argument: "), "got: \(text)")
        #expect(client.elicitationMessages.count == 1, "the approval prompt is shown first")
    }

    @Test("A switched-off module is hidden and its tools refuse to run")
    func disabledModule() throws {
        let client = try StdioClient(env: ["BENCH_SERIAL_ENABLED": "0"])
        defer { client.close() }
        _ = try client.initialize(capabilities: [:])
        let names = try client.listTools().compactMap { $0["name"] as? String }
        #expect(names.count == 17)
        #expect(!names.contains("serial_read"))

        let response = try client.call("serial_read", arguments: ["port": "/dev/x"])
        let text = ((response["result"] as? [String: Any])?["structuredContent"] as? [String: Any])?["text"] as? String ?? ""
        #expect(text.hasPrefix("bench.serial.module_disabled: "))
        #expect(text.contains("BENCH_SERIAL_ENABLED=1"))
    }

    @Test("A write without approval is refused, and model-supplied confirm does not count")
    func writeRefusedWithoutElicitation() throws {
        let client = try StdioClient(env: [:])
        defer { client.close() }
        _ = try client.initialize(capabilities: [:])
        let response = try client.call("serial_write", arguments: ["port": "/dev/x", "data": "hi", "confirm": true])
        let result = response["result"] as? [String: Any]
        #expect(result?["isError"] as? Bool == true)
        let text = (result?["structuredContent"] as? [String: Any])?["text"] as? String ?? ""
        #expect(text.hasPrefix("bench.serial.write_not_approved: "))
        #expect(text.contains("BENCH_APPROVE_DEVICE_WRITES=1"))
        #expect(client.elicitationMessages.isEmpty, "no prompt is sent to a client that cannot answer one")
    }

    @Test("Pre-approved writes run without a prompt")
    func preApprovedWrite() throws {
        let client = try StdioClient(env: ["BENCH_APPROVE_DEVICE_WRITES": "1"])
        defer { client.close() }
        _ = try client.initialize(capabilities: [:])
        let response = try client.call("serial_write", arguments: [:])
        let text = ((response["result"] as? [String: Any])?["structuredContent"] as? [String: Any])?["text"] as? String ?? ""
        #expect(text.hasPrefix("bench.serial.missing_argument: "))
        #expect(client.elicitationMessages.isEmpty)
    }

    @Test("The person sees the full payload and a decline stops the write")
    func declinedWrite() throws {
        let client = try StdioClient(env: [:], elicitationAnswer: ["action": "decline"])
        defer { client.close() }
        _ = try client.initialize(capabilities: ["elicitation": [:]])
        let response = try client.call("serial_write", arguments: ["port": "/dev/x", "data": "reset"])
        let text = ((response["result"] as? [String: Any])?["structuredContent"] as? [String: Any])?["text"] as? String ?? ""
        #expect(text.hasPrefix("bench.serial.write_declined: "))
        let prompt = client.elicitationMessages.first ?? ""
        #expect(prompt.contains("\"data\": \"reset\""))
        #expect(prompt.contains("\"port\": \"/dev/x\""))
    }

    @Test("An accepted prompt lets the write proceed to its handler")
    func acceptedWrite() throws {
        let client = try StdioClient(env: [:], elicitationAnswer: ["action": "accept"])
        defer { client.close() }
        _ = try client.initialize(capabilities: ["elicitation": [:]])
        let response = try client.call("serial_write", arguments: [:])
        let text = ((response["result"] as? [String: Any])?["structuredContent"] as? [String: Any])?["text"] as? String ?? ""
        #expect(text.hasPrefix("bench.serial.missing_argument: "))
        #expect(client.elicitationMessages.count == 1)
    }
}

/// Minimal newline-delimited JSON-RPC client over the server's stdio.
final class StdioClient {
    private let process = Process()
    private let stdinPipe = Pipe()
    private let stdoutPipe = Pipe()
    private var buffer = Data()
    private var nextID = 1
    private let elicitationAnswer: [String: Any]?
    private(set) var elicitationMessages: [String] = []

    init(env: [String: String], elicitationAnswer: [String: Any]? = nil) throws {
        self.elicitationAnswer = elicitationAnswer
        process.executableURL = URL(fileURLWithPath: StdioServerTests.binaryPath)
        process.environment = env
        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = FileHandle.nullDevice
        try process.run()
    }

    func close() {
        try? stdinPipe.fileHandleForWriting.close()
        process.terminate()
        process.waitUntilExit()
    }

    func initialize(capabilities: [String: Any]) throws -> [String: Any] {
        let response = try request("initialize", [
            "protocolVersion": "2025-11-25",
            "capabilities": capabilities,
            "clientInfo": ["name": "bench-tests", "version": "1"],
        ])
        try notify("notifications/initialized")
        return response
    }

    func listTools() throws -> [[String: Any]] {
        let response = try request("tools/list", [:])
        return (response["result"] as? [String: Any])?["tools"] as? [[String: Any]] ?? []
    }

    func call(_ name: String, arguments: [String: Any]) throws -> [String: Any] {
        try request("tools/call", ["name": name, "arguments": arguments])
    }

    private func notify(_ method: String) throws {
        try write(["jsonrpc": "2.0", "method": method])
    }

    func request(_ method: String, _ params: [String: Any]) throws -> [String: Any] {
        let id = nextID
        nextID += 1
        try write(["jsonrpc": "2.0", "id": id, "method": method, "params": params])
        while true {
            guard let message = try readMessage() else {
                throw ClientError.serverClosed
            }
            // Server-to-client elicitation: answer it, or stay silent if this client cannot.
            if message["method"] as? String == "elicitation/create", let serverID = message["id"] {
                let params = message["params"] as? [String: Any]
                elicitationMessages.append(params?["message"] as? String ?? "")
                if let answer = elicitationAnswer {
                    try write(["jsonrpc": "2.0", "id": serverID, "result": answer])
                }
                continue
            }
            if let responseID = message["id"] as? Int, responseID == id {
                return message
            }
        }
    }

    private func write(_ object: [String: Any]) throws {
        var data = try JSONSerialization.data(withJSONObject: object)
        data.append(10)
        try stdinPipe.fileHandleForWriting.write(contentsOf: data)
    }

    private func readMessage() throws -> [String: Any]? {
        let fd = stdoutPipe.fileHandleForReading.fileDescriptor
        while true {
            if let newline = buffer.firstIndex(of: 10) {
                let line = buffer[buffer.startIndex..<newline]
                buffer.removeSubrange(buffer.startIndex...newline)
                if line.isEmpty { continue }
                return try JSONSerialization.jsonObject(with: line) as? [String: Any]
            }
            var chunk = [UInt8](repeating: 0, count: 65536)
            let count = read(fd, &chunk, chunk.count)
            if count <= 0 { return nil }
            buffer.append(contentsOf: chunk[0..<count])
        }
    }

    enum ClientError: Error {
        case serverClosed
    }
}
