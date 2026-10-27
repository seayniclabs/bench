import Foundation
import MCP

// MARK: - Modules

/// A group of related tools that can be switched on or off independently.
public struct BenchModule: Sendable, Equatable {
    public let id: String
    public let title: String
    public let summary: String
    /// Whether the module is on when no setting names it. Modules that
    /// shipped before 0.3.0 stay on so existing installs keep their tools.
    /// Any module added in a later release must ship with this set to false.
    public let defaultEnabled: Bool
    public let tools: [String]
}

public enum BenchModules {
    /// Always on. Cannot be switched off.
    public static let core = BenchModule(
        id: "core",
        title: "Core",
        summary: "Health check and module discovery",
        defaultEnabled: true,
        tools: ["ping", "bench_modules"]
    )

    public static let usb = BenchModule(
        id: "usb",
        title: "USB discovery",
        summary: "Enumerate, identify, inspect and monitor USB devices",
        defaultEnabled: true,
        tools: [
            "list_usb_devices", "get_device_info", "identify_device", "eject_device",
            "hub_topology", "tag_device", "port_reset", "power_info", "monitor_events",
            "snapshot_state", "diagnose_device", "device_descriptors",
        ]
    )

    public static let serial = BenchModule(
        id: "serial",
        title: "Serial ports",
        summary: "List serial ports and open, read, write and monitor them",
        defaultEnabled: true,
        tools: [
            "list_serial_ports", "serial_open", "serial_read", "serial_write",
            "serial_close", "serial_monitor",
        ]
    )

    public static let firmware = BenchModule(
        id: "firmware",
        title: "Firmware",
        summary: "Detect chips and flash firmware with esptool, dfu-util, avrdude or UF2",
        defaultEnabled: true,
        tools: ["chip_detect", "flash_firmware"]
    )

    public static let hid = BenchModule(
        id: "hid",
        title: "HID",
        summary: "Send and read raw HID reports",
        defaultEnabled: true,
        tools: ["hid_send"]
    )

    /// Every module, core first. Order is the order shown by bench_modules.
    public static let all: [BenchModule] = [core, usb, serial, firmware, hid]

    public static func module(for tool: String) -> BenchModule? {
        all.first { $0.tools.contains(tool) }
    }
}

// MARK: - Settings

/// Settings come from environment variables only, so the server starts with an
/// empty environment. Precedence, highest first:
///   1. BENCH_<MODULE>_ENABLED=1|0 for one module
///   2. BENCH_MODULES=usb,serial (comma list; replaces the defaults)
///   3. the module's defaultEnabled value
/// BENCH_APPROVE_DEVICE_WRITES=1 pre-approves device-writing tools. Without it,
/// each write asks the person through MCP elicitation, or is refused.
public struct BenchSettings: Sendable, Equatable {
    public let enabledModules: Set<String>
    public let approveDeviceWrites: Bool
    /// Human-readable notes about settings that were ignored.
    public let warnings: [String]

    public init(enabledModules: Set<String>, approveDeviceWrites: Bool, warnings: [String] = []) {
        self.enabledModules = enabledModules
        self.approveDeviceWrites = approveDeviceWrites
        self.warnings = warnings
    }

    public func isEnabled(_ moduleID: String) -> Bool {
        enabledModules.contains(moduleID)
    }

    public static func load(env: [String: String]) -> BenchSettings {
        var warnings: [String] = []
        let known = Set(BenchModules.all.map(\.id))

        var enabled: Set<String>
        if let list = env["BENCH_MODULES"], !list.trimmingCharacters(in: .whitespaces).isEmpty {
            let ids = list.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
            enabled = []
            for id in ids where !id.isEmpty {
                if known.contains(id) {
                    enabled.insert(id)
                } else {
                    warnings.append("BENCH_MODULES names unknown module '\(id)' and it was ignored.")
                }
            }
        } else {
            enabled = Set(BenchModules.all.filter(\.defaultEnabled).map(\.id))
        }

        for module in BenchModules.all where module.id != "core" {
            let key = "BENCH_\(module.id.uppercased())_ENABLED"
            guard let raw = env[key] else { continue }
            switch raw.lowercased() {
            case "1", "true", "on", "yes":
                enabled.insert(module.id)
            case "0", "false", "off", "no":
                enabled.remove(module.id)
            default:
                warnings.append("\(key)='\(raw)' is not a boolean (use 1 or 0) and was ignored.")
            }
        }

        enabled.insert("core")

        let approve = ["1", "true", "on", "yes"].contains(
            (env["BENCH_APPROVE_DEVICE_WRITES"] ?? "").lowercased()
        )
        return BenchSettings(enabledModules: enabled, approveDeviceWrites: approve, warnings: warnings)
    }
}

// MARK: - Errors

/// Every error Bench returns reads `bench.<module>.<code>: <message> Fix: <hint>`.
public func benchErrorText(module: String, code: String, message: String, fix: String) -> String {
    "bench.\(module).\(code): \(message) Fix: \(fix)"
}

