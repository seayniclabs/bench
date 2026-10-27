import Foundation
import Testing
@testable import BenchCore

/// Skills over MCP, the approval log, decode_crash, serial_write_and_expect, the doctor,
/// and the no-promotion rule. Each test drives the built binary over stdio or as a process.
@Suite("Skills, trust and new tools", .serialized)
struct TrustTests {
    static let repoSkills = SkillsTests.repoSkills

    static func runBench(_ args: [String], env: [String: String]) throws -> (status: Int32, stdout: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: StdioServerTests.binaryPath)
        process.arguments = args
        process.environment = env
        let stdout = Pipe()
        process.standardOutput = stdout
        process.standardError = FileHandle.nullDevice
        try process.run()
        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (process.terminationStatus, String(decoding: data, as: UTF8.self))
    }

    static func tempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("bench-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// The structured text of a tool result, or "" when absent.
    static func text(of response: [String: Any]) -> String {
        ((response["result"] as? [String: Any])?["structuredContent"] as? [String: Any])?["text"] as? String ?? ""
    }

    @Test("Prompts: one per skill folder, and prompts/get returns the SKILL.md body")
    func promptsMatchSkills() throws {
        let client = try StdioClient(env: [:])
        defer { client.close() }
        _ = try client.initialize(capabilities: [:])

        let listed = try client.request("prompts/list", [:])
        let names = ((listed["result"] as? [String: Any])?["prompts"] as? [[String: Any]] ?? []).compactMap { $0["name"] as? String }
        let expected = BenchSkills.load(from: Self.repoSkills).map(\.name)
        #expect(names.sorted() == expected.sorted())
        #expect(names.count == 5)

        let got = try client.request("prompts/get", ["name": "getting-started"])
        let message = ((got["result"] as? [String: Any])?["messages"] as? [[String: Any]])?.first
        let content = (message?["content"] as? [String: Any])?["text"] as? String ?? ""
        #expect(content.hasPrefix("# Getting started with Bench"), "the prompt starts with the body, not the frontmatter")

        let withFiles = try client.request("prompts/get", ["name": "systematic-debugging"])
        let filesText = (((withFiles["result"] as? [String: Any])?["messages"] as? [[String: Any]])?.first?["content"] as? [String: Any])?["text"] as? String ?? ""
        #expect(filesText.contains("skill://bench/systematic-debugging/root-cause-tracing.md"), "the supporting-files list is missing")
    }

    @Test("Resources: each SKILL.md is readable at skill://bench/<name>/SKILL.md")
    func resourcesReadable() throws {
        let client = try StdioClient(env: [:])
        defer { client.close() }
        _ = try client.initialize(capabilities: [:])

        let listed = try client.request("resources/list", [:])
        let uris = ((listed["result"] as? [String: Any])?["resources"] as? [[String: Any]] ?? []).compactMap { $0["uri"] as? String }
        #expect(uris.contains("skill://bench/board-bring-up/SKILL.md"))
        #expect(uris.contains("skill://bench/systematic-debugging/LICENSE"))

        let read = try client.request("resources/read", ["uri": "skill://bench/safe-flashing/SKILL.md"])
        let text = (((read["result"] as? [String: Any])?["contents"] as? [[String: Any]])?.first)?["text"] as? String ?? ""
        #expect(text.contains("name: safe-flashing"))

        let missing = try client.request("resources/read", ["uri": "skill://bench/nope/SKILL.md"])
        #expect(missing["error"] != nil)
    }

    @Test("No promotion reaches the model: instructions, tool text and prompts never link the site")
    func noPromotionForTheModel() throws {
        let client = try StdioClient(env: [:])
        defer { client.close() }
        let initResponse = try client.initialize(capabilities: [:])
        let instructions = (initResponse["result"] as? [String: Any])?["instructions"] as? String ?? ""
        #expect(instructions.hasPrefix("Bench finds USB maker boards"))
        #expect(!instructions.contains("seayniclabs.com"))

        for tool in try client.listTools() {
            let description = tool["description"] as? String ?? ""
            #expect(!description.contains("seayniclabs.com"), "\(tool["name"] ?? "?") links the site")
        }
        let prompts = try client.request("prompts/list", [:])
        #expect(!String(describing: prompts).contains("seayniclabs.com"))
    }

    @Test("bench_modules names the publisher, the homepage, the skills and the approval log")
    func discoveryOutput() throws {
        let client = try StdioClient(env: [:])
        defer { client.close() }
        _ = try client.initialize(capabilities: [:])
        let response = try client.call("bench_modules", arguments: [:])
        let text = Self.text(of: response)
        #expect(text.contains("Publisher: Seaynic Labs. Homepage: https://github.com/seayniclabs/bench"))
        #expect(text.contains("Skills: 5 served as MCP prompts and resources"))
        #expect(text.contains("Approval log: "))
        #expect(text.contains("[off] debug"))
    }

    @Test("Declines and refusals are logged without the payload")
    func approvalLogRecordsDecisions() throws {
        let logDir = try Self.tempDir()
        let logPath = logDir.appendingPathComponent("approvals.jsonl").path
        let env = ["BENCH_APPROVAL_LOG": logPath]

        let declining = try StdioClient(env: env, elicitationAnswer: ["action": "decline"])
        _ = try declining.initialize(capabilities: ["elicitation": [:]])
        _ = try declining.call("serial_write", arguments: ["port": "/dev/cu.test", "data": "SECRET-PAYLOAD-123"])
        declining.close()

        let refusing = try StdioClient(env: env)
        _ = try refusing.initialize(capabilities: [:])
        let refused = try refusing.call("serial_write_and_expect", arguments: ["port": "/dev/cu.test", "data": "SECRET-PAYLOAD-456", "pattern": "OK"])
        refusing.close()

        #expect(Self.text(of: refused).hasPrefix("bench.serial.write_not_approved: "))
        let log = try String(contentsOfFile: logPath, encoding: .utf8)
        let lines = log.split(separator: "\n").compactMap { try? JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String: Any] }
        let decisions = lines.compactMap { $0["decision"] as? String }
        #expect(decisions == ["requested", "declined", "requested", "refused"])
        #expect(lines.first?["tool"] as? String == "serial_write")
        #expect(!log.contains("SECRET-PAYLOAD-123"), "the payload must not be logged")
        #expect(!log.contains("SECRET-PAYLOAD-456"), "the payload must not be logged")
        #expect(log.contains("\"port\":\"\\/dev\\/cu.test\"") || log.contains("\"port\":\"/dev/cu.test\""))
        #expect(log.contains("<redacted 18 chars>"), "SECRET-PAYLOAD-123 is 18 characters")
    }

    @Test("An accepted write is logged as approved by the person")
    func approvalLogRecordsGrant() throws {
        let logDir = try Self.tempDir()
        let logPath = logDir.appendingPathComponent("approvals.jsonl").path
        let client = try StdioClient(env: ["BENCH_APPROVAL_LOG": logPath], elicitationAnswer: ["action": "accept"])
        _ = try client.initialize(capabilities: ["elicitation": [:]])
        _ = try client.call("serial_write", arguments: [:])
        client.close()
        let log = try String(contentsOfFile: logPath, encoding: .utf8)
        #expect(log.contains("\"decision\":\"approved\""))
        #expect(log.contains("person (MCP elicitation)"))
    }

    @Test("serial_write_and_expect needs approval, validates its pattern, and reports a closed port")
    func expectNeedsApprovalAndReportsClosedPort() throws {
        let client = try StdioClient(env: [:], elicitationAnswer: ["action": "accept"])
        defer { client.close() }
        _ = try client.initialize(capabilities: ["elicitation": [:]])

        let closed = try client.call("serial_write_and_expect", arguments: ["port": "/dev/cu.test", "data": "ping", "pattern": "pong"])
        #expect(Self.text(of: closed).hasPrefix("bench.serial.port_not_open: "))
        #expect(client.elicitationMessages.count == 1, "the write is shown to the person first")

        let badPattern = try client.call("serial_write_and_expect", arguments: ["port": "/dev/cu.test", "data": "ping", "pattern": "("])
        #expect(Self.text(of: badPattern).hasPrefix("bench.serial.invalid_argument: "))
    }

    @Test("decode_crash is off by default and resolves addresses through BENCH_ADDR2LINE")
    func decodeCrashWithFakeToolchain() throws {
        let dir = try Self.tempDir()
        let tool = dir.appendingPathComponent("fake-addr2line")
        try "#!/bin/sh\nfor a in \"$@\"; do case \"$a\" in -*|*.elf) ;; *) echo \"app_main at /src/main.c:42\";; esac; done\n"
            .write(to: tool, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: tool.path)
        let elf = dir.appendingPathComponent("firmware.elf")
        try Data([0x7F, 0x45, 0x4C, 0x46, 0, 0, 0, 0]).write(to: elf)
        let dump = "Guru Meditation Error: Core  0 panic'ed (LoadProhibited).\nBacktrace: 0x400d1234:0x3ffb1f40 0x400d0a3a:0x3ffb1f60\n"

        let off = try StdioClient(env: [:])
        _ = try off.initialize(capabilities: [:])
        let offText = Self.text(of: try off.call("decode_crash", arguments: ["output": dump, "elf": elf.path]))
        off.close()
        #expect(offText.hasPrefix("bench.debug.module_disabled: "))

        let on = try StdioClient(env: ["BENCH_DEBUG_ENABLED": "1", "BENCH_ADDR2LINE": tool.path])
        defer { on.close() }
        _ = try on.initialize(capabilities: [:])
        #expect(try on.listTools().count == 25)
        let response = try on.call("decode_crash", arguments: ["output": dump, "elf": elf.path])
        let text = Self.text(of: response)
        #expect(text.contains("Decoded 2 address(es) from an ESP32 dump"))
        #expect(text.contains("#0  BACKTRACE  0x400d1234  app_main at /src/main.c:42"))
        #expect(text.contains("#1  BACKTRACE  0x400d0a3a  app_main at /src/main.c:42"))
        let readOnly = try on.listTools().first { $0["name"] as? String == "decode_crash" }
        #expect((readOnly?["annotations"] as? [String: Any])?["readOnlyHint"] as? Bool == true)
    }

    @Test("decode_crash names what to install when no addr2line is available, and refuses bad input")
    func decodeCrashErrors() throws {
        let dir = try Self.tempDir()
        let elf = dir.appendingPathComponent("firmware.elf")
        try Data([0x7F, 0x45, 0x4C, 0x46]).write(to: elf)
        let dump = "Guru Meditation Error: Core  0 panic'ed.\nBacktrace: 0x400d1234:0x3ffb1f40\n"

        let client = try StdioClient(env: ["BENCH_DEBUG_ENABLED": "1", "BENCH_ADDR2LINE": "/nonexistent/addr2line"])
        defer { client.close() }
        _ = try client.initialize(capabilities: [:])
        let missing = Self.text(of: try client.call("decode_crash", arguments: ["output": dump, "elf": elf.path]))
        #expect(missing.hasPrefix("bench.debug.toolchain_missing: "))
        #expect(missing.contains("BENCH_ADDR2LINE") || missing.contains("ESP-IDF"))

        let relative = Self.text(of: try client.call("decode_crash", arguments: ["output": dump, "elf": "firmware.elf"]))
        #expect(relative.hasPrefix("bench.debug.invalid_argument: "))

        let notELF = Self.text(of: try client.call("decode_crash", arguments: ["output": dump, "elf": "/etc/hosts"]))
        #expect(notELF.hasPrefix("bench.debug.invalid_argument: "))

        let noDump = Self.text(of: try client.call("decode_crash", arguments: ["output": "OK\n", "elf": elf.path]))
        #expect(noDump.hasPrefix("bench.debug.no_crash_found: "))
    }

    @Test("The doctor exits 1 and prints a FIX line for each problem it finds")
    func doctorReportsFixes() throws {
        let result = try Self.runBench(["--doctor"], env: ["BENCH_SKILLS_DIR": Self.repoSkills.path])
        #expect(result.status == 1)
        #expect(result.stdout.hasPrefix("bench \(Bench.serverVersion) doctor"))
        #expect(result.stdout.contains("FIX  esptool"))
        #expect(result.stdout.contains("ok   skills"))
        #expect(result.stdout.contains("ok   network"))
        #expect(result.stdout.contains("thing(s) to fix"))
    }

    @Test("The doctor names a missing skills folder with a fix")
    func doctorSkillsFix() throws {
        let result = try Self.runBench(["--doctor"], env: ["BENCH_SKILLS_DIR": "/nonexistent-bench-skills"])
        #expect(result.status == 1)
        #expect(result.stdout.contains("FIX  skills"))
    }

    @Test("The doctor names the log file it writes to")
    func doctorApprovalLog() throws {
        let result = try Self.runBench(["--doctor"], env: ["BENCH_APPROVAL_LOG": "/tmp/bench-doctor-log.jsonl"])
        #expect(result.stdout.contains("ok   approval log  /tmp/bench-doctor-log.jsonl"))
    }
}
