import Foundation
import MCP
import BenchCore

// MARK: - Entry Point

func log(_ msg: String) {
    FileHandle.standardError.write(Data("[bench] \(msg)\n".utf8))
}

do {
    log("starting server...")
    try await startServer()
} catch {
    log("error: \(error)")
    exit(1)
}

// MARK: - Server

func startServer() async throws {
    let server = Server(
        name: Bench.serverName,
        version: Bench.serverVersion,
        capabilities: Server.Capabilities(
            tools: .init()
        )
    )

    await server.withMethodHandler(ListTools.self) { _ in
        .init(tools: Bench.tools)
    }

    await server.withMethodHandler(CallTool.self) { params in
        switch params.name {
        case "ping":
            return handlePing()
        case "list_usb_devices":
            return handleListDevices(params: params)
        case "get_device_info":
            return try handleGetDeviceInfo(params: params)
        case "identify_device":
            return try handleIdentifyDevice(params: params)
        case "eject_device":
            return try handleEjectDevice(params: params)
        case "list_serial_ports":
            return handleListSerialPorts(params: params)
        case "hub_topology":
            return handleHubTopology(params: params)
        case "tag_device":
            return handleTagDevice(params: params)
        case "port_reset":
            return handlePortReset(params: params)
        case "power_info":
            return handlePowerInfo(params: params)
        case "monitor_events":
            return handleMonitorEvents(params: params)
        case "snapshot_state":
            return handleSnapshotState(params: params)
        case "diagnose_device":
            return handleDiagnoseDevice(params: params)
        case "device_descriptors":
            return handleDeviceDescriptors(params: params)
        case "flash_firmware":
            return handleFlashFirmware(params: params)
        case "chip_detect":
            return handleChipDetect(params: params)
        case "hid_send":
            return handleHIDSend(params: params)
        case "serial_open":
            return handleSerialOpen(params: params)
        case "serial_read":
            return handleSerialRead(params: params)
        case "serial_write":
            return handleSerialWrite(params: params)
        case "serial_close":
            return handleSerialClose(params: params)
        case "serial_monitor":
            return handleSerialMonitor(params: params)
        default:
            return .init(content: [.text("Unknown tool: \(params.name)")], isError: true)
        }
    }

    let transport = StdioTransport()
    try await server.start(transport: transport)
    await server.waitUntilCompleted()
}

// MARK: - Tool Handlers

func handlePing() -> CallTool.Result {
    let macosVersion = ProcessInfo.processInfo.operatingSystemVersionString
    let ioKitOK = IOKitBridge.isAvailable

    let response = """
    {
      "status": "ok",
      "server": "Bench",
      "version": "\(Bench.serverVersion)",
      "macos_version": "\(macosVersion)",
      "iokit_available": \(ioKitOK)
    }
    """
    return .init(content: [.text(response)])
}

func handleListDevices(params: CallTool.Parameters) -> CallTool.Result {
    let filterType = params.arguments?["device_type"]?.stringValue ?? "all"
    let includeInternal = params.arguments?["include_internal"]?.boolValue ?? false

    var devices = IOKitBridge.enumerateDevices(includeInternal: includeInternal)

    // Enrich with serial port info
    SerialPortBridge.enrichDevices(&devices)

    // Enrich storage devices with diskutil info
    let volumes = DiskUtilBridge.externalVolumes()
    enrichStorageDevices(&devices, with: volumes)

    // Filter by type
    if filterType != "all" {
        devices = devices.filter { $0.deviceType == filterType }
    }

    if devices.isEmpty {
        let msg = filterType == "all"
            ? "No USB devices found."
            : "No USB devices of type '\(filterType)' found."
        return .init(content: [.text(msg)])
    }

    let deviceLines = devices.map { formatDeviceSummary($0) }
    let output = """
    Found \(devices.count) USB device\(devices.count == 1 ? "" : "s"):

    \(deviceLines.joined(separator: "\n\n"))
    """
    return .init(content: [.text(output)])
}

func handleGetDeviceInfo(params: CallTool.Parameters) throws -> CallTool.Result {
    guard let identifier = params.arguments?["identifier"]?.stringValue else {
        return .init(content: [.text("Missing required parameter: identifier")], isError: true)
    }

    guard var device = IOKitBridge.findDevice(identifier: identifier) else {
        return .init(content: [.text("No device found matching '\(identifier)'")], isError: true)
    }

    // Enrich with serial port info
    var singleDevice = [device]
    SerialPortBridge.enrichDevices(&singleDevice)
    device = singleDevice[0]

    // Enrich with storage info if applicable
    if device.deviceType == "storage" {
        let volumes = DiskUtilBridge.externalVolumes()
        enrichSingleDevice(&device, with: volumes)
    }

    return .init(content: [.text(formatDeviceDetail(device))])
}

func handleIdentifyDevice(params: CallTool.Parameters) throws -> CallTool.Result {
    guard let identifier = params.arguments?["identifier"]?.stringValue else {
        return .init(content: [.text("Missing required parameter: identifier")], isError: true)
    }

    guard let device = IOKitBridge.findDevice(identifier: identifier) else {
        return .init(content: [.text("No device found matching '\(identifier)'")], isError: true)
    }

    if let known = DeviceDatabase.identify(vendorID: device.vendorID, productID: device.productID) {
        let output = """
        Device identified:
          Name: \(known.name)
          Vendor: \(known.vendor)
          Category: \(known.category)
          Notes: \(known.notes)
          Known device: true
          Vendor ID: \(String(format: "0x%04X", device.vendorID))
          Product ID: \(String(format: "0x%04X", device.productID))
          Serial: \(device.serialNumber.isEmpty ? "none" : device.serialNumber)
          USB Speed: \(device.usbSpeed)
          Location: \(device.locationID)
        """
        return .init(content: [.text(output)])
    } else {
        let vendorName = DeviceDatabase.vendorName(for: device.vendorID) ?? "Unknown vendor"
        let output = """
        Device not in known database:
          Name: \(device.name)
          Vendor: \(vendorName)
          Category: \(device.deviceType)
          Known device: false
          Vendor ID: \(String(format: "0x%04X", device.vendorID))
          Product ID: \(String(format: "0x%04X", device.productID))
          USB Class: \(device.deviceClass)/\(device.deviceSubclass)/\(device.deviceProtocol)
          Serial: \(device.serialNumber.isEmpty ? "none" : device.serialNumber)
          USB Speed: \(device.usbSpeed)
          Location: \(device.locationID)

        This device isn't in the known board database yet. If you know what it is, it can be added in a future update.
        """
        return .init(content: [.text(output)])
    }
}

