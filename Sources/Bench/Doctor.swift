import BenchCore
import Foundation

/// `bench --doctor`: checks what this Mac and this environment need, prints one line
/// per check and a FIX line for each problem. Exit 0 = ready, 1 = something to fix.
/// It only reads: no device is opened and nothing is written.
enum Doctor {
    struct Check {
        let name: String
        let ok: Bool
        let message: String
    }

    static func run(env: [String: String]) -> Int32 {
        let checks = collect(env: env)
        print("bench \(Bench.serverVersion) doctor")
        for check in checks {
            let mark = check.ok ? "ok  " : "FIX "
            print("  \(mark) \(check.name.padding(toLength: 13, withPad: " ", startingAt: 0)) \(check.message)")
        }
        let bad = checks.filter { !$0.ok }.count
        print(bad == 0 ? "ready" : "\(bad) thing(s) to fix")
        return bad == 0 ? 0 : 1
    }

    static func collect(env: [String: String]) -> [Check] {
        let settings = BenchSettings.load(env: env)
        var out: [Check] = []

        let on = BenchModules.all.filter { settings.isEnabled($0.id) }.map(\.id)
        out.append(Check(name: "modules", ok: true, message: "on: \(on.joined(separator: ", ")). Switch with BENCH_MODULES or BENCH_<MODULE>_ENABLED."))

        let devices = IOKitBridge.enumerateDevices(includeInternal: false)
        out.append(Check(name: "usb", ok: true, message: devices.isEmpty
            ? "IOKit answered; no USB devices attached right now. Plug a board in to test."
            : "IOKit answered; \(devices.count) USB device(s) attached."))

        let ports = SerialPortBridge.discoverPorts()
        if ports.isEmpty {
            out.append(Check(name: "serial", ok: true, message: "no serial ports attached right now."))
        } else {
            let unusable = ports.filter { access($0.path, R_OK | W_OK) != 0 }.map(\.path)
            if unusable.isEmpty {
                out.append(Check(name: "serial", ok: true, message: "\(ports.count) port(s) readable and writable: \(ports.map(\.path).joined(separator: ", "))"))
            } else {
                out.append(Check(name: "serial", ok: false, message: "cannot read and write \(unusable.joined(separator: ", ")). Fix: allow the client's process to use serial devices, then retry (on Linux, add your user to the dialout group)."))
            }
        }

        let firmwareOn = settings.isEnabled("firmware")
        out.append(tool(
            "esptool", names: ["esptool", "esptool.py"], env: env, required: firmwareOn,
            fix: "Needed for chip_detect and ESP32 flashing. Fix: brew install esptool (or pip install esptool), then start the client with that folder on its PATH."
        ))
        out.append(tool(
            "dfu-util", names: ["dfu-util"], env: env, required: false,
            fix: "Needed only to flash STM32 boards over DFU. Fix: brew install dfu-util."
        ))
        out.append(tool(
            "avrdude", names: ["avrdude"], env: env, required: false,
            fix: "Needed only to flash AVR boards (Uno, Nano). Fix: brew install avrdude."
        ))
        out.append(tool(
            "arduino-cli", names: ["arduino-cli"], env: env, required: false,
            fix: "Optional. No Bench tool calls it; install it for your own builds."
        ))

        let debugOn = settings.isEnabled("debug")
        if !debugOn {
            out.append(Check(name: "addr2line", ok: true, message: "decode_crash is switched off (BENCH_DEBUG_ENABLED=1 turns it on)."))
        } else if let found = addr2lineOnPath(env: env) {
            out.append(Check(name: "addr2line", ok: true, message: "found \(found)."))
        } else {
            out.append(Check(name: "addr2line", ok: false, message: "no ESP32 or ARM addr2line found, which decode_crash needs. Fix: install the ESP-IDF toolchain or arm-none-eabi-gcc, put its bin folder on PATH, or set BENCH_ADDR2LINE to the full path."))
        }

        let log = ApprovalLog.path(env: env)
        let approvedInAdvance = ["1", "true", "on", "yes"].contains((env["BENCH_APPROVE_DEVICE_WRITES"] ?? "").lowercased())
        out.append(Check(name: "approvals", ok: true, message: approvedInAdvance
            ? "device writes are pre-approved (BENCH_APPROVE_DEVICE_WRITES). Each one is still logged."
            : "device writes ask the person through MCP elicitation. A client that cannot answer is refused unless BENCH_APPROVE_DEVICE_WRITES=1."))
        out.append(Check(name: "approval log", ok: true, message: "\(log.path) (local only; BENCH_APPROVAL_LOG changes it)."))

        let skillsDir = BenchSkills.directory(env: env, executable: benchExecutableURL())
        let skillCount = BenchSkills.load(from: skillsDir).count
        if let skillsDir, skillCount > 0 {
            out.append(Check(name: "skills", ok: true, message: "\(skillCount) skill(s) in \(skillsDir.path)."))
        } else {
            out.append(Check(name: "skills", ok: false, message: "no skills folder found. Fix: install with Homebrew (it installs share/bench/skills), or set BENCH_SKILLS_DIR to the skills folder of a checkout."))
        }

        out.append(Check(name: "network", ok: true, message: "none. Bench makes no network calls and sends no telemetry."))
        return out
    }

    /// A tool on PATH. When it is not needed by a switched-off module, it is reported as ok.
    static func tool(_ label: String, names: [String], env: [String: String], required: Bool, fix: String) -> Check {
        for name in names {
            if let path = try? ToolRunner.resolve(name) {
                return Check(name: label, ok: true, message: "found \(path.path).")
            }
        }
        if required {
            return Check(name: label, ok: false, message: "not found on PATH. \(fix)")
        }
        return Check(name: label, ok: true, message: "not found. \(fix)")
    }

    static func addr2lineOnPath(env: [String: String]) -> String? {
        if let explicit = env["BENCH_ADDR2LINE"], !explicit.isEmpty {
            return FileManager.default.isExecutableFile(atPath: explicit) ? explicit : nil
        }
        let names = [
            "xtensa-esp32-elf-addr2line", "xtensa-esp32s3-elf-addr2line", "xtensa-esp32s2-elf-addr2line",
            "xtensa-esp-elf-addr2line", "riscv32-esp-elf-addr2line", "arm-none-eabi-addr2line",
        ]
        for name in names {
            if let path = try? ToolRunner.resolve(name) { return path.path }
        }
        return nil
    }

}
