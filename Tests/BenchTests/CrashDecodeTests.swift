import Foundation
import Testing
@testable import BenchCore

@Suite("Crash dump parsing")
struct CrashDecodeTests {
    static let esp32Dump = """
    Guru Meditation Error: Core  0 panic'ed (LoadProhibited). Exception was unhandled.
    Core  0 register dump:
    PC      : 0x400d1234  PS      : 0x00060030  A0      : 0x800d0a3d  A1      : 0x3ffb1f40
    Backtrace: 0x400d1234:0x3ffb1f40 0x400d0a3a:0x3ffb1f60 0x40083a7d:0x3ffb1f80
    """

    @Test("ESP32 Xtensa dump: PC and backtrace addresses are found, stack words are not")
    func esp32Xtensa() throws {
        let report = try #require(CrashDecoder.parse(Self.esp32Dump))
        #expect(report.family == .esp32)
        #expect(report.isRiscV == false)
        #expect(report.exceptionLine?.hasPrefix("Guru Meditation Error") == true)
        let hexes = report.addresses.map(\.hex)
        #expect(hexes.contains("0x400d1234"))
        #expect(hexes.contains("0x400d0a3a"))
        #expect(hexes.contains("0x40083a7d"))
        #expect(!hexes.contains("0x3ffb1f40"), "a stack address is not code")
        #expect(report.addresses.first?.label == "PC")
        #expect(CrashDecoder.toolchainCandidates(for: report).first == "xtensa-esp32-elf-addr2line")
    }

    @Test("ESP32-C3 (RISC-V) dump names MEPC and selects the RISC-V addr2line")
    func esp32RiscV() throws {
        let dump = """
        Guru Meditation Error: Core  0 panic'ed (Store access fault). Exception was unhandled.
        MEPC    : 0x4038a1f2  RA      : 0x4038a1d0  SP      : 0x3fc9e000
        """
        let report = try #require(CrashDecoder.parse(dump))
        #expect(report.isRiscV)
        #expect(report.addresses.map(\.hex) == ["0x4038a1f2", "0x4038a1d0"])
        #expect(CrashDecoder.toolchainCandidates(for: report).first == "riscv32-esp-elf-addr2line")
    }

    @Test("ARM HardFault register dump: PC, LR and stacked PC are found, with the Thumb bit cleared")
    func armHardFault() throws {
        let dump = """
        ***** HardFault *****
        r15/pc : 0x08001235
        r14/lr : 0x080012fd
        Stacked PC : 0x08004444
        CFSR   : 0x00000082
        """
        let report = try #require(CrashDecoder.parse(dump))
        #expect(report.family == .arm)
        #expect(report.addresses.map(\.hex) == ["0x8001234", "0x80012fc", "0x8004444"])
        #expect(CrashDecoder.toolchainCandidates(for: report) == ["arm-none-eabi-addr2line", "arm-zephyr-eabi-addr2line"])
    }

    @Test("Text without a crash dump is not a crash")
    func noCrash() {
        #expect(CrashDecoder.parse("ets Jun  8 2016 00:22:57\nrst:0x1 (POWERON_RESET)") == nil)
        #expect(CrashDecoder.parse("OK\n") == nil)
    }

    @Test("Addresses are normalized, and anything that is not hex is refused")
    func normalize() {
        #expect(CrashDecoder.normalize("0x400D1234") == "0x400d1234")
        #expect(CrashDecoder.normalize("400d1235") == "0x400d1235", "Xtensa keeps bit 0")
        #expect(CrashDecoder.normalize("400d1235", clearThumbBit: true) == "0x400d1234", "ARM clears the Thumb bit")
        #expect(CrashDecoder.normalize("0x400d1234; rm -rf ~") == nil)
        #expect(CrashDecoder.normalize("") == nil)
        #expect(CrashDecoder.normalize("0x12345678901234567") == nil, "longer than 64 bits")
    }
}