func handleEjectDevice(params: CallTool.Parameters) throws -> CallTool.Result {
    guard let identifier = params.arguments?["identifier"]?.stringValue else {
        return .init(content: [.text("Missing required parameter: identifier")], isError: true)
    }

    let force = params.arguments?["force"]?.boolValue ?? false

    // Try to find the device first to validate it's a storage device
    if let device = IOKitBridge.findDevice(identifier: identifier) {
        if device.deviceType != "storage" {
            return .init(
                content: [.text("'\(device.name)' is a \(device.deviceType) device, not storage. Only storage devices can be ejected.")],
                isError: true
            )
        }
    }

    // Attempt eject — identifier could be a mount point, volume name, or BSD name
    let (success, message) = DiskUtilBridge.eject(identifier: identifier, force: force)

    if success {
        return .init(content: [.text("Ejected successfully: \(message)")])
    } else {
        return .init(content: [.text("Eject failed: \(message)")], isError: true)
    }
}

func handleListSerialPorts(params: CallTool.Parameters) -> CallTool.Result {
    let filterType = params.arguments?["device_type"]?.stringValue ?? "all"

    // Map filter string to device category
    let filter: SerialPortBridge.SerialPort.DeviceCategory?
    switch filterType.lowercased() {
    case "usb": filter = .usb
    case "bluetooth": filter = .bluetooth
    case "built_in", "builtin": filter = .builtIn
    case "all": filter = nil
    default:
        return .init(
            content: [.text("Invalid device_type '\(filterType)'. Use: usb, bluetooth, built_in, or all")],
            isError: true
        )
    }

    let ports = SerialPortBridge.allPorts(filterDeviceType: filter)

    if ports.isEmpty {
        let msg = filterType == "all"
            ? "No serial ports found."
            : "No serial ports of type '\(filterType)' found."
        return .init(content: [.text(msg)])
    }

    // Get USB devices for matching
    let usbDevices = IOKitBridge.enumerateDevices(includeInternal: true)

    let portLines = ports.map { port -> String in
        formatSerialPort(port, usbDevices: usbDevices)
    }

    let output = """
    Found \(ports.count) serial port\(ports.count == 1 ? "" : "s"):

    \(portLines.joined(separator: "\n\n"))
    """
    return .init(content: [.text(output)])
}

func handleHubTopology(params: CallTool.Parameters) -> CallTool.Result {
    let includeInternal = params.arguments?["include_internal"]?.boolValue ?? false

    let topology = IOKitBridge.enumerateHubTopology(includeInternal: includeInternal)

    if topology.isEmpty {
        return .init(content: [.text("No USB devices found in topology.")])
    }

    var lines: [String] = []
    for node in topology {
        formatTopologyNode(node, prefix: "", isLast: true, isRoot: true, lines: &lines)
    }

    let output = """
    USB Hub Topology:

    \(lines.joined(separator: "\n"))
    """
    return .init(content: [.text(output)])
}

// MARK: - Formatting

func formatDeviceSummary(_ device: USBDevice) -> String {
    var lines = [
        "  \(device.name)",
        "    Vendor: \(device.vendorName) (\(String(format: "0x%04X", device.vendorID)))",
        "    Type: \(device.deviceType)",
        "    Speed: \(device.usbSpeed)",
        "    Location: \(device.locationID)",
    ]

    if !device.serialNumber.isEmpty {
        lines.append("    Serial: \(device.serialNumber)")
    }

    if let port = device.serialPort {
        lines.append("    Serial Port: \(port)")
    }

    if let mp = device.mountPoint {
        lines.append("    Mount: \(mp)")
    }

    if let cap = device.capacityGB {
        let free = device.freeGB.map { String(format: "%.1f", $0) } ?? "?"
        lines.append("    Capacity: \(String(format: "%.1f", cap)) GB (\(free) GB free)")
    }

    // Check if it's a known device
    if let known = DeviceDatabase.identify(vendorID: device.vendorID, productID: device.productID) {
        lines.append("    Identified as: \(known.name)")
    }

    return lines.joined(separator: "\n")
}

func formatDeviceDetail(_ device: USBDevice) -> String {
    var lines = [
        "Device: \(device.name)",
        "  Vendor: \(device.vendorName) (\(String(format: "0x%04X", device.vendorID)))",
        "  Product ID: \(String(format: "0x%04X", device.productID))",
        "  Type: \(device.deviceType)",
        "  USB Speed: \(device.usbSpeed)",
        "  Bus Power: \(device.busPowerMA) mA",
        "  Location ID: \(device.locationID)",
        "  Removable: \(device.isRemovable)",
        "  USB Class: \(device.deviceClass)/\(device.deviceSubclass)/\(device.deviceProtocol)",
    ]

    if !device.serialNumber.isEmpty {
        lines.append("  Serial: \(device.serialNumber)")
    }

    if let port = device.serialPort {
        lines.append("  Serial Port: \(port)")
    }

    if let mp = device.mountPoint {
        lines.append("  Mount Point: \(mp)")
    }

    if let vn = device.volumeName {
        lines.append("  Volume: \(vn)")
    }

    if let fs = device.filesystemType {
        lines.append("  Filesystem: \(fs)")
    }

    if let cap = device.capacityGB {
        lines.append("  Capacity: \(String(format: "%.1f", cap)) GB")
    }

    if let free = device.freeGB {
        lines.append("  Free: \(String(format: "%.1f", free)) GB")
    }

    if let bsd = device.bsdName {
        lines.append("  BSD Name: \(bsd)")
    }

    if let known = DeviceDatabase.identify(vendorID: device.vendorID, productID: device.productID) {
        lines.append("")
        lines.append("  Identified as: \(known.name)")
        lines.append("  Notes: \(known.notes)")
    }

    return lines.joined(separator: "\n")
}

