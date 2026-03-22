import Foundation
import IOKit
import IOKit.usb

/// Reads full USB descriptor chains from IOKit for a device.
enum DescriptorBridge {

    /// Full descriptor tree for a device
    struct DeviceDescriptors: Sendable {
        let deviceName: String
        let vendorID: Int
        let productID: Int
        let bcdUSB: String
        let bDeviceClass: Int
        let bDeviceSubClass: Int
        let bDeviceProtocol: Int
        let bMaxPacketSize0: Int
        let bcdDevice: String
        let iManufacturer: String
        let iProduct: String
        let iSerialNumber: String
        let bNumConfigurations: Int
        let configurations: [ConfigurationDescriptor]
    }

    struct ConfigurationDescriptor: Sendable {
        let bConfigurationValue: Int
        let iConfiguration: String
        let bmAttributes: Int
        let bMaxPower: Int          // in mA
        let bNumInterfaces: Int
        let interfaces: [InterfaceDescriptor]
    }

    struct InterfaceDescriptor: Sendable {
        let bInterfaceNumber: Int
        let bAlternateSetting: Int
        let bInterfaceClass: Int
        let bInterfaceSubClass: Int
        let bInterfaceProtocol: Int
        let iInterface: String
        let className: String       // Human-readable class name
        let bNumEndpoints: Int
        let endpoints: [EndpointDescriptor]
    }

    struct EndpointDescriptor: Sendable {
        let bEndpointAddress: Int
        let direction: String       // "IN" or "OUT"
        let bmAttributes: Int
        let transferType: String    // "Control", "Isochronous", "Bulk", "Interrupt"
        let wMaxPacketSize: Int
        let bInterval: Int
    }

    /// Read full descriptors for a device identified by serial, location ID, or name
    static func readDescriptors(identifier: String) -> DeviceDescriptors? {
        let matching = IOServiceMatching(kIOUSBDeviceClassName)
        var iterator: io_iterator_t = 0
        let result = IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator)

        guard result == KERN_SUCCESS else { return nil }
        defer { IOObjectRelease(iterator) }

        let id = identifier.lowercased()
        var service = IOIteratorNext(iterator)

        while service != 0 {
            defer {
                IOObjectRelease(service)
                service = IOIteratorNext(iterator)
            }

            let vendorID = getInt(service, kUSBVendorID) ?? 0
            let productID = getInt(service, kUSBProductID) ?? 0
            let serial = getString(service, kUSBSerialNumberString) ?? ""
            let locationID = getInt(service, kUSBDevicePropertyLocationID) ?? 0
            let locationHex = String(format: "0x%08x", locationID)
            let name = getString(service, kUSBProductString)
                ?? getString(service, "USB Product Name")
                ?? "Unknown Device"

            // Match by serial, location, or name
            let matched = serial.lowercased() == id
                || locationHex.lowercased() == id
                || name.lowercased().contains(id)

            guard matched else { continue }

            // Read device-level descriptor properties
            let bcdUSBRaw = getInt(service, "bcdUSB") ?? getInt(service, kUSBDeviceReleaseNumber) ?? 0
            let bDeviceClass = getInt(service, kUSBDeviceClass) ?? 0
            let bDeviceSubClass = getInt(service, kUSBDeviceSubClass) ?? 0
            let bDeviceProtocol = getInt(service, kUSBDeviceProtocol) ?? 0
            let bMaxPacketSize0 = getInt(service, "bMaxPacketSize0") ?? getInt(service, kUSBDeviceMaxPacketSize) ?? 0
            let bcdDevice = getInt(service, "bcdDevice") ?? getInt(service, kUSBDeviceReleaseNumber) ?? 0
            let manufacturer = getString(service, kUSBVendorString)
                ?? DeviceDatabase.vendorName(for: vendorID)
                ?? "Unknown"
            let bNumConfigurations = getInt(service, "bNumConfigurations")
                ?? getInt(service, kUSBDeviceNumConfigs) ?? 1

            // Read interface descriptors from child services
            let configurations = readConfigurations(deviceService: service)

            return DeviceDescriptors(
                deviceName: name,
                vendorID: vendorID,
                productID: productID,
                bcdUSB: formatBCD(bcdUSBRaw),
                bDeviceClass: bDeviceClass,
                bDeviceSubClass: bDeviceSubClass,
                bDeviceProtocol: bDeviceProtocol,
                bMaxPacketSize0: bMaxPacketSize0,
                bcdDevice: formatBCD(bcdDevice),
                iManufacturer: manufacturer,
                iProduct: name,
                iSerialNumber: serial.isEmpty ? "(none)" : serial,
                bNumConfigurations: bNumConfigurations,
                configurations: configurations
            )
        }

