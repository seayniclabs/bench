import Foundation
import MCP
import Testing
@testable import BenchCore

@Suite("Modules and settings")
struct ModulesTests {
    @Test("Every tool belongs to exactly one module, and the modules cover the registry")
    func moduleCoverage() {
        let owned = BenchModules.all.flatMap(\.tools)
        #expect(owned.count == Set(owned).count, "a tool is listed in two modules")
        #expect(Set(owned) == Set(Bench.toolNames))
    }

    @Test("Defaults keep every module on, and core is always on")
    func defaults() {
        let settings = BenchSettings.load(env: [:])
        #expect(settings.enabledModules == Set(BenchModules.all.map(\.id)))
        #expect(settings.approveDeviceWrites == false)
        #expect(settings.warnings.isEmpty)
    }

    @Test("BENCH_MODULES replaces the defaults and always keeps core")
    func moduleList() {
        let settings = BenchSettings.load(env: ["BENCH_MODULES": "serial, usb"])
        #expect(settings.enabledModules == ["core", "serial", "usb"])
    }

    @Test("Per-module switch overrides the list")
    func perModuleSwitch() {
        let off = BenchSettings.load(env: ["BENCH_USB_ENABLED": "0"])
        #expect(!off.isEnabled("usb"))
        #expect(off.isEnabled("serial"))

        let on = BenchSettings.load(env: ["BENCH_MODULES": "serial", "BENCH_HID_ENABLED": "true"])
        #expect(on.isEnabled("hid"))
    }

    @Test("Core cannot be switched off")
    func coreAlwaysOn() {
        let settings = BenchSettings.load(env: ["BENCH_CORE_ENABLED": "0", "BENCH_MODULES": "serial"])
        #expect(settings.isEnabled("core"))
    }

    @Test("Unknown module names and bad booleans are reported, not fatal")
    func badSettingsWarn() {
        let settings = BenchSettings.load(env: ["BENCH_MODULES": "usb,nope", "BENCH_SERIAL_ENABLED": "maybe"])
        #expect(settings.enabledModules == ["core", "usb"])
        #expect(settings.warnings.count == 2)
    }

    @Test("Write pre-approval is off unless explicitly set")
    func writeApproval() {
        #expect(BenchSettings.load(env: ["BENCH_APPROVE_DEVICE_WRITES": "1"]).approveDeviceWrites)
        #expect(!BenchSettings.load(env: ["BENCH_APPROVE_DEVICE_WRITES": "0"]).approveDeviceWrites)
        #expect(!BenchSettings.load(env: ["BENCH_APPROVE_DEVICE_WRITES": "true-ish"]).approveDeviceWrites)
    }

    @Test("Standard error text has the bench.<module>.<code> shape")
    func errorShape() {
        let text = benchErrorText(module: "usb", code: "device_not_found", message: "No device.", fix: "Run list_usb_devices.")
        #expect(text == "bench.usb.device_not_found: No device. Fix: Run list_usb_devices.")
    }

    @Test("Plain handler failures are normalized to a coded error")
    func normalization() {
        let missing = normalizeErrorText(module: "serial", tool: "serial_open", text: "Missing required parameter: port")
        #expect(missing.hasPrefix("bench.serial.missing_argument: Missing required parameter: port Fix: "))

        let notFound = normalizeErrorText(module: "usb", tool: "get_device_info", text: "No device found matching 'x'")
        #expect(notFound.hasPrefix("bench.usb.device_not_found: "))
        #expect(notFound.contains("Fix: "))

        let already = "bench.serial.write_declined: x Fix: y"
        #expect(normalizeErrorText(module: "serial", tool: "t", text: already) == already)
    }

    @Test("Writes need approval, reads do not, and hid_send depends on its action")
    func writeClassification() {
        #expect(DeviceWrites.requiresApproval(tool: "serial_write", arguments: nil))
        #expect(DeviceWrites.requiresApproval(tool: "flash_firmware", arguments: nil))
        #expect(DeviceWrites.requiresApproval(tool: "port_reset", arguments: ["confirm": .bool(true)]))
        #expect(!DeviceWrites.requiresApproval(tool: "serial_read", arguments: nil))
        #expect(!DeviceWrites.requiresApproval(tool: "list_usb_devices", arguments: nil))
        #expect(!DeviceWrites.requiresApproval(tool: "hid_send", arguments: ["action": .string("get_report")]))
        #expect(DeviceWrites.requiresApproval(tool: "hid_send", arguments: ["action": .string("send_report")]))
    }

