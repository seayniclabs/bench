import MCP

public enum Bench {
    public static let serverName = "bench"
    public static let serverVersion = "0.2.0"

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
        ),
        Tool(
            name: "tag_device",
            description: "Set, get, list, or remove persistent user-defined aliases (tags) for USB devices. Tags are stored locally and survive reconnections.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "action": .object([
                        "type": .string("string"),
                        "description": .string("Action to perform: set, get, list, or remove")
                    ]),
                    "identifier": .object([
                        "type": .string("string"),
                        "description": .string("Device serial number, location ID, or name (required for set, get, remove)")
                    ]),
                    "tag": .object([
                        "type": .string("string"),
                        "description": .string("The alias/tag to assign to the device (required for set)")
                    ])
                ]),
                "required": .array([.string("action")])
            ])
        ),
        Tool(
            name: "port_reset",
            description: "Reset a USB port to recover a frozen or unresponsive device. Simulates an unplug/replug cycle via IOKit re-enumeration. Only works on external/removable devices.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "identifier": .object([
                        "type": .string("string"),
                        "description": .string("Device serial number, location ID, or name")
                    ]),
                    "confirm": .object([
                        "type": .string("boolean"),
                        "description": .string("Must be true to proceed — port reset can disrupt active transfers")
                    ])
                ]),
                "required": .array([.string("identifier"), .string("confirm")])
            ])
        ),
        Tool(
            name: "power_info",
            description: "Report USB power draw and capabilities for devices — bus power available, current draw, self-powered vs bus-powered, hub power budgets, and charging type detection",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "identifier": .object([
                        "type": .string("string"),
                        "description": .string("Device serial number, location ID, or name. If omitted, shows power summary for all devices.")
                    ])
                ]),
                "required": .array([])
            ])
        ),
        Tool(
            name: "monitor_events",
            description: "Monitor USB connect/disconnect events. Uses a polling approach — first call snapshots current state, subsequent calls report what changed since last check. Maintains a circular buffer of the last 50 events.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "clear": .object([
                        "type": .string("boolean"),
                        "description": .string("Clear the event log and re-snapshot current state (default: false)")
                    ])
                ]),
                "required": .array([])
            ])
        ),
        Tool(
            name: "snapshot_state",
            description: "Capture and compare USB device state snapshots. Save current state to a named snapshot, list snapshots, compare two snapshots or compare a snapshot to current state, or delete a snapshot.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "action": .object([
                        "type": .string("string"),
                        "description": .string("Action to perform: capture, list, compare, or delete")
                    ]),
                    "name": .object([
                        "type": .string("string"),
                        "description": .string("Snapshot name (for capture: name to save as; for compare: snapshot to compare from; for delete: snapshot to remove). Default: timestamp-based name.")
                    ]),
                    "compare_to": .object([
                        "type": .string("string"),
                        "description": .string("For compare action: name of second snapshot to compare against. If omitted, compares to current live state.")
                    ])
                ]),
                "required": .array([.string("action")])
            ])
        ),
        Tool(
            name: "diagnose_device",
            description: "Query macOS system logs and IOKit for USB errors related to a specific device. Reports error count, error types, and recent log entries.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "identifier": .object([
                        "type": .string("string"),
                        "description": .string("Device serial number, location ID, or device name")
                    ]),
                    "timeframe": .object([
                        "type": .string("string"),
                        "description": .string("How far back to search: 1h, 6h, or 24h (default: 1h)")
                    ])
                ]),
                "required": .array([.string("identifier")])
            ])
        ),
        Tool(
            name: "device_descriptors",
            description: "Read full USB descriptor chain for a device — device descriptor, configuration descriptors, interface descriptors, and endpoint descriptors with class codes, transfer types, and max packet sizes",
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
            name: "flash_firmware",
            description: "Flash firmware to a USB device. Supports ESP32 (esptool), STM32 (dfu-util), Arduino AVR (avrdude), and RP2040 (UF2 copy). Shows the exact command before executing. Requires confirm=true — flashing is destructive.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "identifier": .object([
                        "type": .string("string"),
                        "description": .string("Device serial number, location ID, or name")
                    ]),
                    "firmware_path": .object([
                        "type": .string("string"),
                        "description": .string("Path to the firmware file (.bin, .hex, .uf2, .elf)")
                    ]),
                    "tool": .object([
                        "type": .string("string"),
                        "description": .string("Override auto-detection: esptool, dfu-util, avrdude, or uf2")
                    ]),
                    "port": .object([
                        "type": .string("string"),
                        "description": .string("Serial port override (auto-detected from device if not specified)")
                    ]),
                    "baud": .object([
                        "type": .string("integer"),
                        "description": .string("Baud rate for serial flashing (default varies by tool)")
                    ]),
                    "confirm": .object([
                        "type": .string("boolean"),
                        "description": .string("Must be true — flashing is a destructive operation")
                    ])
                ]),
                "required": .array([.string("identifier"), .string("firmware_path"), .string("confirm")])
            ])
        ),
        Tool(
            name: "chip_detect",
            description: "Detect the exact chip type of a connected microcontroller via esptool. Resolves ambiguous USB identifications (e.g. ESP32-S2 vs S3 when sharing PID 0x1001). Returns chip type, revision, features, crystal frequency, and MAC address.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "identifier": .object([
                        "type": .string("string"),
                        "description": .string("Device serial number, location ID, or name")
                    ]),
                    "port": .object([
                        "type": .string("string"),
                        "description": .string("Serial port override (auto-detected from device if not specified)")
                    ])
                ]),
                "required": .array([.string("identifier")])
            ])
        ),
        Tool(
            name: "hid_send",
            description: "Interact with USB HID (Human Interface Devices). Send output/feature reports, read input/feature reports, or list available report descriptors. Useful for controlling Stream Decks, macro pads, and custom HID devices.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "identifier": .object([
                        "type": .string("string"),
                        "description": .string("Device serial number, location ID, or name")
                    ]),
                    "action": .object([
                        "type": .string("string"),
                        "description": .string("Action to perform: send_report, get_report, or list_reports")
                    ]),
                    "report_type": .object([
                        "type": .string("string"),
                        "description": .string("Report type: output or feature (default: output for send, feature for get)")
                    ]),
                    "report_id": .object([
                        "type": .string("integer"),
                        "description": .string("Report ID (default: 0)")
                    ]),
                    "data": .object([
                        "type": .string("string"),
                        "description": .string("Hex string of bytes to send, e.g. '0x01 0xFF 0x00' or '01ff00'")
                    ]),
                    "confirm": .object([
                        "type": .string("boolean"),
                        "description": .string("Required for send_report — sending data to a device is potentially destructive")
                    ])
                ]),
                "required": .array([.string("identifier"), .string("action")])
            ])
        ),
        Tool(
            name: "serial_open",
            description: "Open a serial connection to a port (e.g. /dev/cu.usbserial-2120). Configures baud rate, data bits, stop bits, and parity for raw communication.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "port": .object([
                        "type": .string("string"),
                        "description": .string("Serial port path, e.g. /dev/cu.usbserial-2120")
                    ]),
                    "baud_rate": .object([
                        "type": .string("integer"),
                        "description": .string("Baud rate (default: 115200). Common values: 300, 1200, 2400, 4800, 9600, 19200, 38400, 57600, 115200, 230400")
                    ]),
                    "data_bits": .object([
                        "type": .string("integer"),
                        "description": .string("Data bits: 5, 6, 7, or 8 (default: 8)")
                    ]),
                    "stop_bits": .object([
                        "type": .string("integer"),
                        "description": .string("Stop bits: 1 or 2 (default: 1)")
                    ]),
                    "parity": .object([
                        "type": .string("string"),
                        "description": .string("Parity: none, even, or odd (default: none)")
                    ])
                ]),
                "required": .array([.string("port")])
            ])
        ),
        Tool(
            name: "serial_read",
            description: "Read available data from an open serial connection. Returns whatever is in the receive buffer, waiting up to the timeout for data to arrive.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "port": .object([
                        "type": .string("string"),
                        "description": .string("Serial port path (must be opened with serial_open first)")
                    ]),
                    "timeout": .object([
                        "type": .string("number"),
                        "description": .string("Read timeout in seconds (default: 1.0)")
                    ])
                ]),
                "required": .array([.string("port")])
            ])
        ),
        Tool(
            name: "serial_write",
            description: "Write data or a command to an open serial connection. Text is sent as UTF-8 with \\r\\n appended. Hex bytes can be sent as '0x01 0xFF' or '01FF'.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "port": .object([
                        "type": .string("string"),
                        "description": .string("Serial port path (must be opened with serial_open first)")
                    ]),
                    "data": .object([
                        "type": .string("string"),
                        "description": .string("Data to send — text string or hex bytes (e.g. '0x01 0xFF 0x00')")
                    ])
                ]),
                "required": .array([.string("port"), .string("data")])
            ])
        ),
        Tool(
            name: "serial_close",
            description: "Close an open serial connection and restore the port to its original state.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "port": .object([
                        "type": .string("string"),
                        "description": .string("Serial port path to close")
                    ])
                ]),
                "required": .array([.string("port")])
            ])
        ),
        Tool(
            name: "serial_monitor",
            description: "Read from a serial port for a specified duration and return all output. Useful for capturing boot output, log streams, or device responses. Can auto-open the port if not already open.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "port": .object([
                        "type": .string("string"),
                        "description": .string("Serial port path, e.g. /dev/cu.usbserial-2120")
                    ]),
                    "seconds": .object([
                        "type": .string("number"),
                        "description": .string("How long to monitor in seconds (default: 5.0, max: 30.0)")
                    ]),
                    "auto_open": .object([
                        "type": .string("boolean"),
                        "description": .string("Automatically open the port if not already open (default: false)")
                    ]),
                    "baud_rate": .object([
                        "type": .string("integer"),
                        "description": .string("Baud rate for auto_open (default: 115200)")
                    ])
                ]),
                "required": .array([.string("port")])
            ])
        ),
    ]
}
