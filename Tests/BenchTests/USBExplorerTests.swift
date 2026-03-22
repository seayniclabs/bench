import Testing
import MCP
@testable import BenchCore

@Suite("Tool Registration")
struct ToolRegistrationTests {

    @Test("All 16 tools are defined")
    func toolCount() {
        #expect(Bench.tools.count == 16)
    }

    @Test("Tool names match expected set")
    func toolNames() {
        let expected: Set<String> = [
            "ping",
            "list_usb_devices",
            "get_device_info",
            "identify_device",
            "eject_device",
            "list_serial_ports",
            "hub_topology",
            "device_descriptors",
            "monitor_events",
            "snapshot_state",
            "diagnose_device",
            "power_info",
            "tag_device",
            "port_reset",
            "flash_firmware",
            "hid_send"
        ]
        let actual = Set(Bench.toolNames)
        #expect(actual == expected)
    }

    @Test("Every tool has a description")
    func allToolsHaveDescriptions() {
        for tool in Bench.tools {
            #expect(tool.description != nil)
            #expect(tool.description?.isEmpty == false)
        }
    }

    @Test("Server metadata is set")
    func serverMetadata() {
        #expect(Bench.serverName == "bench")
        #expect(Bench.serverVersion == "0.1.0")
    }
}

@Suite("Required Parameters")
struct RequiredParameterTests {
    private func requiredParams(for toolName: String) -> [String] {
        guard let tool = Bench.tools.first(where: { $0.name == toolName }),
              case .object(let schema) = tool.inputSchema,
              case .array(let required) = schema["required"] else {
            return []
        }
        return required.compactMap { if case .string(let s) = $0 { return s } else { return nil } }
    }

    @Test("ping has no required parameters")
    func pingNoRequired() {
        #expect(requiredParams(for: "ping").isEmpty)
    }

    @Test("list_usb_devices has no required parameters")
    func listNoRequired() {
        #expect(requiredParams(for: "list_usb_devices").isEmpty)
    }

    @Test("get_device_info requires identifier")
    func getDeviceInfoRequired() {
        #expect(requiredParams(for: "get_device_info") == ["identifier"])
    }

    @Test("identify_device requires identifier")
    func identifyDeviceRequired() {
        #expect(requiredParams(for: "identify_device") == ["identifier"])
    }

    @Test("eject_device requires identifier")
    func ejectDeviceRequired() {
        #expect(requiredParams(for: "eject_device") == ["identifier"])
    }
}

@Suite("Tool Schemas")
struct ToolSchemaTests {
    private func propertyNames(for toolName: String) -> Set<String> {
        guard let tool = Bench.tools.first(where: { $0.name == toolName }),
              case .object(let schema) = tool.inputSchema,
              case .object(let properties) = schema["properties"] else {
            return []
        }
        return Set(properties.keys)
    }

    @Test("list_usb_devices has device_type and include_internal params")
    func listDevicesParams() {
        let params = propertyNames(for: "list_usb_devices")
        #expect(params.contains("device_type"))
        #expect(params.contains("include_internal"))
    }

    @Test("eject_device has identifier and force params")
    func ejectDeviceParams() {
        let params = propertyNames(for: "eject_device")
        #expect(params.contains("identifier"))
        #expect(params.contains("force"))
    }
}
