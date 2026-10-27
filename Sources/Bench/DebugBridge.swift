import BenchCore
import Foundation
import MCP

/// decode_crash: resolves the program counters in a crash dump with addr2line.
/// The model never chooses the binary. It is found on PATH for the dump's chip family,
/// or set by the person with BENCH_ADDR2LINE. The .elf is passed as data in argv.
func handleDecodeCrash(params: CallTool.Parameters) -> CallTool.Result {
    func fail(_ code: String, _ message: String, _ fix: String) -> CallTool.Result {
        .init(content: [.text(benchErrorText(module: "debug", code: code, message: message, fix: fix))], isError: true)
    }

    guard let output = params.arguments?["output"]?.stringValue else {
        return .init(content: [.text("Missing required parameter: output")], isError: true)
    }
    guard let elf = params.arguments?["elf"]?.stringValue else {
        return .init(content: [.text("Missing required parameter: elf")], isError: true)
    }
    guard output.utf8.count <= CrashDecoder.maxInputBytes else {
        return fail("invalid_argument", "Invalid output: it is longer than 64 KB.", "Paste only the crash block, from the Guru Meditation or HardFault line through the Backtrace or register lines.")
    }
    guard elf.hasPrefix("/") else {
        return fail("invalid_argument", "Invalid elf: the path must be absolute.", "Pass the full path to the .elf file, for example /Users/you/project/build/firmware.elf.")
    }
    guard isELF(path: elf) else {
        return fail("invalid_argument", "Invalid elf: \(jsonString(elf)) is not a readable ELF file.", "Build the firmware and pass the .elf it produced (not the .bin or .hex).")
    }

    guard let report = CrashDecoder.parse(output) else {
        return fail("no_crash_found", "No Guru Meditation Error or HardFault dump was found in the output.", "Paste the whole crash block: the Guru Meditation line and its Backtrace line, or the HardFault register lines.")
    }
    guard !report.addresses.isEmpty else {
        return fail("no_addresses", "The \(report.family.rawValue) dump has no program counter or backtrace address to decode.", "Paste the full dump. The Backtrace or PC lines are the ones that get decoded.")
    }

    let tool: String
    do {
        tool = try addr2lineBinary(for: report)
    } catch {
        let names = CrashDecoder.toolchainCandidates(for: report).joined(separator: ", ")
        return fail("toolchain_missing", "No addr2line for this \(report.family.rawValue) dump was found (looked for \(names) on PATH, or BENCH_ADDR2LINE).", CrashDecoder.installHint(for: report))
    }

    let addresses = report.addresses.map(\.hex)
    let run: ToolRunResult
    do {
        run = try ToolRunner.run(name: tool, arguments: ["-e", elf, "-f", "-C", "-p"] + addresses)
    } catch {
        return fail("addr2line_failed", "addr2line could not be started: \(error).", CrashDecoder.installHint(for: report))
    }
    guard run.status == 0 else {
        let detail = run.stderr.trimmingCharacters(in: .whitespacesAndNewlines).prefix(300)
        return fail("addr2line_failed", "addr2line exited with status \(run.status): \(detail)", "Check that the .elf is the firmware that crashed, and that the toolchain matches the chip.")
    }

    let resolved = run.stdout.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
    var lines = [
        "Decoded \(addresses.count) address(es) from an \(report.family.rawValue) dump with \(tool).",
    ]
    if let exception = report.exceptionLine {
        lines.append("Fault: \(exception)")
    }
    lines.append("")
    if resolved.count >= addresses.count {
        for (index, address) in report.addresses.enumerated() {
            let location = resolved[index].trimmingCharacters(in: .whitespaces)
            let label = address.label.padding(toLength: 10, withPad: " ", startingAt: 0)
            lines.append("#\(index)  \(label) \(address.hex)  \(location)")
        }
        if resolved.prefix(addresses.count).contains(where: { $0.hasPrefix("??") }) {
            lines.append("")
            lines.append("Frames marked ?? were not found in the .elf. A ?? on every line usually means the .elf is from a different build than the crashing firmware.")
        }
    } else {
        lines.append("addr2line returned \(resolved.count) line(s) for \(addresses.count) address(es). Raw output:")
        lines.append(run.stdout)
    }
    return .init(content: [.text(lines.joined(separator: "\n"))])
}

/// The addr2line to run: BENCH_ADDR2LINE if set (it must be executable), otherwise
/// the first candidate for this chip family found on PATH.
func addr2lineBinary(for report: CrashReport) throws -> String {
    let env = ProcessInfo.processInfo.environment
    if let explicit = env["BENCH_ADDR2LINE"], !explicit.isEmpty {
        guard FileManager.default.isExecutableFile(atPath: explicit) else {
            throw ToolRunError.notFound(explicit)
        }
        return explicit
    }
    let candidates = CrashDecoder.toolchainCandidates(for: report)
    for name in candidates {
        if (try? ToolRunner.resolve(name)) != nil { return name }
    }
    throw ToolRunError.notFound(candidates.joined(separator: " or "))
}

/// True when the file starts with the ELF magic bytes. Reads four bytes only.
func isELF(path: String) -> Bool {
    guard let handle = FileHandle(forReadingAtPath: path) else { return false }
    defer { try? handle.close() }
    let magic = (try? handle.read(upToCount: 4)) ?? Data()
    return magic == Data([0x7F, 0x45, 0x4C, 0x46])
}
