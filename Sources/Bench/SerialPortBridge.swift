import Foundation

/// Discovers serial ports and matches them to USB devices
enum SerialPortBridge {

    /// A discovered serial port
    struct SerialPort: Sendable {
        let path: String           // e.g. "/dev/cu.usbserial-2120"
        let locationHint: String?  // extracted location suffix, e.g. "2120"
        let type: PortType
        let deviceType: DeviceCategory

        enum PortType: String, Sendable {
            case usbSerial          // CH340, CP210x, FTDI, etc.
            case usbModem           // CDC ACM devices (Arduino Leonardo, native USB boards)
            case other
        }

        enum DeviceCategory: String, Sendable {
            case usb = "usb"
            case bluetooth = "bluetooth"
            case builtIn = "built_in"
        }
    }

    /// Discover all USB-related serial ports (filters out Bluetooth, debug-console, etc.)
    static func discoverPorts() -> [SerialPort] {
        let fm = FileManager.default
        var ports: [SerialPort] = []

        guard let entries = try? fm.contentsOfDirectory(atPath: "/dev") else {
            return []
        }

        for entry in entries {
            // Only look at cu.* devices (call-out, not call-in tty.*)
            guard entry.hasPrefix("cu.") else { continue }

            // Skip non-USB ports
            let skipPrefixes = ["cu.Bluetooth", "cu.debug"]
            if skipPrefixes.contains(where: { entry.hasPrefix($0) }) { continue }

            let path = "/dev/\(entry)"

            let (type, locationHint) = classifyPort(entry)
            if type == .other { continue } // Skip unrecognized ports

            ports.append(SerialPort(
                path: path,
                locationHint: locationHint,
                type: type,
                deviceType: .usb
            ))
        }

        return ports
    }

    /// Discover all serial ports on the system, including Bluetooth and built-in
    static func allPorts(filterDeviceType: SerialPort.DeviceCategory? = nil) -> [SerialPort] {
        let fm = FileManager.default
        var ports: [SerialPort] = []

        guard let entries = try? fm.contentsOfDirectory(atPath: "/dev") else {
            return []
        }

        for entry in entries.sorted() {
            guard entry.hasPrefix("cu.") else { continue }

            let path = "/dev/\(entry)"

            // Classify by device category
            let deviceCategory: SerialPort.DeviceCategory
            let portType: SerialPort.PortType
            let locationHint: String?

            if entry.hasPrefix("cu.Bluetooth") || entry.hasPrefix("cu.BLE") {
                deviceCategory = .bluetooth
                portType = .other
                locationHint = nil
            } else if entry == "cu.wlan-debug" || entry.hasPrefix("cu.debug") {
                deviceCategory = .builtIn
                portType = .other
                locationHint = nil
            } else {
                let (classified, hint) = classifyPort(entry)
                if classified == .other {
                    // Unrecognized cu.* — treat as built-in
                    deviceCategory = .builtIn
                    portType = .other
                    locationHint = nil
                } else {
                    deviceCategory = .usb
                    portType = classified
                    locationHint = hint
                }
            }

            // Apply filter
            if let filter = filterDeviceType, filter != deviceCategory {
                continue
            }

            ports.append(SerialPort(
                path: path,
                locationHint: locationHint,
                type: portType,
                deviceType: deviceCategory
            ))
        }

        return ports
    }

    /// Try to match a serial port to a USB device from the provided device list
    static func matchDevice(port: SerialPort, devices: [USBDevice]) -> USBDevice? {
        guard let hint = port.locationHint else { return nil }
        return devices.first { device in
            locationMatches(locationID: device.locationID, portHint: hint)
        }
    }

    /// Match discovered serial ports to USB devices by location ID
    static func enrichDevices(_ devices: inout [USBDevice]) {
        let ports = discoverPorts()

        for i in devices.indices {
            let locID = devices[i].locationID // e.g. "0x02120000"

            for port in ports {
                guard let hint = port.locationHint else { continue }

                // Match: the port suffix should appear in the hex location ID
                // e.g. port "cu.usbserial-2120" has hint "2120"
                //      location "0x02120000" contains "2120"
                if locationMatches(locationID: locID, portHint: hint) {
                    devices[i].serialPort = port.path
                    break
                }
            }
        }
    }

    // MARK: - Private

    /// Classify a /dev/cu.* entry and extract the location hint
    private static func classifyPort(_ name: String) -> (SerialPort.PortType, String?) {
        // cu.usbserial-XXXX — CH340, FTDI, CP210x, Prolific
        if name.hasPrefix("cu.usbserial-") {
            let suffix = String(name.dropFirst("cu.usbserial-".count))
            return (.usbSerial, suffix)
        }

        // cu.usbmodem-XXXX or cu.usbmodemXXXX — CDC ACM (Arduino Leonardo, native USB boards)
        if name.hasPrefix("cu.usbmodem") {
            let suffix = String(name.dropFirst("cu.usbmodem".count))
            // Strip leading dash if present
            let cleaned = suffix.hasPrefix("-") ? String(suffix.dropFirst()) : suffix
            // macOS often appends extra digits (e.g. "21201" for location 2120)
            // Extract the base location: drop the last digit if length > 4
            let locationHint = cleaned.count > 4 ? String(cleaned.dropLast()) : cleaned
            return (.usbModem, locationHint)
        }

        // cu.wchusbserial-XXXX — CH340 on older macOS drivers
        if name.hasPrefix("cu.wchusbserial") {
            let suffix = String(name.dropFirst("cu.wchusbserial".count))
            let cleaned = suffix.hasPrefix("-") ? String(suffix.dropFirst()) : suffix
            return (.usbSerial, cleaned)
        }

        // cu.SLAB_USBtoUART — CP210x with Silicon Labs driver
        if name.hasPrefix("cu.SLAB_") {
            return (.usbSerial, nil)
        }

        return (.other, nil)
    }

    /// Check if a port hint (e.g. "2120") matches a location ID (e.g. "0x02120000")
    /// macOS derives serial port names from the USB location ID, but the exact
    /// truncation varies by driver. We check if the hint appears in the hex string.
    private static func locationMatches(locationID: String, portHint: String) -> Bool {
        var hex = locationID.lowercased()
        if hex.hasPrefix("0x") {
            hex = String(hex.dropFirst(2))
        }
        return hex.contains(portHint.lowercased())
    }
}