// MARK: - Storage enrichment

func enrichStorageDevices(_ devices: inout [USBDevice], with volumes: [VolumeInfo]) {
    // Only enrich devices that could plausibly be storage
    let storageTypes: Set<String> = ["storage", "unknown"]
    for i in devices.indices where storageTypes.contains(devices[i].deviceType) {
        enrichSingleDevice(&devices[i], with: volumes)
    }
}

func formatSerialPort(_ port: SerialPortBridge.SerialPort, usbDevices: [USBDevice]) -> String {
    var lines = [
        "  \(port.path)",
        "    Type: \(port.deviceType.rawValue)",
    ]

    switch port.type {
    case .usbSerial:
        lines.append("    Port Type: USB-Serial Adapter")
    case .usbModem:
        lines.append("    Port Type: USB Modem (CDC ACM)")
    case .other:
        if port.deviceType == .bluetooth {
            lines.append("    Port Type: Bluetooth")
        } else {
            lines.append("    Port Type: Built-in")
        }
    }

    // Try to match to a USB device
    if let device = SerialPortBridge.matchDevice(port: port, devices: usbDevices) {
        lines.append("    Device: \(device.name)")
        lines.append("    Vendor: \(device.vendorName) (\(String(format: "0x%04X", device.vendorID)))")
        lines.append("    Product ID: \(String(format: "0x%04X", device.productID))")
        lines.append("    Speed: \(device.usbSpeed)")
        lines.append("    Location: \(device.locationID)")

        if let known = DeviceDatabase.identify(vendorID: device.vendorID, productID: device.productID) {
            lines.append("    Identified as: \(known.name)")
        }
    }

    return lines.joined(separator: "\n")
}

func formatTopologyNode(_ node: IOKitBridge.TopologyNode, prefix: String, isLast: Bool, isRoot: Bool, lines: inout [String]) {
    let connector = isLast ? "└── " : "├── "
    let childPrefix = isLast ? "    " : "│   "

    // Build the node label
    var label: String
    let portLabel = node.portNumber > 0 ? "Port \(node.portNumber)" : "Bus"

    if node.isHub {
        label = "\(portLabel): USB Hub [\(node.name)]"
    } else {
        label = "\(portLabel): \(node.name)"
        if node.vendorName != "Unknown" {
            label += " [\(node.vendorName)]"
        }
    }

    // Add speed
    label += " (\(node.speed))"

    // Add power draw
    if node.busPowerMA > 0 {
        label += " \(node.busPowerMA)mA"
    }

    // Add serial port if present
    if let serialPort = node.serialPort {
        label += " → \(serialPort)"
    }

    if isRoot {
        lines.append(label)
    } else {
        lines.append("\(prefix)\(connector)\(label)")
    }

    // Render children
    let nextPrefix = isRoot ? "" : "\(prefix)\(childPrefix)"
    for (index, child) in node.children.enumerated() {
        let isLastChild = index == node.children.count - 1
        formatTopologyNode(child, prefix: nextPrefix, isLast: isLastChild, isRoot: false, lines: &lines)
    }
}

func enrichSingleDevice(_ device: inout USBDevice, with volumes: [VolumeInfo]) {
    // Match volumes to this device by checking if the diskutil device path
    // relates to this USB device. We use volume name matching against the
    // device name as a heuristic.
    for volume in volumes {
        guard let detail = DiskUtilBridge.volumeDetail(bsdName: volume.bsdName) else {
            continue
        }

        // Try to match: volume name in device name, or device name in volume name
        let matched: Bool
        if let volName = detail.volumeName, !volName.isEmpty {
            let devLower = device.name.lowercased()
            let volLower = volName.lowercased()
            matched = devLower.contains(volLower) || volLower.contains(devLower)
        } else {
            matched = false
        }

        if matched && device.mountPoint == nil {
            device.mountPoint = detail.mountPoint
            device.volumeName = detail.volumeName
            device.filesystemType = detail.filesystemType
            device.bsdName = detail.bsdName
            if detail.totalSizeBytes > 0 {
                device.capacityGB = Double(detail.totalSizeBytes) / 1_000_000_000.0
                device.freeGB = Double(detail.freeSizeBytes) / 1_000_000_000.0
                // If we matched storage, update the type
                if device.deviceType == "unknown" {
                    device.deviceType = "storage"
                }
            }
            return // Found a match, done
        }
    }
}

// MARK: - Tag Device Handler

func handleTagDevice(params: CallTool.Parameters) -> CallTool.Result {
    guard let action = params.arguments?["action"]?.stringValue else {
        return .init(content: [.text("Missing required parameter: action")], isError: true)
    }

    switch action.lowercased() {
    case "set":
        guard let identifier = params.arguments?["identifier"]?.stringValue else {
            return .init(content: [.text("Missing required parameter: identifier (needed for 'set')")], isError: true)
        }
        guard let tag = params.arguments?["tag"]?.stringValue else {
            return .init(content: [.text("Missing required parameter: tag (needed for 'set')")], isError: true)
        }
        let (success, message) = TagManager.setTag(identifier: identifier, tag: tag)
        return .init(content: [.text(message)], isError: !success)

    case "get":
        guard let identifier = params.arguments?["identifier"]?.stringValue else {
            return .init(content: [.text("Missing required parameter: identifier (needed for 'get')")], isError: true)
        }
        let (success, message) = TagManager.getTag(identifier: identifier)
        return .init(content: [.text(message)], isError: !success)

    case "list":
        let (_, message) = TagManager.listTags()
        return .init(content: [.text(message)])

    case "remove":
        guard let identifier = params.arguments?["identifier"]?.stringValue else {
            return .init(content: [.text("Missing required parameter: identifier (needed for 'remove')")], isError: true)
        }
        let (success, message) = TagManager.removeTag(identifier: identifier)
        return .init(content: [.text(message)], isError: !success)

    default:
        return .init(content: [.text("Invalid action '\(action)'. Use: set, get, list, or remove")], isError: true)
    }
}