/// Maps a tool's plain-text failure onto the standard error shape. Text that
/// already has the standard shape is left alone.
public func normalizeErrorText(module: String, tool: String, text: String) -> String {
    if text.hasPrefix("bench.") { return text }
    let (code, fix): (String, String)
    if text.hasPrefix("Missing required parameter") {
        (code, fix) = ("missing_argument", "Pass the parameter named in the message and call \(tool) again.")
    } else if text.hasPrefix("No device found") {
        (code, fix) = ("device_not_found", "Run list_usb_devices and pass a serial number, location ID or name from its output.")
    } else if text.hasPrefix("Invalid ") {
        (code, fix) = ("invalid_argument", "Use one of the values named in the message.")
    } else if text.hasPrefix("Unknown tool") {
        (code, fix) = ("unknown_tool", "Call bench_modules to list the tools that are available.")
    } else if text.hasPrefix("Snapshot ") {
        (code, fix) = ("not_found", "Run snapshot_state with action list to see saved snapshots.")
    } else if text.hasPrefix("Eject failed") {
        (code, fix) = ("eject_failed", "Quit apps that use the volume, then retry. Use force only if you accept losing unsaved data.")
    } else {
        (code, fix) = ("tool_failed", "Check the device is connected and that macOS has granted the access this tool needs (USB, serial or Bluetooth), then retry.")
    }
    return benchErrorText(module: module, code: code, message: text, fix: fix)
}

// MARK: - Device writes

/// Tools that change something on real hardware or in device state.
public enum DeviceWrites {
    /// chip_detect is here because esptool resets the chip into its bootloader.
    public static let tools: Set<String> = [
        "eject_device", "port_reset", "flash_firmware", "serial_write", "hid_send", "chip_detect",
    ]

    /// hid_send needs approval for every action except the known read actions.
    /// Fails closed: a missing or non-string action needs approval.
    public static func requiresApproval(tool: String, arguments: [String: Value]?) -> Bool {
        guard tools.contains(tool) else { return false }
        if tool == "hid_send" {
            return !HIDAction.isRead(arguments?["action"]?.stringValue)
        }
        return true
    }

    /// The text the person sees before approving. Shows the full payload.
    public static func approvalPrompt(tool: String, arguments: [String: Value]?) -> String {
        let payload = (arguments ?? [:]).sorted { $0.key < $1.key }
            .map { "\(jsonString($0.key)): \(describe($0.value))" }
            .joined(separator: ", ")
        return "Bench is about to run \(tool) on a connected device, which changes hardware or device state. Arguments: {\(payload)}. Allow this one call?"
    }

    private static func describe(_ value: Value) -> String {
        if let s = value.stringValue { return jsonString(s) }
        if let b = value.boolValue { return b ? "true" : "false" }
        if let i = value.intValue { return String(i) }
        if let d = value.doubleValue { return String(d) }
        return "\(value)"
    }
}

/// Quotes and escapes a string the way JSON does, so control characters show.
func jsonString(_ text: String) -> String {
    let data = (try? JSONSerialization.data(withJSONObject: [text], options: [])) ?? Data()
    let encoded = String(decoding: data, as: UTF8.self)
    let inner = String(encoded.dropFirst().dropLast())
    return inner.replacingOccurrences(of: "\\/", with: "/")
}

// MARK: - Structured results

/// The envelope every tool result carries in structuredContent.
public enum BenchEnvelope {
    public static let schema: Value = .object([
        "type": .string("object"),
        "properties": .object([
            "ok": .object(["type": .string("boolean")]),
            "module": .object(["type": .string("string")]),
            "tool": .object(["type": .string("string")]),
            "text": .object([
                "type": .string("string"),
                "description": .string("Human-readable result, or the bench.<module>.<code> error"),
            ]),
        ]),
        "required": .array([.string("ok"), .string("module"), .string("tool"), .string("text")]),
    ])

    public static func make(ok: Bool, module: String, tool: String, text: String) -> Value {
        .object([
            "ok": .bool(ok),
            "module": .string(module),
            "tool": .string(tool),
            "text": .string(text),
        ])
    }
}

extension Bench {
    /// Tools that only read. Anything not listed here is annotated as not read-only.
    static let readOnlyTools: Set<String> = [
        "ping", "bench_modules", "list_usb_devices", "get_device_info", "identify_device",
        "list_serial_ports", "hub_topology", "power_info", "monitor_events", "diagnose_device",
        "device_descriptors", "serial_read", "serial_monitor",
    ]

    /// Adds MCP annotations and the output schema to a tool definition.
    static func decorate(_ tool: Tool) -> Tool {
        let readOnly = readOnlyTools.contains(tool.name)
        let destructive = DeviceWrites.tools.contains(tool.name)
        return Tool(
            name: tool.name,
            description: tool.description,
            inputSchema: tool.inputSchema,
            annotations: .init(
                readOnlyHint: readOnly,
                destructiveHint: destructive,
                idempotentHint: readOnly,
                openWorldHint: false
            ),
            outputSchema: BenchEnvelope.schema
        )
    }
}
