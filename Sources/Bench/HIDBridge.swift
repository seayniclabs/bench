import Foundation
import IOKit
import IOKit.hid

/// Bridge to IOKit HID Manager for sending/receiving HID reports
enum HIDBridge {

    /// Result of a HID operation
    struct HIDResult: Sendable {
        let success: Bool
        let message: String
        let data: String?    // Hex string of returned data, if any
    }

    /// HID report descriptor summary
    struct ReportDescriptor: Sendable {
        let reportID: Int
        let reportType: String    // "input", "output", "feature"
        let reportSize: Int       // Size in bytes
    }

    // MARK: - Device Validation

    /// Check if a USB device is a HID device by looking at its device class
    static func isHIDDevice(_ device: USBDevice) -> Bool {
        // USB class 3 = HID
        if device.deviceClass == 0x03 {
            return true
        }
        // Composite devices (class 0) may have HID interfaces —
        // check if IOKit can find a HID device matching this vendor/product
        if device.deviceClass == 0x00 || device.deviceClass == 0xFF {
            return findHIDDevice(vendorID: device.vendorID, productID: device.productID) != nil
        }
        return false
    }

    // MARK: - Report Operations

    /// Send a report to a HID device
    static func sendReport(
        vendorID: Int,
        productID: Int,
        reportType: ReportType,
        reportID: Int,
        data: [UInt8]
    ) -> HIDResult {
        guard let deviceRef = findHIDDevice(vendorID: vendorID, productID: productID) else {
            return HIDResult(
                success: false,
                message: "Could not find HID device with VID=\(String(format: "0x%04X", vendorID)) PID=\(String(format: "0x%04X", productID))",
                data: nil
            )
        }

        let openResult = IOHIDDeviceOpen(deviceRef, IOOptionBits(kIOHIDOptionsTypeNone))
        guard openResult == kIOReturnSuccess else {
            return HIDResult(
                success: false,
                message: "Failed to open HID device (error: \(String(format: "0x%08X", openResult))). The device may be in use by another application.",
                data: nil
            )
        }
        defer { IOHIDDeviceClose(deviceRef, IOOptionBits(kIOHIDOptionsTypeNone)) }

        let cfReportType: IOHIDReportType
        switch reportType {
        case .output:
            cfReportType = kIOHIDReportTypeOutput
        case .feature:
            cfReportType = kIOHIDReportTypeFeature
        }

        var reportData = data
        let result = IOHIDDeviceSetReport(
            deviceRef,
            cfReportType,
            CFIndex(reportID),
            &reportData,
            reportData.count
        )

        if result == kIOReturnSuccess {
            return HIDResult(
                success: true,
                message: "Report sent successfully (type=\(reportType.rawValue), id=\(reportID), \(data.count) bytes)",
                data: formatHexString(data)
            )
        } else {
            return HIDResult(
                success: false,
                message: "Failed to send report (error: \(String(format: "0x%08X", result)))",
                data: nil
            )
        }
    }

    /// Read a report from a HID device
    static func getReport(
        vendorID: Int,
        productID: Int,
        reportType: ReportType,
        reportID: Int,
        maxLength: Int = 64
    ) -> HIDResult {
        guard let deviceRef = findHIDDevice(vendorID: vendorID, productID: productID) else {
            return HIDResult(
                success: false,
                message: "Could not find HID device with VID=\(String(format: "0x%04X", vendorID)) PID=\(String(format: "0x%04X", productID))",
                data: nil
            )
        }

        let openResult = IOHIDDeviceOpen(deviceRef, IOOptionBits(kIOHIDOptionsTypeNone))
        guard openResult == kIOReturnSuccess else {
            return HIDResult(
                success: false,
                message: "Failed to open HID device (error: \(String(format: "0x%08X", openResult))). The device may be in use by another application.",
                data: nil
            )
        }
        defer { IOHIDDeviceClose(deviceRef, IOOptionBits(kIOHIDOptionsTypeNone)) }

        let cfReportType: IOHIDReportType
        switch reportType {
        case .output:
            cfReportType = kIOHIDReportTypeOutput
        case .feature:
            cfReportType = kIOHIDReportTypeFeature
        }

        var buffer = [UInt8](repeating: 0, count: maxLength)
        var reportLength = CFIndex(maxLength)

        let result = IOHIDDeviceGetReport(
            deviceRef,
            cfReportType,
            CFIndex(reportID),
            &buffer,
            &reportLength
        )

        if result == kIOReturnSuccess {
            let actualData = Array(buffer.prefix(reportLength))
            return HIDResult(
                success: true,
                message: "Report read successfully (type=\(reportType.rawValue), id=\(reportID), \(reportLength) bytes)",
                data: formatHexString(actualData)
            )
        } else {
            return HIDResult(
                success: false,
                message: "Failed to read report (error: \(String(format: "0x%08X", result)))",
                data: nil
            )
        }
    }