// MARK: - Port Reset Handler

func handlePortReset(params: CallTool.Parameters) -> CallTool.Result {
    guard let identifier = params.arguments?["identifier"]?.stringValue else {
        return .init(content: [.text("Missing required parameter: identifier")], isError: true)
    }

    guard let confirm = params.arguments?["confirm"]?.boolValue else {
        return .init(content: [.text("Missing required parameter: confirm (must be true to proceed)")], isError: true)
    }

    if !confirm {
        return .init(
            content: [.text("Port reset aborted — confirm must be true. This operation can disrupt active USB transfers.")],
            isError: true
        )
    }

    let (success, message) = DeviceControlBridge.resetDevice(identifier: identifier)
    return .init(content: [.text(message)], isError: !success)
}

// MARK: - Power Info Handler

func handlePowerInfo(params: CallTool.Parameters) -> CallTool.Result {
    if let identifier = params.arguments?["identifier"]?.stringValue, !identifier.isEmpty {
        let (success, message) = PowerBridge.powerInfo(identifier: identifier)
        return .init(content: [.text(message)], isError: !success)
    } else {
        let (_, message) = PowerBridge.powerSummaryAll()
        return .init(content: [.text(message)])
    }
}

// MARK: - Monitor Events Handler

func handleMonitorEvents(params: CallTool.Parameters) -> CallTool.Result {
    let clear = params.arguments?["clear"]?.boolValue ?? false

    let events: [EventMonitor.USBEvent]
    if clear {
        events = EventMonitor.shared.clear()
    } else {
        events = EventMonitor.shared.poll()
    }

    if events.isEmpty {
        let msg = clear
            ? "Event log cleared. Current USB state captured as baseline."
            : "No USB events recorded yet. Current state captured as baseline — call again to detect changes."
        return .init(content: [.text(msg)])
    }

    let formatter = DateFormatter()
    formatter.dateFormat = "HH:mm:ss"

    var lines: [String] = ["USB Event Log (\(events.count) event\(events.count == 1 ? "" : "s")):"]
    lines.append("")

    for event in events {
        let ts = formatter.string(from: event.timestamp)
        let arrow = event.eventType == "connected" ? "+" : "-"
        let vid = String(format: "0x%04X", event.vendorID)
        let pid = String(format: "0x%04X", event.productID)
        lines.append("  [\(ts)] \(arrow) \(event.eventType.uppercased()): \(event.deviceName)")
        lines.append("         VID/PID: \(vid)/\(pid)  Location: \(event.locationID)")
        if !event.serialNumber.isEmpty {
            lines.append("         Serial: \(event.serialNumber)")
        }
    }

    return .init(content: [.text(lines.joined(separator: "\n"))])
}

// MARK: - Snapshot State Handler

func handleSnapshotState(params: CallTool.Parameters) -> CallTool.Result {
    guard let action = params.arguments?["action"]?.stringValue else {
        return .init(content: [.text("Missing required parameter: action")], isError: true)
    }

    switch action.lowercased() {
    case "capture":
        let name = params.arguments?["name"]?.stringValue
        let snapshot = SnapshotManager.shared.capture(name: name)
        let output = """
        Snapshot captured:
          Name: \(snapshot.name)
          Timestamp: \(snapshot.timestamp)
          Devices: \(snapshot.devices.count)

        Device list:
        \(snapshot.devices.map { "  - \($0.name) [\($0.vendorName)] (\($0.locationID))" }.joined(separator: "\n"))
        """
        return .init(content: [.text(output)])

    case "list":
        let snapshots = SnapshotManager.shared.list()
        if snapshots.isEmpty {
            return .init(content: [.text("No snapshots saved. Use action: \"capture\" to save one.")])
        }

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"

        var lines = ["Saved snapshots (\(snapshots.count)):"]
        lines.append("")
        for s in snapshots {
            lines.append("  \(s.name)  —  \(formatter.string(from: s.timestamp))  (\(s.deviceCount) devices)")
        }
        return .init(content: [.text(lines.joined(separator: "\n"))])

    case "compare":
        guard let name = params.arguments?["name"]?.stringValue else {
            return .init(content: [.text("Missing required parameter: name (snapshot to compare from)")], isError: true)
        }
        let compareTo = params.arguments?["compare_to"]?.stringValue

        guard let result = SnapshotManager.shared.compare(name: name, compareTo: compareTo) else {
            let target = compareTo ?? name
            return .init(content: [.text("Snapshot '\(target)' not found.")], isError: true)
        }

        var lines = ["Comparison: \(result.fromName) → \(result.toName)"]
        lines.append("")

        if result.added.isEmpty && result.removed.isEmpty && result.changed.isEmpty {
            lines.append("  No differences found.")
        } else {
            if !result.added.isEmpty {
                lines.append("  ADDED (\(result.added.count)):")
                for d in result.added {
                    lines.append("    + \(d.name) [\(d.vendorName)] (\(d.locationID))")
                }
                lines.append("")
            }

            if !result.removed.isEmpty {
                lines.append("  REMOVED (\(result.removed.count)):")
                for d in result.removed {
                    lines.append("    - \(d.name) [\(d.vendorName)] (\(d.locationID))")
                }
                lines.append("")
            }

            if !result.changed.isEmpty {
                lines.append("  CHANGED (\(result.changed.count)):")
                for pair in result.changed {
                    lines.append("    ~ \(pair.old.name) (\(pair.old.locationID))")
                    if pair.old.usbSpeed != pair.new.usbSpeed {
                        lines.append("        Speed: \(pair.old.usbSpeed) → \(pair.new.usbSpeed)")
                    }
                    if pair.old.busPowerMA != pair.new.busPowerMA {
                        lines.append("        Power: \(pair.old.busPowerMA) mA → \(pair.new.busPowerMA) mA")
                    }
                    if pair.old.deviceType != pair.new.deviceType {
                        lines.append("        Type: \(pair.old.deviceType) → \(pair.new.deviceType)")
                    }
                    if pair.old.name != pair.new.name {
                        lines.append("        Name: \(pair.old.name) → \(pair.new.name)")
                    }
                }
            }
        }

        return .init(content: [.text(lines.joined(separator: "\n"))])

    case "delete":
        guard let name = params.arguments?["name"]?.stringValue else {
            return .init(content: [.text("Missing required parameter: name (snapshot to delete)")], isError: true)
        }
        if SnapshotManager.shared.delete(name: name) {
            return .init(content: [.text("Snapshot '\(name)' deleted.")])
        } else {
            return .init(content: [.text("Snapshot '\(name)' not found.")], isError: true)
        }

    default:
        return .init(content: [.text("Invalid action '\(action)'. Use: capture, list, compare, or delete")], isError: true)
    }
}

