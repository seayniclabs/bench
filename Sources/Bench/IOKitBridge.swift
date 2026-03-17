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