    /// List HID report descriptors for a device
    static func listReports(vendorID: Int, productID: Int) -> (success: Bool, message: String, reports: [ReportDescriptor]) {
        guard let deviceRef = findHIDDevice(vendorID: vendorID, productID: productID) else {
            return (
                false,
                "Could not find HID device with VID=\(String(format: "0x%04X", vendorID)) PID=\(String(format: "0x%04X", productID))",
                []
            )
        }

        var reports: [ReportDescriptor] = []

        // Query device properties for report info
        if let maxInputSize = IOHIDDeviceGetProperty(deviceRef, kIOHIDMaxInputReportSizeKey as CFString) as? Int, maxInputSize > 0 {
            reports.append(ReportDescriptor(reportID: 0, reportType: "input", reportSize: maxInputSize))
        }
        if let maxOutputSize = IOHIDDeviceGetProperty(deviceRef, kIOHIDMaxOutputReportSizeKey as CFString) as? Int, maxOutputSize > 0 {
            reports.append(ReportDescriptor(reportID: 0, reportType: "output", reportSize: maxOutputSize))
        }
        if let maxFeatureSize = IOHIDDeviceGetProperty(deviceRef, kIOHIDMaxFeatureReportSizeKey as CFString) as? Int, maxFeatureSize > 0 {
            reports.append(ReportDescriptor(reportID: 0, reportType: "feature", reportSize: maxFeatureSize))
        }

        // Get usage page and usage for context
        let usagePage = IOHIDDeviceGetProperty(deviceRef, kIOHIDPrimaryUsagePageKey as CFString) as? Int ?? 0
        let usage = IOHIDDeviceGetProperty(deviceRef, kIOHIDPrimaryUsageKey as CFString) as? Int ?? 0
        let product = IOHIDDeviceGetProperty(deviceRef, kIOHIDProductKey as CFString) as? String ?? "Unknown"

        let usageDesc = describeUsage(page: usagePage, usage: usage)

        let summary = """
        HID Device: \(product)
          Vendor ID: \(String(format: "0x%04X", vendorID))
          Product ID: \(String(format: "0x%04X", productID))
          Usage Page: \(String(format: "0x%04X", usagePage)) (\(usageDesc.page))
          Usage: \(String(format: "0x%04X", usage)) (\(usageDesc.usage))
          Reports: \(reports.count) report type\(reports.count == 1 ? "" : "s") available
        """

        return (true, summary, reports)
    }

    // MARK: - Types

    enum ReportType: String, Sendable {
        case output
        case feature
    }

    // MARK: - Private

    /// Find a HID device by vendor and product ID using IOHIDManager
    private static func findHIDDevice(vendorID: Int, productID: Int) -> IOHIDDevice? {
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))

        let matching: [String: Any] = [
            kIOHIDVendorIDKey as String: vendorID,
            kIOHIDProductIDKey as String: productID
        ]
        IOHIDManagerSetDeviceMatching(manager, matching as CFDictionary)

        let openResult = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        guard openResult == kIOReturnSuccess else {
            return nil
        }

        guard let deviceSet = IOHIDManagerCopyDevices(manager) else {
            IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
            return nil
        }

        let devices = deviceSet as! Set<IOHIDDevice>

        guard let device = devices.first else {
            IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
            return nil
        }

        // NOTE: We intentionally do NOT close the manager here because
        // the device reference is only valid while the manager is open.
        // The caller is responsible for the device lifecycle via open/close.
        return device
    }

    /// Parse a hex string like "0x01 0xFF 0x00" or "01ff00" into bytes
    static func parseHexData(_ input: String) -> [UInt8]? {
        var cleaned = input
            .replacingOccurrences(of: "0x", with: "")
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: ",", with: "")
            .uppercased()

        // Must be even number of hex chars
        guard cleaned.count % 2 == 0 else { return nil }

        var bytes: [UInt8] = []
        while !cleaned.isEmpty {
            let hexByte = String(cleaned.prefix(2))
            cleaned = String(cleaned.dropFirst(2))
            guard let byte = UInt8(hexByte, radix: 16) else { return nil }
            bytes.append(byte)
        }

        return bytes
    }

    /// Format bytes as a hex string
    private static func formatHexString(_ data: [UInt8]) -> String {
        return data.map { String(format: "0x%02X", $0) }.joined(separator: " ")
    }

    /// Describe a HID usage page and usage
    private static func describeUsage(page: Int, usage: Int) -> (page: String, usage: String) {
        let pageName: String
        var usageName = "Unknown"

        switch page {
        case 0x01:
            pageName = "Generic Desktop"
            switch usage {
            case 0x01: usageName = "Pointer"
            case 0x02: usageName = "Mouse"
            case 0x04: usageName = "Joystick"
            case 0x05: usageName = "Game Pad"
            case 0x06: usageName = "Keyboard"
            case 0x07: usageName = "Keypad"
            default: break
            }
        case 0x06:
            pageName = "Generic Device"
            usageName = "Device Controls"
        case 0x07:
            pageName = "Keyboard/Keypad"
            usageName = "Keyboard"
        case 0x08:
            pageName = "LED"
            usageName = "LED Indicator"
        case 0x09:
            pageName = "Button"
            usageName = "Button"
        case 0x0C:
            pageName = "Consumer"
            switch usage {
            case 0x01: usageName = "Consumer Control"
            case 0x02: usageName = "Numeric Keypad"
            default: usageName = "Consumer Device"
            }
        case 0x0D:
            pageName = "Digitizers"
            usageName = "Digitizer"
        case 0xFF00...0xFFFF:
            pageName = "Vendor Defined"
            usageName = "Vendor Specific"
        default:
            pageName = "Unknown"
        }

        return (pageName, usageName)
    }
}
