import MCP

public enum Bench {
    public static let serverName = "bench"
    public static let serverVersion = "0.1.0"

    public static let toolNames: [String] = tools.map(\.name)

    public static let tools: [Tool] = [
        Tool(
            name: "ping",
            description: "Check if Bench is running and IOKit is available",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([:]),
                "required": .array([])
            ])
        ),
        Tool(
            name: "list_usb_devices",
            description: "List all connected USB devices with type, vendor, product, and serial information",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "device_type": .object([
                        "type": .string("string"),
                        "description": .string("Filter by device type: storage, audio, hub, input, video, serial, microcontroller, or all (default: all)")
                    ]),
                    "include_internal": .object([
                        "type": .string("boolean"),
                        "description": .string("Include Apple internal devices like Bluetooth controller, camera (default: false)")
                    ])
                ]),
                "required": .array([])
            ])
        ),
        Tool(
            name: "get_device_info",
            description: "Get detailed information about a specific USB device by serial number, location ID, or name",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "identifier": .object([
                        "type": .string("string"),
                        "description": .string("Device serial number, location ID (e.g. 0x02100000), or device name")
                    ])
                ]),
                "required": .array([.string("identifier")])
            ])
        ),
        Tool(
            name: "identify_device",
            description: "Identify a connected USB device — recognizes common maker boards (Arduino, Raspberry Pi Pico, ESP32, etc.) and provides context about the device",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "identifier": .object([
                        "type": .string("string"),
                        "description": .string("Device serial number, location ID, or device name")
                    ])
                ]),
                "required": .array([.string("identifier")])
            ])
        ),
        Tool(
            name: "eject_device",
            description: "Safely unmount and eject a removable USB storage device",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "identifier": .object([
                        "type": .string("string"),
                        "description": .string("Device serial number, location ID, volume name, or mount point")
                    ]),
                    "force": .object([
                        "type": .string("boolean"),
                        "description": .string("Force eject even if volumes are in use (default: false)")
                    ])
                ]),
                "required": .array([.string("identifier")])
            ])
        ),
        Tool(
            name: "list_serial_ports",
            description: "Enumerate all serial ports on the system with their associated USB device info, type classification, and matched device details",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "device_type": .object([
                        "type": .string("string"),
                        "description": .string("Filter by port type: usb, bluetooth, built_in, or all (default: all)")
                    ])
                ]),
                "required": .array([])
            ])
        ),
        Tool(
            name: "hub_topology",
            description: "Display the USB hub topology tree showing which devices are connected to which hubs and ports, with speeds and power draw",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "include_internal": .object([
                        "type": .string("boolean"),
                        "description": .string("Show Apple internal hubs and devices (default: false)")
                    ])
                ]),
                "required": .array([])
            ])
        )
    ]
}
