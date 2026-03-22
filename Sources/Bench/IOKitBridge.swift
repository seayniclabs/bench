import Foundation
import IOKit
import IOKit.usb

/// Represents a USB device discovered via IOKit
struct USBDevice: Sendable {
    let name: String
    let vendorID: Int
    let productID: Int
    let vendorName: String
    let serialNumber: String
    var deviceType: String
    let usbSpeed: String
    let busPowerMA: Int
    let locationID: String
    let isRemovable: Bool
    let deviceClass: Int
    let deviceSubclass: Int
    let deviceProtocol: Int

    // Serial port (populated by serial port scan)
    var serialPort: String?

    // Storage-specific (populated by DiskUtilBridge)
    var mountPoint: String?
    var capacityGB: Double?
    var freeGB: Double?
    var volumeName: String?
    var filesystemType: String?
    var bsdName: String?
}

/// Bridge to IOKit for USB device enumeration
enum IOKitBridge {

    /// Check if IOKit USB enumeration is available
    static var isAvailable: Bool {
        let matching = IOServiceMatching(kIOUSBDeviceClassName)
        var iterator: io_iterator_t = 0
        let result = IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator)
        if result == KERN_SUCCESS {
            IOObjectRelease(iterator)
            return true
        }
        return false
    }

    /// Enumerate all connected USB devices
    static func enumerateDevices(includeInternal: Bool = false) -> [USBDevice] {
        let matching = IOServiceMatching(kIOUSBDeviceClassName)
        var iterator: io_iterator_t = 0
        let result = IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator)

        guard result == KERN_SUCCESS else {
            return []
        }
        defer { IOObjectRelease(iterator) }

        var devices: [USBDevice] = []

        var service = IOIteratorNext(iterator)
        while service != 0 {
            defer {
                IOObjectRelease(service)
                service = IOIteratorNext(iterator)
            }

            let vendorID = getIntProperty(service, kUSBVendorID) ?? 0
            let productID = getIntProperty(service, kUSBProductID) ?? 0

            // Skip internal Apple devices unless requested
            if !includeInternal && vendorID == 0x05AC {
                continue
            }

            // Skip root hubs (vendor 0, product 0)
            if vendorID == 0 && productID == 0 {
                continue
            }

            let name = getStringProperty(service, kUSBProductString)
                ?? getStringProperty(service, "USB Product Name")
                ?? "Unknown Device"
            let vendorName = getStringProperty(service, kUSBVendorString)
                ?? DeviceDatabase.vendorName(for: vendorID)
                ?? "Unknown"
            let serial = getStringProperty(service, kUSBSerialNumberString) ?? ""
            let locationID = getIntProperty(service, kUSBDevicePropertyLocationID) ?? 0
            let deviceClass = getIntProperty(service, kUSBDeviceClass) ?? 0
            let deviceSubclass = getIntProperty(service, kUSBDeviceSubClass) ?? 0
            let deviceProtocol = getIntProperty(service, kUSBDeviceProtocol) ?? 0
            let speed = getIntProperty(service, "Device Speed") ?? 0
            let busPower = getIntProperty(service, "Bus Power Available") ?? 0
            let isRemovable = getBoolProperty(service, "Removable") ?? true

            let deviceType = classifyDevice(
                deviceClass: deviceClass,
                deviceSubclass: deviceSubclass,
                vendorID: vendorID,
                productID: productID
            )

            let device = USBDevice(
                name: name,
                vendorID: vendorID,
                productID: productID,
                vendorName: vendorName,
                serialNumber: serial,
                deviceType: deviceType,
                usbSpeed: speedString(speed),
                busPowerMA: busPower * 2, // IOKit reports in 2mA units
                locationID: String(format: "0x%08X", locationID),
                isRemovable: isRemovable,
                deviceClass: deviceClass,
                deviceSubclass: deviceSubclass,
                deviceProtocol: deviceProtocol
            )

            devices.append(device)
        }

        return devices
    }

    /// Find a single device by identifier (serial, location ID, or name)
    static func findDevice(identifier: String, includeInternal: Bool = true) -> USBDevice? {
        let devices = enumerateDevices(includeInternal: includeInternal)
        let id = identifier.lowercased()

        // Match by serial number
        if let device = devices.first(where: { $0.serialNumber.lowercased() == id }) {
            return device
        }

        // Match by location ID
        if let device = devices.first(where: { $0.locationID.lowercased() == id }) {
            return device
        }

        // Match by name (case-insensitive contains)
        if let device = devices.first(where: { $0.name.lowercased().contains(id) }) {
            return device
        }

        return nil
    }

    // MARK: - Hub Topology

    /// Represents a node in the USB hub topology tree
    struct TopologyNode: Sendable {
        let name: String
        let vendorID: Int
        let productID: Int
        let vendorName: String
        let speed: String
        let busPowerMA: Int
        let locationID: Int
        let portNumber: Int
        let isHub: Bool
        let deviceClass: Int
        let serialPort: String?     // Populated if this device has a serial port
        var children: [TopologyNode]
    }

    /// Enumerate the USB hub topology as a tree structure
    static func enumerateHubTopology(includeInternal: Bool = false) -> [TopologyNode] {
        // Step 1: Enumerate all USB devices AND hubs, collecting parent info
        let matching = IOServiceMatching(kIOUSBDeviceClassName)
        var iterator: io_iterator_t = 0
        let result = IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator)

        guard result == KERN_SUCCESS else { return [] }
        defer { IOObjectRelease(iterator) }

        // Collect all nodes with their raw location IDs for parent matching
        struct RawNode {
            let node: TopologyNode
            let rawLocationID: Int
        }

        var allNodes: [RawNode] = []
        var service = IOIteratorNext(iterator)

        while service != 0 {
            defer {
                IOObjectRelease(service)
                service = IOIteratorNext(iterator)
            }

            let vendorID = getIntProperty(service, kUSBVendorID) ?? 0
            let productID = getIntProperty(service, kUSBProductID) ?? 0
            let deviceClass = getIntProperty(service, kUSBDeviceClass) ?? 0
            let locationID = getIntProperty(service, kUSBDevicePropertyLocationID) ?? 0
            let speed = getIntProperty(service, "Device Speed") ?? 0
            let busPower = getIntProperty(service, "Bus Power Available") ?? 0
            let portNumber = getIntProperty(service, "PortNum") ?? 0

            // Skip root hubs (vendor 0, product 0 and location 0)
            if vendorID == 0 && productID == 0 { continue }

            // Skip internal Apple devices unless requested
            if !includeInternal && vendorID == 0x05AC { continue }

            let name = getStringProperty(service, kUSBProductString)
                ?? getStringProperty(service, "USB Product Name")
                ?? "Unknown Device"
            let vendorName = getStringProperty(service, kUSBVendorString)
                ?? DeviceDatabase.vendorName(for: vendorID)
                ?? "Unknown"

            let isHub = deviceClass == 0x09

            let node = TopologyNode(
                name: name,
                vendorID: vendorID,
                productID: productID,
                vendorName: vendorName,
                speed: speedString(speed),
                busPowerMA: busPower * 2,
                locationID: locationID,
                portNumber: portNumber,
                isHub: isHub,
                deviceClass: deviceClass,
                serialPort: nil,
                children: []
            )

            allNodes.append(RawNode(node: node, rawLocationID: locationID))
        }

        // Step 2: Enrich with serial port info
        let serialPorts = SerialPortBridge.discoverPorts()
        for i in allNodes.indices {
            let locHex = String(format: "0x%08X", allNodes[i].rawLocationID)
            for port in serialPorts {
                guard let hint = port.locationHint else { continue }
                var hex = locHex.lowercased()
                if hex.hasPrefix("0x") { hex = String(hex.dropFirst(2)) }
                if hex.contains(hint.lowercased()) {
                    allNodes[i] = RawNode(
                        node: TopologyNode(
                            name: allNodes[i].node.name,
                            vendorID: allNodes[i].node.vendorID,
                            productID: allNodes[i].node.productID,
                            vendorName: allNodes[i].node.vendorName,
                            speed: allNodes[i].node.speed,
                            busPowerMA: allNodes[i].node.busPowerMA,
                            locationID: allNodes[i].node.locationID,
                            portNumber: allNodes[i].node.portNumber,
                            isHub: allNodes[i].node.isHub,
                            deviceClass: allNodes[i].node.deviceClass,
                            serialPort: port.path,
                            children: []
                        ),
                        rawLocationID: allNodes[i].rawLocationID
                    )
                    break
                }
            }
        }

        // Step 3: Build tree using location ID hierarchy
        // macOS USB location IDs encode the topology:
        // Bits 31-24: Bus number
        // Bits 23-20: Port of first hub
        // Bits 19-16: Port of second hub
        // etc. — each nibble is a port number in the chain
        // A device's parent is found by zeroing out its last non-zero nibble

        // Separate hubs from leaf devices
        var hubMap: [Int: TopologyNode] = [:]
        var leafNodes: [RawNode] = []

        for raw in allNodes {
            if raw.node.isHub {
                hubMap[raw.rawLocationID] = raw.node
            } else {
                leafNodes.append(raw)
            }
        }

        // Assign leaf devices to their parent hub
        for raw in leafNodes {
            let parentLoc = parentLocationID(raw.rawLocationID)
            if hubMap[parentLoc] != nil {
                hubMap[parentLoc]!.children.append(raw.node)
            } else {
                // No parent hub found — treat as root-level device
                hubMap[raw.rawLocationID] = raw.node
            }
        }

        // Nest child hubs under parent hubs
        let hubLocationIDs = Array(hubMap.keys).sorted()
        var rootNodes: [TopologyNode] = []

        // Sort by depth (number of non-zero nibbles) so we process children before parents
        let sortedByDepth = hubLocationIDs.sorted { a, b in
            nibbleDepth(a) > nibbleDepth(b)
        }

        var consumed: Set<Int> = []

        for locID in sortedByDepth {
            if consumed.contains(locID) { continue }
            let parentLoc = parentLocationID(locID)
            if parentLoc != locID && hubMap[parentLoc] != nil {
                hubMap[parentLoc]!.children.append(hubMap[locID]!)
                consumed.insert(locID)
            }
        }

        // Remaining unconsumed hubs are root-level
        for locID in hubLocationIDs {
            if !consumed.contains(locID) {
                if let node = hubMap[locID] {
                    rootNodes.append(node)
                }
            }
        }

        // Sort children by port number
        func sortChildren(_ node: inout TopologyNode) {
            node.children.sort { $0.portNumber < $1.portNumber }
            for i in node.children.indices {
                sortChildren(&node.children[i])
            }
        }
        for i in rootNodes.indices {
            sortChildren(&rootNodes[i])
        }

        return rootNodes.sorted { $0.locationID < $1.locationID }
    }

    /// Get the parent location ID by zeroing out the last non-zero nibble (bits 23-0)
    private static func parentLocationID(_ locationID: Int) -> Int {
        // Bits 31-24 are bus number, bits 23-0 encode the port chain in nibbles
        let busNumber = locationID & 0xFF000000
        var portBits = locationID & 0x00FFFFFF

        // Find the last non-zero nibble in the port chain and zero it
        // Nibbles from bit 23 down to bit 0: positions 5,4,3,2,1,0
        for shift in stride(from: 0, through: 20, by: 4) {
            let nibble = (portBits >> shift) & 0xF
            if nibble != 0 {
                portBits &= ~(0xF << shift)
                break
            }
        }

        return busNumber | portBits
    }

    /// Count the number of non-zero nibbles in the port chain (bits 23-0)
    private static func nibbleDepth(_ locationID: Int) -> Int {
        let portBits = locationID & 0x00FFFFFF
        var count = 0
        for shift in stride(from: 0, through: 20, by: 4) {
            if (portBits >> shift) & 0xF != 0 {
                count += 1
            }
        }
        return count
    }

    // MARK: - Private helpers

    private static func getStringProperty(_ service: io_service_t, _ key: String) -> String? {
        guard let value = IORegistryEntryCreateCFProperty(
            service, key as CFString, kCFAllocatorDefault, 0
        )?.takeRetainedValue() else {
            return nil
        }
        return value as? String
    }

    private static func getIntProperty(_ service: io_service_t, _ key: String) -> Int? {
        guard let value = IORegistryEntryCreateCFProperty(
            service, key as CFString, kCFAllocatorDefault, 0
        )?.takeRetainedValue() else {
            return nil
        }
        return value as? Int
    }

    private static func getBoolProperty(_ service: io_service_t, _ key: String) -> Bool? {
        guard let value = IORegistryEntryCreateCFProperty(
            service, key as CFString, kCFAllocatorDefault, 0
        )?.takeRetainedValue() else {
            return nil
        }
        return value as? Bool
    }

    private static func speedString(_ speed: Int) -> String {
        switch speed {
        case 0: return "USB 1.0 (1.5 Mbps)"
        case 1: return "USB 1.1 (12 Mbps)"
        case 2: return "USB 2.0 (480 Mbps)"
        case 3: return "USB 3.0 (5 Gbps)"
        case 4: return "USB 3.1 (10 Gbps)"
        case 5: return "USB 3.2 (20 Gbps)"
        default: return "Unknown"
        }
    }

    /// Classify device type from USB class codes and known device database
    private static func classifyDevice(
        deviceClass: Int,
        deviceSubclass: Int,
        vendorID: Int,
        productID: Int
    ) -> String {
        // Check known device database first
        if let known = DeviceDatabase.identify(vendorID: vendorID, productID: productID) {
            return known.category
        }

        // Fall back to USB class codes
        // See: https://www.usb.org/defined-class-codes
        switch deviceClass {
        case 0x01: return "audio"
        case 0x02: return "serial"         // CDC — serial/modem
        case 0x03: return "input"          // HID
        case 0x06: return "imaging"        // Still Image
        case 0x07: return "printer"
        case 0x08: return "storage"        // Mass Storage
        case 0x09: return "hub"
        case 0x0A: return "serial"         // CDC-Data
        case 0x0E: return "video"
        case 0x10: return "audio"          // Audio/Video
        case 0x11: return "video"           // USB Type-C Bridge (AV adapters)
        case 0xE0: return "wireless"       // Wireless controller (BT, etc.)
        case 0xEF:                         // Miscellaneous — check subclass
            if deviceSubclass == 0x02 { return "serial" } // IAD, common for CDC ACM
            return "miscellaneous"
        case 0x00, 0xFF:                   // Defined at interface level or vendor-specific
            // Check if it's a known serial adapter vendor
            if [0x1A86, 0x10C4, 0x0403, 0x067B].contains(vendorID) {
                return "serial_adapter"
            }
            // Check if it's a known microcontroller vendor
            if [0x2341, 0x2E8A, 0x239A, 0x1B4F, 0x16C0, 0x0483, 0x303A].contains(vendorID) {
                return "microcontroller"
            }
            // Check if it's a known storage vendor
            if [0x0781, 0x0951, 0x090C, 0x058F, 0x13FE, 0x0BDA, 0x04E8, 0x1058].contains(vendorID) {
                // 0x0781=SanDisk, 0x0951=Kingston, 0x090C=Silicon Motion,
                // 0x058F=Alcor Micro, 0x13FE=Kingston/Phison, 0x0BDA=Realtek/Raycue,
                // 0x04E8=Samsung, 0x1058=Western Digital
                return "storage"
            }
            // Check if it's a known HID/input vendor pattern
            if [0x1EA7, 0x046D, 0x045E, 0x04F2, 0x258A, 0x3151].contains(vendorID) {
                // 0x1EA7=2.4G wireless peripherals, 0x046D=Logitech,
                // 0x045E=Microsoft, 0x04F2=Chicony, 0x258A=SINO WEALTH,
                // 0x3151=common wireless keyboard/mouse dongles
                return "input"
            }
            // Check if it's a known video/display adapter
            if [0x343C, 0x0835, 0x17E9, 0x0711].contains(vendorID) {
                // 0x343C=Apple AV adapters, 0x0835=Action Star,
                // 0x17E9=DisplayLink, 0x0711=Magic Control
                return "video"
            }
            return "unknown"
        default: return "unknown"
        }
    }
}
