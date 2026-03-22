import Foundation
import IOKit
import IOKit.usb

/// Bridge for USB device control operations (port reset / re-enumeration)
enum DeviceControlBridge {

    /// Attempt to reset (re-enumerate) a USB device, simulating an unplug/replug cycle.
    /// Requires the device to be external/removable. Returns (success, message).
    static func resetDevice(identifier: String) -> (success: Bool, message: String) {
        // Find the device first
        guard let device = IOKitBridge.findDevice(identifier: identifier) else {
            return (false, "No device found matching '\(identifier)'")
        }

        // Safety: refuse to reset internal devices
        if !device.isRemovable {
            return (false, "Refusing to reset '\(device.name)' — it is an internal/non-removable device. Only external devices can be reset.")
        }

        // Apple vendor devices should not be reset
        if device.vendorID == 0x05AC {
            return (false, "Refusing to reset '\(device.name)' — Apple internal devices cannot be safely reset.")
        }

        // Attempt IOKit-based reset
        let (resetOK, resetMsg) = performIOKitReset(device: device)

        if resetOK {
            // Give the device time to re-enumerate
            Thread.sleep(forTimeInterval: 1.0)

            let newState: String
            if let reFound = IOKitBridge.findDevice(identifier: identifier) {
                newState = """
                Device re-enumerated successfully:
                  Name: \(reFound.name)
                  Location: \(reFound.locationID)
                  Speed: \(reFound.usbSpeed)
                  Bus Power: \(reFound.busPowerMA) mA
                """
            } else {
                newState = "Device has not yet re-appeared. It may need a few more seconds to re-enumerate, or the reset may have disconnected it."
            }

            return (true, """
            Port reset succeeded for '\(device.name)'.
            \(resetMsg)

            \(newState)
            """)
        }

        // IOKit reset failed — provide manual fallback instructions
        return (false, """
        Port reset failed for '\(device.name)'.
        \(resetMsg)

        Manual recovery steps:
        1. Physically unplug and replug the device
        2. If the device is on a hub, try a different port
        3. Run: sudo killall -STOP -c usbd && sudo killall -CONT -c usbd
        4. As a last resort: sudo kextunload -b com.apple.driver.usb.AppleUSBXHCI && sudo kextload -b com.apple.driver.usb.AppleUSBXHCI
        """)
    }

    // MARK: - Private

    /// Attempt to reset a device via IOKit registry methods
    private static func performIOKitReset(device: USBDevice) -> (success: Bool, message: String) {
        let matching = IOServiceMatching(kIOUSBDeviceClassName)
        var iterator: io_iterator_t = 0
        let result = IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator)

        guard result == KERN_SUCCESS else {
            return (false, "Failed to access IOKit USB services")
        }
        defer { IOObjectRelease(iterator) }

        var service = IOIteratorNext(iterator)
        while service != 0 {
            defer {
                IOObjectRelease(service)
                service = IOIteratorNext(iterator)
            }

            let vendorID = getIntProperty(service, kUSBVendorID) ?? 0
            let productID = getIntProperty(service, kUSBProductID) ?? 0
            let locationID = getIntProperty(service, kUSBDevicePropertyLocationID) ?? 0
            let locationStr = String(format: "0x%08X", locationID)

            // Match by VID+PID+location
            if vendorID == device.vendorID &&
               productID == device.productID &&
               locationStr == device.locationID {

                // Method 1: IOServiceRequestProbe — asks the driver to re-probe the device
                let probeResult = IOServiceRequestProbe(service, 0)
                if probeResult == KERN_SUCCESS {
                    return (true, "IOServiceRequestProbe succeeded — device driver will re-probe.")
                }

                // Method 2: Set re-enumerate property on the IORegistryEntry
                let properties: NSDictionary = ["USB Device Re-Enumerate" : true as CFBoolean]
                let setResult = IORegistryEntrySetCFProperties(service, properties)
                if setResult == KERN_SUCCESS {
                    return (true, "IORegistryEntry re-enumerate property set — device should re-enumerate.")
                }

                // Method 3: Try requesting termination + re-registration
                let termProperties: NSDictionary = ["IORequestTerminate" : true as CFBoolean]
                let termResult = IORegistryEntrySetCFProperties(service, termProperties)
                if termResult == KERN_SUCCESS {
                    return (true, "IORegistryEntry termination requested — device should re-attach.")
                }

                return (false, "All IOKit reset methods failed (probe: \(probeResult), property: \(setResult), terminate: \(termResult)). The device may require physical reconnection or elevated privileges (sudo).")
            }
        }

        return (false, "Could not find matching IOKit service for device.")
    }

    // MARK: - IOKit Helpers

    private static func getIntProperty(_ service: io_service_t, _ key: String) -> Int? {
        guard let value = IORegistryEntryCreateCFProperty(
            service, key as CFString, kCFAllocatorDefault, 0
        )?.takeRetainedValue() else {
            return nil
        }
        return value as? Int
    }
}