// MARK: - Diagnose Device Handler

func handleDiagnoseDevice(params: CallTool.Parameters) -> CallTool.Result {
    guard let identifier = params.arguments?["identifier"]?.stringValue else {
        return .init(content: [.text("Missing required parameter: identifier")], isError: true)
    }

    let timeframe = params.arguments?["timeframe"]?.stringValue ?? "1h"

    // Validate timeframe
    let validTimeframes = ["1h", "6h", "24h"]
    guard validTimeframes.contains(timeframe) else {
        return .init(
            content: [.text("Invalid timeframe '\(timeframe)'. Use: 1h, 6h, or 24h")],
            isError: true
        )
    }

    let result = DiagnosticsBridge.diagnose(identifier: identifier, timeframe: timeframe)

    var lines = ["USB Diagnostics for: \(result.identifier)"]
    lines.append("Timeframe: last \(result.timeframe)")
    lines.append("")

    if result.errorCount == 0 && result.logEntries.isEmpty {
        lines.append("No USB errors found for this device in the last \(result.timeframe).")
    } else {
        lines.append("Errors found: \(result.errorCount)")

        if !result.errorTypes.isEmpty {
            lines.append("")
            lines.append("Error breakdown:")
            for (errorType, count) in result.errorTypes.sorted(by: { $0.value > $1.value }) {
                lines.append("  \(errorType): \(count)")
            }
        }

        if let lastTs = result.lastErrorTimestamp {
            lines.append("")
            lines.append("Last error: \(lastTs)")
        }

        if !result.logEntries.isEmpty {
            lines.append("")
            lines.append("Recent log entries (\(result.logEntries.count)):")
            for entry in result.logEntries {
                lines.append("  \(entry)")
            }
        }
    }

    return .init(content: [.text(lines.joined(separator: "\n"))])
}

// MARK: - Device Descriptors Handler

func handleDeviceDescriptors(params: CallTool.Parameters) -> CallTool.Result {
    guard let identifier = params.arguments?["identifier"]?.stringValue else {
        return .init(content: [.text("Missing required parameter: identifier")], isError: true)
    }

    guard let desc = DescriptorBridge.readDescriptors(identifier: identifier) else {
        return .init(content: [.text("No device found matching '\(identifier)'")], isError: true)
    }

    var lines: [String] = []

    // Device Descriptor
    lines.append("USB Device Descriptor")
    lines.append("=====================")
    lines.append("  Device: \(desc.deviceName)")
    lines.append("  bcdUSB: \(desc.bcdUSB)")
    lines.append("  bDeviceClass: \(desc.bDeviceClass) (\(descriptorDeviceClassName(desc.bDeviceClass)))")
    lines.append("  bDeviceSubClass: \(desc.bDeviceSubClass)")
    lines.append("  bDeviceProtocol: \(desc.bDeviceProtocol)")
    lines.append("  bMaxPacketSize0: \(desc.bMaxPacketSize0)")
    lines.append("  idVendor: \(String(format: "0x%04X", desc.vendorID))")
    lines.append("  idProduct: \(String(format: "0x%04X", desc.productID))")
    lines.append("  bcdDevice: \(desc.bcdDevice)")
    lines.append("  iManufacturer: \(desc.iManufacturer)")
    lines.append("  iProduct: \(desc.iProduct)")
    lines.append("  iSerialNumber: \(desc.iSerialNumber)")
    lines.append("  bNumConfigurations: \(desc.bNumConfigurations)")

    // Configuration Descriptors
    for (configIdx, config) in desc.configurations.enumerated() {
        lines.append("")
        lines.append("  Configuration \(configIdx + 1)")
        lines.append("  ─────────────────")
        lines.append("    bConfigurationValue: \(config.bConfigurationValue)")
        lines.append("    bmAttributes: \(String(format: "0x%02X", config.bmAttributes)) (\(descriptorAttributesDescription(config.bmAttributes)))")
        lines.append("    bMaxPower: \(config.bMaxPower) mA")
        lines.append("    bNumInterfaces: \(config.bNumInterfaces)")

        // Interface Descriptors
        for iface in config.interfaces {
            lines.append("")
            lines.append("    Interface \(iface.bInterfaceNumber) (Alt \(iface.bAlternateSetting))")
            lines.append("    ───────────────────")
            lines.append("      bInterfaceClass: \(iface.bInterfaceClass) (\(iface.className))")
            lines.append("      bInterfaceSubClass: \(iface.bInterfaceSubClass)")
            lines.append("      bInterfaceProtocol: \(iface.bInterfaceProtocol)")
            if !iface.iInterface.isEmpty {
                lines.append("      iInterface: \(iface.iInterface)")
            }
            lines.append("      bNumEndpoints: \(iface.bNumEndpoints)")

            // Endpoint Descriptors
            for ep in iface.endpoints {
                let addrHex = String(format: "0x%02X", ep.bEndpointAddress)
                lines.append("")
                lines.append("      Endpoint \(addrHex) (\(ep.direction))")
                lines.append("        Transfer Type: \(ep.transferType)")
                lines.append("        wMaxPacketSize: \(ep.wMaxPacketSize)")
                lines.append("        bInterval: \(ep.bInterval)")
            }
        }
    }

    return .init(content: [.text(lines.joined(separator: "\n"))])
}

