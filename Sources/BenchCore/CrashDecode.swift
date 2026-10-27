import Foundation

/// A crash dump found in serial output, reduced to the addresses to resolve.
public struct CrashReport: Equatable, Sendable {
    public enum Family: String, Sendable {
        case esp32 = "ESP32"
        case arm = "ARM"
    }

    public struct Address: Equatable, Sendable {
        /// Where the address came from: "PC", "MEPC", "backtrace", "frame", "LR", ...
        public let label: String
        /// Normalized hex, for example 0x400d1234. The Thumb bit is cleared.
        public let hex: String
    }

    public let family: Family
    /// The line that names the fault, trimmed. Nil when the dump has no such line.
    public let exceptionLine: String?
    /// True when the dump names a RISC-V register (MEPC), as ESP32-C2, C3, C6 and H2 do.
    public let isRiscV: Bool
    public let addresses: [Address]
}

/// Finds crash dumps in serial text. Pure string handling: no process is started here.
public enum CrashDecoder {
    public static let maxInputBytes = 64 * 1024
    public static let maxAddresses = 32

    /// Register and backtrace labels whose values are code addresses.
    static let codeLabels: Set<String> = [
        "pc", "mepc", "epc", "ra", "lr", "r14", "r15", "r14/lr", "r15/pc",
        "stacked pc", "stacked lr", "exception pc",
    ]

    /// nil when the text has no Guru Meditation Error and no HardFault dump.
    public static func parse(_ text: String) -> CrashReport? {
        let lines = text.components(separatedBy: .newlines)
        let lower = text.lowercased()
        let isEsp = text.contains("Guru Meditation") || lines.contains {
            $0.trimmingCharacters(in: .whitespaces).hasPrefix("Backtrace:")
        }
        let isArm = ["hardfault", "hard fault", "cfsr", "busfault", "usagefault", "memmanage"].contains { lower.contains($0) }
        guard isEsp || isArm else { return nil }

        var found: [CrashReport.Address] = []
        func add(_ label: String, _ raw: String) {
            let hex = normalize(raw, clearThumbBit: !isEsp)
            guard let hex, !found.contains(where: { $0.hex == hex }) else { return }
            found.append(.init(label: label, hex: hex))
        }

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("Backtrace:") {
                for token in trimmed.dropFirst("Backtrace:".count).split(whereSeparator: { $0 == " " || $0 == "\t" }) {
                    // Each backtrace entry is PC:SP. Only the PC is code.
                    add("BACKTRACE", String(token.split(separator: ":").first ?? ""))
                }
            }
            for label in labelledValues(in: line) where codeLabels.contains(label.name) {
                add(label.name.uppercased(), label.value)
            }
            if let frame = frameValue(in: trimmed) {
                add("FRAME", frame)
            }
        }

        let family: CrashReport.Family = isEsp ? .esp32 : .arm
        let exception = lines.first { $0.contains("Guru Meditation") || lower.contains("hardfault") || $0.lowercased().contains("hard fault") }
        return CrashReport(
            family: family,
            exceptionLine: exception.map { String($0.trimmingCharacters(in: .whitespaces).prefix(200)) },
            isRiscV: found.contains { $0.label == "MEPC" },
            addresses: Array(found.prefix(maxAddresses))
        )
    }

    /// The addr2line binaries to try, in order, for this dump.
    public static func toolchainCandidates(for report: CrashReport) -> [String] {
        switch report.family {
        case .esp32 where report.isRiscV:
            return ["riscv32-esp-elf-addr2line", "riscv32-unknown-elf-addr2line"]
        case .esp32:
            return ["xtensa-esp32-elf-addr2line", "xtensa-esp32s3-elf-addr2line", "xtensa-esp32s2-elf-addr2line", "xtensa-esp-elf-addr2line"]
        case .arm:
            return ["arm-none-eabi-addr2line", "arm-zephyr-eabi-addr2line"]
        }
    }

    /// What to install, named for the person who has to install it.
    public static func installHint(for report: CrashReport) -> String {
        switch report.family {
        case .esp32:
            return "Install the ESP-IDF toolchain (run install.sh in the ESP-IDF folder, or use PlatformIO's toolchain-xtensa-esp32 or toolchain-riscv32-esp package), add its bin folder to the client's PATH, or set BENCH_ADDR2LINE to the full path of the addr2line binary."
        case .arm:
            return "Install the GNU Arm Embedded toolchain (brew install arm-none-eabi-gcc on macOS), add its bin folder to the client's PATH, or set BENCH_ADDR2LINE to the full path of arm-none-eabi-addr2line."
        }
    }

    /// Accepts 0x-prefixed or bare hex and returns 0x<lowercase hex>. ARM code addresses
    /// carry the Thumb bit in bit 0, which is cleared when `clearThumbBit` is set. Xtensa
    /// and RISC-V instructions can start at odd addresses, so their bit 0 is kept.
    public static func normalize(_ raw: String, clearThumbBit: Bool = false) -> String? {
        var text = raw.trimmingCharacters(in: .whitespaces).lowercased()
        if text.hasPrefix("0x") { text.removeFirst(2) }
        guard !text.isEmpty, text.count <= 16, text.allSatisfy(\.isHexDigit), var value = UInt64(text, radix: 16) else {
            return nil
        }
        if clearThumbBit { value &= ~UInt64(1) }
        return "0x" + String(value, radix: 16)
    }

    /// `name: 0x...` pairs on one line, for example "PC : 0x400d1234  PS : 0x60030".
    static func labelledValues(in line: String) -> [(name: String, value: String)] {
        guard let regex = try? NSRegularExpression(
            pattern: "(?<![A-Za-z0-9_])([A-Za-z][A-Za-z0-9_/]*(?: [A-Za-z]+)?)\\s*[:=]\\s*(0x[0-9A-Fa-f]{1,16})"
        ) else { return [] }
        let range = NSRange(line.startIndex..<line.endIndex, in: line)
        return regex.matches(in: line, range: range).compactMap { match in
            guard let nameRange = Range(match.range(at: 1), in: line),
                  let valueRange = Range(match.range(at: 2), in: line) else { return nil }
            let name = line[nameRange].lowercased().split(separator: " ").joined(separator: " ")
            return (name, String(line[valueRange]))
        }
    }

    /// A gdb-style "#3  0x400d1234 in ..." frame line.
    static func frameValue(in trimmed: String) -> String? {
        guard trimmed.hasPrefix("#") else { return nil }
        let parts = trimmed.dropFirst().split(separator: " ", omittingEmptySubsequences: true)
        guard parts.count >= 2, parts[0].allSatisfy(\.isNumber), parts[1].hasPrefix("0x") else { return nil }
        return String(parts[1])
    }
}
