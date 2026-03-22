import Foundation
import IOKit
import IOKit.usb

/// Bridge for reading USB power draw and capability information from IOKit
enum PowerBridge {

    /// Power information for a single USB device
    struct DevicePowerInfo: Sendable {
        let name: String
        let vendorID: Int
        let productID: Int
        let locationID: String
        let usbSpeed: String
        let isRemovable: Bool

        // Power properties
        let busPowerAvailable: Int       // mA available from the bus
        let busPowerUsed: Int            // mA requested by device
        let extraCurrentInSleep: Int     // Extra current in sleep (mA)
        let extraCurrentInWake: Int      // Extra current in wake (mA)
        let isSelfPowered: Bool
        let isHub: Bool
        let portCount: Int               // For hubs: number of ports

        // Raw power-related properties from IORegistry
        let rawProperties: [String: String]
    }

    /// Get power info for a specific device
    static func powerInfo(identifier: String) -> (success: Bool, message: String) {
        guard let device = IOKitBridge.findDevice(identifier: identifier) else {
            return (false, "No device found matching '\(identifier)'")
        }

        let info = queryPowerInfo(
            vendorID: device.vendorID,
            productID: device.productID,
            locationID: device.locationID
        )

        if let info = info {
            return (true, formatSingleDevice(info))
        } else {
            return (false, "Could not read power properties for '\(device.name)'")
        }
    }

    /// Get power summary for all connected devices
    static func powerSummaryAll() -> (success: Bool, message: String) {
        let allInfo = queryAllPowerInfo()

        if allInfo.isEmpty {
            return (true, "No USB devices found.")
        }

        var lines: [String] = ["USB Power Summary (\(allInfo.count) devices):"]
        var totalBusPower = 0

        for info in allInfo {
            lines.append("")
            lines.append(formatDeviceBrief(info))
            totalBusPower += info.busPowerUsed
        }

        lines.append("")
        lines.append("Total bus power draw: \(totalBusPower) mA")

        return (true, lines.joined(separator: "\n"))
    }

    // MARK: - IOKit Queries

    /// Query power info for all USB devices
    private static func queryAllPowerInfo() -> [DevicePowerInfo] {
        let matching = IOServiceMatching(kIOUSBDeviceClassName)
        var iterator: io_iterator_t = 0
        let result = IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator)

        guard result == KERN_SUCCESS else { return [] }
        defer { IOObjectRelease(iterator) }

        var infos: [DevicePowerInfo] = []
        var service = IOIteratorNext(iterator)

        while service != 0 {
            defer {
                IOObjectRelease(service)
                service = IOIteratorNext(iterator)
            }

            if let info = extractPowerInfo(service: service) {
                infos.append(info)
            }
        }