func descriptorDeviceClassName(_ classCode: Int) -> String {
    switch classCode {
    case 0x00: return "Defined at Interface Level"
    case 0x02: return "Communications"
    case 0x09: return "Hub"
    case 0xEF: return "Miscellaneous"
    case 0xFF: return "Vendor Specific"
    default: return String(format: "0x%02X", classCode)
    }
}

func descriptorAttributesDescription(_ attrs: Int) -> String {
    var parts: [String] = []
    if attrs & 0x40 != 0 { parts.append("Self-Powered") }
    if attrs & 0x20 != 0 { parts.append("Remote Wakeup") }
    if parts.isEmpty { parts.append("Bus-Powered") }
    return parts.joined(separator: ", ")
}

// MARK: - Flash Firmware Handler

func handleFlashFirmware(params: CallTool.Parameters) -> CallTool.Result {
    guard let identifier = params.arguments?["identifier"]?.stringValue else {
        return .init(content: [.text("Missing required parameter: identifier")], isError: true)
    }

    guard let firmwarePath = params.arguments?["firmware_path"]?.stringValue else {
        return .init(content: [.text("Missing required parameter: firmware_path")], isError: true)
    }

    guard let confirm = params.arguments?["confirm"]?.boolValue else {
        return .init(content: [.text("Missing required parameter: confirm (must be true — flashing is destructive)")], isError: true)
    }

    if !confirm {
        return .init(
            content: [.text("Flash aborted — confirm must be true. Flashing overwrites the device's firmware and is destructive.")],
            isError: true
        )
    }

    // Validate firmware file
    let validation = FirmwareBridge.validateFirmware(path: firmwarePath)
    if !validation.valid {
        return .init(content: [.text(validation.message)], isError: true)
    }

    // Find the device
    let device = IOKitBridge.findDevice(identifier: identifier)

    // Determine the flashing tool
    let flashTool: FirmwareBridge.FlashTool
    if let toolOverride = params.arguments?["tool"]?.stringValue {
        switch toolOverride.lowercased() {
        case "esptool":
            flashTool = .esptool
        case "dfu-util", "dfuutil", "dfu_util":
            flashTool = .dfuUtil
        case "avrdude":
            flashTool = .avrdude
        case "uf2":
            flashTool = .uf2
        default:
            return .init(
                content: [.text("Unknown tool '\(toolOverride)'. Use: esptool, dfu-util, avrdude, or uf2")],
                isError: true
            )
        }
    } else {
        guard let detected = FirmwareBridge.detectTool(device: device, firmwarePath: firmwarePath) else {
            return .init(
                content: [.text("Could not auto-detect flashing tool for this device/firmware combination. Use the 'tool' parameter to specify: esptool, dfu-util, avrdude, or uf2")],
                isError: true
            )
        }
        flashTool = detected
    }

    // Check tool is installed
    let (installed, toolPath) = FirmwareBridge.isToolInstalled(flashTool)
    if !installed {
        return .init(
            content: [.text("\(flashTool.rawValue) is not installed. Install it first:\n" + installHint(for: flashTool))],
            isError: true
        )
    }

    // Determine serial port
    let port: String?
    if let portOverride = params.arguments?["port"]?.stringValue {
        port = portOverride
    } else if let device = device {
        // Try to find the serial port for this device
        var enriched = [device]
        SerialPortBridge.enrichDevices(&enriched)
        port = enriched[0].serialPort
    } else {
        port = nil
    }

    let baud: Int?
    if let baudValue = params.arguments?["baud"]?.intValue {
        baud = baudValue
    } else {
        baud = nil
    }

    // Show the command that will be run
    let previewCommand: String
    if flashTool == .uf2 {
        let volumePath = FirmwareBridge.findUF2Volume() ?? "/Volumes/<UF2_VOLUME>"
        let fileName = (firmwarePath as NSString).lastPathComponent
        previewCommand = "cp \(firmwarePath) \(volumePath)/\(fileName)"
    } else {
        previewCommand = FirmwareBridge.buildCommand(
            tool: flashTool,
            toolPath: toolPath,
            firmwarePath: firmwarePath,
            port: port,
            baud: baud
        ) ?? "(unknown)"
    }

    // Execute the flash
    let result = FirmwareBridge.flash(
        tool: flashTool,
        toolPath: toolPath,
        firmwarePath: firmwarePath,
        port: port,
        baud: baud
    )

    let deviceName = device?.name ?? identifier
    var output = """
    Flash Firmware — \(deviceName)
      Tool: \(flashTool.rawValue)
      Firmware: \(firmwarePath)
      Command: \(previewCommand)
      Status: \(result.success ? "SUCCESS" : "FAILED")
      Message: \(result.message)
    """

    if !result.output.isEmpty {
        output += "\n\n  Output:\n\(result.output.split(separator: "\n").map { "    \($0)" }.joined(separator: "\n"))"
    }

    return .init(content: [.text(output)], isError: !result.success)
}

