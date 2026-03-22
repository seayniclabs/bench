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