        return infos
    }

    /// Query power info for a specific device by VID+PID+location
    private static func queryPowerInfo(vendorID: Int, productID: Int, locationID: String) -> DevicePowerInfo? {
        let matching = IOServiceMatching(kIOUSBDeviceClassName)
        var iterator: io_iterator_t = 0
        let result = IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator)

        guard result == KERN_SUCCESS else { return nil }
        defer { IOObjectRelease(iterator) }

        var service = IOIteratorNext(iterator)
        while service != 0 {
            defer {
                IOObjectRelease(service)
                service = IOIteratorNext(iterator)
            }

            let vid = getIntProperty(service, kUSBVendorID) ?? 0
            let pid = getIntProperty(service, kUSBProductID) ?? 0
            let loc = getIntProperty(service, kUSBDevicePropertyLocationID) ?? 0
            let locStr = String(format: "0x%08X", loc)

            if vid == vendorID && pid == productID && locStr == locationID {
                return extractPowerInfo(service: service)
            }
        }

        return nil
    }

    /// Extract power properties from an IOKit service entry
    private static func extractPowerInfo(service: io_service_t) -> DevicePowerInfo? {
        let vendorID = getIntProperty(service, kUSBVendorID) ?? 0
        let productID = getIntProperty(service, kUSBProductID) ?? 0

        // Skip root hubs
        if vendorID == 0 && productID == 0 { return nil }

        let name = getStringProperty(service, kUSBProductString)
            ?? getStringProperty(service, "USB Product Name")
            ?? "Unknown Device"
        let locationID = getIntProperty(service, kUSBDevicePropertyLocationID) ?? 0
        let speed = getIntProperty(service, "Device Speed") ?? 0
        let isRemovable = getBoolProperty(service, "Removable") ?? true
        let deviceClass = getIntProperty(service, kUSBDeviceClass) ?? 0

        // Power properties — IOKit reports bus power in 2mA units
        let busPowerAvailable = (getIntProperty(service, "Bus Power Available") ?? 0) * 2
        let busPowerUsed = (getIntProperty(service, kUSBDevicePropertyBusPowerAvailable) ?? getIntProperty(service, "Device Power") ?? 0) * 2

        // Self-powered detection
        let selfPowered = getBoolProperty(service, "Self Powered") ?? false

        // Extra current properties (for sleep/wake scenarios)
        let extraCurrentSleep = getIntProperty(service, "ExtraCurrentInSleep") ?? 0
        let extraCurrentWake = getIntProperty(service, "ExtraCurrentInWake") ?? 0

        // Hub properties
        let isHub = deviceClass == 0x09
        let portCount = getIntProperty(service, "Ports") ?? 0

        // Gather all power-related raw properties for transparency
        var rawProps: [String: String] = [:]
        let powerKeys = [
            "Bus Power Available",
            "Device Power",
            "Self Powered",
            "ExtraCurrentInSleep",
            "ExtraCurrentInWake",
            "kUSBDevicePropertyBusPowerAvailable",
            "bMaxPower",
            "USB Power",
            "Ports",
            "Current Available",
            "Sleep Current",
            "kUSBSleepPowerSupply",
            "kUSBWakePowerSupply",
        ]

        for key in powerKeys {
            if let intVal = getIntProperty(service, key) {
                rawProps[key] = String(intVal)
            } else if let strVal = getStringProperty(service, key) {
                rawProps[key] = strVal
            } else if let boolVal = getBoolProperty(service, key) {
                rawProps[key] = String(boolVal)
            }
        }

        // bMaxPower from USB descriptor (in 2mA units for USB 2.0, 8mA for USB 3.0)
        let bMaxPower = getIntProperty(service, "bMaxPower") ?? 0
        let maxPowerMA: Int
        if speed >= 3 {
            maxPowerMA = bMaxPower * 8  // USB 3.x uses 8mA units
        } else {
            maxPowerMA = bMaxPower * 2  // USB 2.0 uses 2mA units
        }

        // Use the best available power draw value
        let effectivePowerUsed: Int
        if maxPowerMA > 0 {
            effectivePowerUsed = maxPowerMA
        } else if busPowerUsed > 0 {
            effectivePowerUsed = busPowerUsed
        } else {
            effectivePowerUsed = 0
        }

        return DevicePowerInfo(
            name: name,
            vendorID: vendorID,
            productID: productID,
            locationID: String(format: "0x%08X", locationID),
            usbSpeed: speedString(speed),
            isRemovable: isRemovable,
            busPowerAvailable: busPowerAvailable,
            busPowerUsed: effectivePowerUsed,
            extraCurrentInSleep: extraCurrentSleep,
            extraCurrentInWake: extraCurrentWake,
            isSelfPowered: selfPowered,
            isHub: isHub,
            portCount: portCount,
            rawProperties: rawProps
        )
    }

    // MARK: - Formatting

    private static func formatSingleDevice(_ info: DevicePowerInfo) -> String {
        var lines = [
            "Power Info: \(info.name)",
            "  Vendor: \(String(format: "0x%04X", info.vendorID))",
            "  Product: \(String(format: "0x%04X", info.productID))",
            "  Location: \(info.locationID)",
            "  Speed: \(info.usbSpeed)",
            "",
            "  Power Source: \(info.isSelfPowered ? "Self-powered" : "Bus-powered")",
            "  Bus Power Available: \(info.busPowerAvailable) mA",
            "  Power Requested: \(info.busPowerUsed) mA",
        ]

        if info.extraCurrentInSleep > 0 {
            lines.append("  Extra Current (Sleep): \(info.extraCurrentInSleep) mA")
        }
        if info.extraCurrentInWake > 0 {
            lines.append("  Extra Current (Wake): \(info.extraCurrentInWake) mA")
        }

        if info.isHub {
            lines.append("")
            lines.append("  Hub: Yes")
            if info.portCount > 0 {
                lines.append("  Port Count: \(info.portCount)")
                let perPort = info.busPowerAvailable > 0 ? info.busPowerAvailable / max(info.portCount, 1) : 0
                if perPort > 0 {
                    lines.append("  Per-Port Power Budget: ~\(perPort) mA")
                }
            }
            lines.append("  Total Power Budget: \(info.busPowerAvailable) mA")
        }

        // Charging type detection based on power capabilities
        lines.append("")
        if info.busPowerUsed >= 1500 || info.busPowerAvailable >= 1500 {
            lines.append("  Charging: USB-C Power Delivery or high-power capable")
        } else if info.busPowerUsed >= 500 || info.busPowerAvailable >= 900 {
            lines.append("  Charging: CDP (Charging Downstream Port) — standard USB charging")
        } else if info.busPowerAvailable >= 100 {
            lines.append("  Charging: SDP (Standard Downstream Port) — limited power")
        }

        // Raw properties
        if !info.rawProperties.isEmpty {
            lines.append("")
            lines.append("  Raw Power Properties:")
            for (key, value) in info.rawProperties.sorted(by: { $0.key < $1.key }) {
                lines.append("    \(key): \(value)")
            }
        }

        return lines.joined(separator: "\n")
    }

    private static func formatDeviceBrief(_ info: DevicePowerInfo) -> String {
        let powerSource = info.isSelfPowered ? "self" : "bus"
        let hubLabel = info.isHub ? " [HUB \(info.portCount)p]" : ""
        return "  \(info.name)\(hubLabel) — \(info.busPowerUsed) mA (\(powerSource)-powered) | \(info.usbSpeed)"
    }

    // MARK: - IOKit Helpers

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
}