private func installHint(for tool: FirmwareBridge.FlashTool) -> String {
    switch tool {
    case .esptool:
        return "  pip install esptool\n  or: brew install esptool"
    case .dfuUtil:
        return "  brew install dfu-util"
    case .avrdude:
        return "  brew install avrdude"
    case .uf2:
        return "  (no tool needed — UF2 uses file copy)"
    }
}

// MARK: - Chip Detect Handler

func handleChipDetect(params: CallTool.Parameters) -> CallTool.Result {
    guard let identifier = params.arguments?["identifier"]?.stringValue else {
        return .init(content: [.text("Missing required parameter: identifier")], isError: true)
    }

    // Check esptool is installed
    let (installed, toolPath) = FirmwareBridge.isToolInstalled(.esptool)
    if !installed {
        return .init(
            content: [.text("esptool is not installed. Install it first:\n  pip install esptool\n  or: brew install esptool")],
            isError: true
        )
    }

    // Find the device
    let device = IOKitBridge.findDevice(identifier: identifier)

    // Determine serial port
    let port: String
    if let portOverride = params.arguments?["port"]?.stringValue {
        port = portOverride
    } else if let dev = device {
        var enriched = [dev]
        SerialPortBridge.enrichDevices(&enriched)
        if let serialPort = enriched[0].serialPort {
            port = serialPort
        } else {
            return .init(
                content: [.text("No serial port found for device '\(identifier)'. Connect via USB or specify a port manually.")],
                isError: true
            )
        }
    } else {
        return .init(
            content: [.text("No device found matching '\(identifier)'. Connect the device or specify a serial port.")],
            isError: true
        )
    }

    // Prefer 'esptool' over deprecated 'esptool.py', and 'chip-id' over deprecated 'chip_id'
    let executable = toolPath ?? "esptool"
    let command = "\(executable) --port \(port) chip-id"

    // Execute
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/bin/sh")
    process.arguments = ["-c", command]

    let stdout = Pipe()
    let stderr = Pipe()
    process.standardOutput = stdout
    process.standardError = stderr

    do {
        try process.run()
        process.waitUntilExit()
    } catch {
        return .init(
            content: [.text("Failed to execute esptool: \(error.localizedDescription)")],
            isError: true
        )
    }

    let outData = stdout.fileHandleForReading.readDataToEndOfFile()
    let errData = stderr.fileHandleForReading.readDataToEndOfFile()
    let outStr = String(data: outData, encoding: .utf8) ?? ""
    let errStr = String(data: errData, encoding: .utf8) ?? ""
    let combined = [outStr, errStr].filter { !$0.isEmpty }.joined(separator: "\n")

    let success = process.terminationStatus == 0

    let deviceName = device?.name ?? identifier
    var output = """
    Chip Detect — \(deviceName)
      Port: \(port)
      Command: \(command)
      Status: \(success ? "SUCCESS" : "FAILED")
    """

    if !combined.isEmpty {
        // Parse key fields from esptool output
        var chip = ""
        var features = ""
        var crystal = ""
        var mac = ""

        for line in combined.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("Chip is ") {
                chip = String(trimmed.dropFirst(8))
            } else if trimmed.hasPrefix("Features:") {
                features = String(trimmed.dropFirst(10))
            } else if trimmed.hasPrefix("Crystal is") {
                crystal = String(trimmed.dropFirst(11))
            } else if trimmed.hasPrefix("MAC:") {
                mac = String(trimmed.dropFirst(5))
            }
        }

        if !chip.isEmpty {
            output += "\n\n  Chip: \(chip)"
            if !features.isEmpty { output += "\n  Features: \(features)" }
            if !crystal.isEmpty { output += "\n  Crystal: \(crystal)" }
            if !mac.isEmpty { output += "\n  MAC: \(mac)" }
        }

        output += "\n\n  Raw Output:\n\(combined.split(separator: "\n").map { "    \($0)" }.joined(separator: "\n"))"
    }

    return .init(content: [.text(output)], isError: !success)
}

// MARK: - HID Send Handler