        return nil
    }

    // MARK: - Private

    /// Read configuration and interface descriptors from the IOKit registry tree
    private static func readConfigurations(deviceService: io_service_t) -> [ConfigurationDescriptor] {
        var configurations: [ConfigurationDescriptor] = []

        // Get configuration-level properties from the device
        let bmAttributes = getInt(deviceService, "bmAttributes") ?? 0x80  // Default: bus-powered
        let bMaxPower = getInt(deviceService, "Bus Power Available") ?? 0

        // Walk child services (interfaces) under this device
        var childIterator: io_iterator_t = 0
        let result = IORegistryEntryGetChildIterator(deviceService, kIOServicePlane, &childIterator)

        var interfaces: [InterfaceDescriptor] = []

        if result == KERN_SUCCESS {
            defer { IOObjectRelease(childIterator) }

            var child = IOIteratorNext(childIterator)
            while child != 0 {
                defer {
                    IOObjectRelease(child)
                    child = IOIteratorNext(childIterator)
                }

                // Check if this is an interface
                let interfaceNumber = getInt(child, kUSBInterfaceNumber)
                guard let ifNum = interfaceNumber else { continue }

                let ifClass = getInt(child, kUSBInterfaceClass) ?? 0
                let ifSubClass = getInt(child, kUSBInterfaceSubClass) ?? 0
                let ifProtocol = getInt(child, kUSBInterfaceProtocol) ?? 0
                let altSetting = getInt(child, kUSBAlternateSetting) ?? 0
                let ifString = getString(child, kUSBInterfaceStringIndex) ?? ""
                let numEndpoints = getInt(child, kUSBNumEndpoints) ?? 0

                // Read endpoints from grandchild services
                let endpoints = readEndpoints(interfaceService: child)

                interfaces.append(InterfaceDescriptor(
                    bInterfaceNumber: ifNum,
                    bAlternateSetting: altSetting,
                    bInterfaceClass: ifClass,
                    bInterfaceSubClass: ifSubClass,
                    bInterfaceProtocol: ifProtocol,
                    iInterface: ifString,
                    className: usbClassName(classCode: ifClass, subclassCode: ifSubClass),
                    bNumEndpoints: numEndpoints > 0 ? numEndpoints : endpoints.count,
                    endpoints: endpoints
                ))
            }
        }

        // Build a single configuration (most devices have one)
        if !interfaces.isEmpty || true {
            configurations.append(ConfigurationDescriptor(
                bConfigurationValue: 1,
                iConfiguration: "",
                bmAttributes: bmAttributes,
                bMaxPower: bMaxPower * 2, // IOKit reports in 2mA units
                bNumInterfaces: interfaces.count,
                interfaces: interfaces
            ))
        }

        return configurations
    }

    /// Read endpoint descriptors from interface children
    private static func readEndpoints(interfaceService: io_service_t) -> [EndpointDescriptor] {
        var endpoints: [EndpointDescriptor] = []

        var childIterator: io_iterator_t = 0
        let result = IORegistryEntryGetChildIterator(interfaceService, kIOServicePlane, &childIterator)

        guard result == KERN_SUCCESS else { return [] }
        defer { IOObjectRelease(childIterator) }

        var child = IOIteratorNext(childIterator)
        while child != 0 {
            defer {
                IOObjectRelease(child)
                child = IOIteratorNext(childIterator)
            }

            // Look for endpoint properties
            if let address = getInt(child, "bEndpointAddress") {
                let attributes = getInt(child, "bmAttributes") ?? 0
                let maxPacket = getInt(child, "wMaxPacketSize") ?? 0
                let interval = getInt(child, "bInterval") ?? 0

                let direction = (address & 0x80) != 0 ? "IN" : "OUT"
                let transferType: String
                switch attributes & 0x03 {
                case 0: transferType = "Control"
                case 1: transferType = "Isochronous"
                case 2: transferType = "Bulk"
                case 3: transferType = "Interrupt"
                default: transferType = "Unknown"
                }

                endpoints.append(EndpointDescriptor(
                    bEndpointAddress: address,
                    direction: direction,
                    bmAttributes: attributes,
                    transferType: transferType,
                    wMaxPacketSize: maxPacket,
                    bInterval: interval
                ))
            }
        }

        return endpoints
    }

    /// Format a BCD-encoded version number (e.g. 0x0200 -> "2.00")
    private static func formatBCD(_ bcd: Int) -> String {
        let major = (bcd >> 8) & 0xFF
        let minor = (bcd >> 4) & 0x0F
        let patch = bcd & 0x0F
        if patch == 0 {
            return "\(major).\(minor)0"
        }
        return "\(major).\(minor)\(patch)"
    }

    /// Map USB class code to human-readable name
    private static func usbClassName(classCode: Int, subclassCode: Int) -> String {
        switch classCode {
        case 0x00: return "Defined at Interface Level"
        case 0x01: return "Audio"
        case 0x02:
            switch subclassCode {
            case 0x02: return "Abstract Control Model (ACM/Serial)"
            case 0x06: return "Ethernet Networking"
            case 0x0D: return "Network Control Model (NCM)"
            default: return "Communications (CDC)"
            }
        case 0x03: return "Human Interface Device (HID)"
        case 0x05: return "Physical"
        case 0x06: return "Still Imaging"
        case 0x07: return "Printer"
        case 0x08: return "Mass Storage"
        case 0x09: return "Hub"
        case 0x0A: return "CDC-Data"
        case 0x0B: return "Smart Card"
        case 0x0D: return "Content Security"
        case 0x0E: return "Video"
        case 0x0F: return "Personal Healthcare"
        case 0x10: return "Audio/Video"
        case 0x11: return "Billboard"
        case 0x12: return "USB Type-C Bridge"
        case 0xDC: return "Diagnostic"
        case 0xE0:
            switch subclassCode {
            case 0x01: return "Bluetooth"
            case 0x02: return "Wireless USB"
            default: return "Wireless Controller"
            }
        case 0xEF: return "Miscellaneous"
        case 0xFE: return "Application Specific"
        case 0xFF: return "Vendor Specific"
        default: return "Unknown (\(String(format: "0x%02X", classCode)))"
        }
    }

    // MARK: - IOKit helpers (duplicated to avoid cross-file dependencies)

    private static func getString(_ service: io_service_t, _ key: String) -> String? {
        guard let value = IORegistryEntryCreateCFProperty(
            service, key as CFString, kCFAllocatorDefault, 0
        )?.takeRetainedValue() else {
            return nil
        }
        return value as? String
    }

    private static func getInt(_ service: io_service_t, _ key: String) -> Int? {
        guard let value = IORegistryEntryCreateCFProperty(
            service, key as CFString, kCFAllocatorDefault, 0
        )?.takeRetainedValue() else {
            return nil
        }
        return value as? Int
    }
}