    @Test("hid_send fails closed: only the exact read actions skip approval")
    func hidSendFailsClosed() {
        func needs(_ action: String?) -> Bool {
            var args: [String: Value]? = nil
            if let action { args = ["action": .string(action)] }
            return DeviceWrites.requiresApproval(tool: "hid_send", arguments: args)
        }
        #expect(needs("send_report"))
        #expect(needs("Send_Report"), "case variant of a write must not bypass approval")
        #expect(needs("SEND_REPORT"))
        #expect(needs("send_report "), "trailing space must not bypass approval")
        #expect(needs(" get_report"), "leading space is not a read action")
        #expect(needs("bogus"), "unknown actions need approval")
        #expect(needs(""))
        #expect(needs(nil), "a missing action needs approval")
        #expect(!needs("get_report"))
        #expect(!needs("GET_REPORT"))
        #expect(!needs("list_reports"))
    }

    @Test("chip_detect needs approval because it resets the chip")
    func chipDetectNeedsApproval() {
        #expect(DeviceWrites.requiresApproval(tool: "chip_detect", arguments: ["identifier": .string("x")]))
        let byName = Dictionary(uniqueKeysWithValues: Bench.tools.map { ($0.name, $0) })
        #expect(byName["chip_detect"]?.annotations.readOnlyHint == false)
        #expect(byName["chip_detect"]?.annotations.destructiveHint == true)
    }

    @Test("Serial device paths: only /dev/cu.* and /dev/tty.* with safe characters")
    func devicePathValidation() {
        #expect(DevicePath.isValid("/dev/cu.usbserial-2120"))
        #expect(DevicePath.isValid("/dev/tty.usbmodem14101"))
        #expect(DevicePath.isValid("/dev/cu.SLAB_USB.1"))
        let rejected = [
            "/dev/cu.x;touch /tmp/pwned",
            "/dev/cu.x$(id)",
            "/dev/cu.x`id`",
            "/dev/cu.x && id",
            "/dev/cu.x|id",
            "/dev/cu.x'",
            "/dev/cu.x\"",
            "/dev/cu.x\n",
            "/dev/cu.x\nid",
            "/dev/cu.x/../../etc/passwd",
            "/dev/null",
            "/dev/disk0",
            "/dev/ttyS0",
            "/dev/cu.",
            "/dev/cu.",
            "../dev/cu.x",
            "cu.x",
            "",
            "/opt/cu.x",
        ]
        for path in rejected {
            #expect(!DevicePath.isValid(path), "accepted \(path)")
            #expect(DevicePath.problem(path)?.hasPrefix("Invalid port ") == true)
        }
    }

    @Test("The approval prompt shows the full payload")
    func approvalPromptShowsPayload() {
        let prompt = DeviceWrites.approvalPrompt(
            tool: "serial_write",
            arguments: ["port": .string("/dev/cu.test"), "data": .string("reset\r\n")]
        )
        #expect(prompt.contains("\"data\": \"reset\\r\\n\""))
        #expect(prompt.contains("\"port\": \"/dev/cu.test\""))
    }

    @Test("Every tool carries annotations and the output schema")
    func decoration() {
        for tool in Bench.tools {
            #expect(tool.outputSchema != nil, "\(tool.name) has no outputSchema")
            #expect(tool.annotations.readOnlyHint != nil, "\(tool.name) has no readOnlyHint")
        }
        let byName = Dictionary(uniqueKeysWithValues: Bench.tools.map { ($0.name, $0) })
        #expect(byName["ping"]?.annotations.readOnlyHint == true)
        #expect(byName["serial_write"]?.annotations.destructiveHint == true)
        #expect(byName["serial_write"]?.annotations.readOnlyHint == false)
    }

    @Test("The envelope carries ok, module, tool and text")
    func envelope() {
        let value = BenchEnvelope.make(ok: false, module: "usb", tool: "eject_device", text: "x")
        guard case .object(let fields) = value else {
            Issue.record("envelope is not an object")
            return
        }
        #expect(fields["ok"]?.boolValue == false)
        #expect(fields["module"]?.stringValue == "usb")
        #expect(fields["tool"]?.stringValue == "eject_device")
        #expect(fields["text"]?.stringValue == "x")
    }
}