func handleHIDSend(params: CallTool.Parameters) -> CallTool.Result {
    guard let identifier = params.arguments?["identifier"]?.stringValue else {
        return .init(content: [.text("Missing required parameter: identifier")], isError: true)
    }

    guard let action = params.arguments?["action"]?.stringValue else {
        return .init(content: [.text("Missing required parameter: action (send_report, get_report, or list_reports)")], isError: true)
    }

    // Find the device
    guard let device = IOKitBridge.findDevice(identifier: identifier) else {
        return .init(content: [.text("No device found matching '\(identifier)'")], isError: true)
    }

    // Validate device is a HID device
    if !HIDBridge.isHIDDevice(device) {
        return .init(
            content: [.text("'\(device.name)' (class \(device.deviceClass)/\(device.deviceSubclass)) does not appear to be a HID device.")],
            isError: true
        )
    }

    let reportID = params.arguments?["report_id"]?.intValue ?? 0

    switch action.lowercased() {
    case "send_report":
        // Require confirmation for sending
        guard let confirm = params.arguments?["confirm"]?.boolValue, confirm else {
            return .init(
                content: [.text("send_report requires confirm=true — sending data to a device is potentially destructive.")],
                isError: true
            )
        }

        guard let dataStr = params.arguments?["data"]?.stringValue else {
            return .init(content: [.text("Missing required parameter: data (hex string of bytes to send)")], isError: true)
        }

        guard let bytes = HIDBridge.parseHexData(dataStr) else {
            return .init(
                content: [.text("Invalid hex data '\(dataStr)'. Use format like '0x01 0xFF 0x00' or '01ff00'")],
                isError: true
            )
        }

        let reportTypeStr = params.arguments?["report_type"]?.stringValue ?? "output"
        guard let reportType = parseReportType(reportTypeStr) else {
            return .init(content: [.text("Invalid report_type '\(reportTypeStr)'. Use: output or feature")], isError: true)
        }

        let result = HIDBridge.sendReport(
            vendorID: device.vendorID,
            productID: device.productID,
            reportType: reportType,
            reportID: reportID,
            data: bytes
        )

        let output = """
        HID Send Report — \(device.name)
          Vendor: \(String(format: "0x%04X", device.vendorID))
          Product: \(String(format: "0x%04X", device.productID))
          Report Type: \(reportTypeStr)
          Report ID: \(reportID)
          Data Sent: \(result.data ?? dataStr)
          Status: \(result.success ? "SUCCESS" : "FAILED")
          Message: \(result.message)
        """
        return .init(content: [.text(output)], isError: !result.success)

    case "get_report":
        let reportTypeStr = params.arguments?["report_type"]?.stringValue ?? "feature"
        guard let reportType = parseReportType(reportTypeStr) else {
            return .init(content: [.text("Invalid report_type '\(reportTypeStr)'. Use: output or feature")], isError: true)
        }

        let result = HIDBridge.getReport(
            vendorID: device.vendorID,
            productID: device.productID,
            reportType: reportType,
            reportID: reportID
        )

        var output = """
        HID Get Report — \(device.name)
          Vendor: \(String(format: "0x%04X", device.vendorID))
          Product: \(String(format: "0x%04X", device.productID))
          Report Type: \(reportTypeStr)
          Report ID: \(reportID)
          Status: \(result.success ? "SUCCESS" : "FAILED")
          Message: \(result.message)
        """

        if let data = result.data {
            output += "\n  Data: \(data)"
        }

        return .init(content: [.text(output)], isError: !result.success)

    case "list_reports":
        let (success, summary, reports) = HIDBridge.listReports(
            vendorID: device.vendorID,
            productID: device.productID
        )

        if !success {
            return .init(content: [.text(summary)], isError: true)
        }

        var output = summary

        if !reports.isEmpty {
            output += "\n\n  Available Reports:"
            for report in reports {
                output += "\n    - \(report.reportType) (id=\(report.reportID), max \(report.reportSize) bytes)"
            }
        } else {
            output += "\n\n  No standard report descriptors found via IOKit properties."
        }

        return .init(content: [.text(output)])

    default:
        return .init(
            content: [.text("Invalid action '\(action)'. Use: send_report, get_report, or list_reports")],
            isError: true
        )
    }
}

private func parseReportType(_ str: String) -> HIDBridge.ReportType? {
    switch str.lowercased() {
    case "output": return .output
    case "feature": return .feature
    default: return nil
    }
}

// MARK: - Serial Communication Handlers

func handleSerialOpen(params: CallTool.Parameters) -> CallTool.Result {
    guard let port = params.arguments?["port"]?.stringValue else {
        return .init(content: [.text("Missing required parameter: port")], isError: true)
    }

    let baudRate = params.arguments?["baud_rate"]?.intValue ?? 115200
    let dataBits = params.arguments?["data_bits"]?.intValue ?? 8
    let stopBits = params.arguments?["stop_bits"]?.intValue ?? 1
    let parity = params.arguments?["parity"]?.stringValue ?? "none"

    // Validate port path
    guard port.hasPrefix("/dev/cu.") else {
        return .init(
            content: [.text("Invalid port path '\(port)'. macOS serial ports are at /dev/cu.* (e.g. /dev/cu.usbserial-2120)")],
            isError: true
        )
    }

    let (success, message) = SerialCommBridge.shared.open(
        path: port,
        baudRate: baudRate,
        dataBits: dataBits,
        stopBits: stopBits,
        parity: parity
    )
    return .init(content: [.text(message)], isError: !success)
}

func handleSerialRead(params: CallTool.Parameters) -> CallTool.Result {
    guard let port = params.arguments?["port"]?.stringValue else {
        return .init(content: [.text("Missing required parameter: port")], isError: true)
    }

    let timeout = params.arguments?["timeout"]?.doubleValue ?? 1.0
    let clampedTimeout = min(max(timeout, 0.1), 30.0)

    let (success, message) = SerialCommBridge.shared.read(path: port, timeoutSeconds: clampedTimeout)
    return .init(content: [.text(message)], isError: !success)
}

func handleSerialWrite(params: CallTool.Parameters) -> CallTool.Result {
    guard let port = params.arguments?["port"]?.stringValue else {
        return .init(content: [.text("Missing required parameter: port")], isError: true)
    }

    guard let data = params.arguments?["data"]?.stringValue else {
        return .init(content: [.text("Missing required parameter: data")], isError: true)
    }

    let (success, message) = SerialCommBridge.shared.write(path: port, data: data)
    return .init(content: [.text(message)], isError: !success)
}

func handleSerialClose(params: CallTool.Parameters) -> CallTool.Result {
    guard let port = params.arguments?["port"]?.stringValue else {
        return .init(content: [.text("Missing required parameter: port")], isError: true)
    }

    let (success, message) = SerialCommBridge.shared.close(path: port)
    return .init(content: [.text(message)], isError: !success)
}

func handleSerialMonitor(params: CallTool.Parameters) -> CallTool.Result {
    guard let port = params.arguments?["port"]?.stringValue else {
        return .init(content: [.text("Missing required parameter: port")], isError: true)
    }

    let seconds = params.arguments?["seconds"]?.doubleValue ?? 5.0
    let clampedSeconds = min(max(seconds, 0.5), 30.0)
    let autoOpen = params.arguments?["auto_open"]?.boolValue ?? false
    let baudRate = params.arguments?["baud_rate"]?.intValue ?? 115200

    // Validate port path
    guard port.hasPrefix("/dev/cu.") else {
        return .init(
            content: [.text("Invalid port path '\(port)'. macOS serial ports are at /dev/cu.* (e.g. /dev/cu.usbserial-2120)")],
            isError: true
        )
    }

    let (success, message) = SerialCommBridge.shared.monitor(
        path: port,
        seconds: clampedSeconds,
        autoOpen: autoOpen,
        baudRate: baudRate
    )
    return .init(content: [.text(message)], isError: !success)
}
