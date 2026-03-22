import Foundation

/// Tracks USB connect/disconnect events using a polling approach.
/// Maintains a circular buffer of the last 50 events and compares
/// current USB state against a previous snapshot to detect changes.
final class EventMonitor: @unchecked Sendable {

    static let shared = EventMonitor()

    /// A single USB event (connect or disconnect)
    struct USBEvent: Sendable {
        let timestamp: Date
        let eventType: String      // "connected" or "disconnected"
        let deviceName: String
        let vendorID: Int
        let productID: Int
        let serialNumber: String
        let locationID: String
    }

    /// Lightweight device fingerprint for diffing
    private struct DeviceFingerprint: Hashable, Sendable {
        let vendorID: Int
        let productID: Int
        let serialNumber: String
        let locationID: String
    }

    private let lock = NSLock()
    private var eventLog: [USBEvent] = []
    private var previousDevices: [DeviceFingerprint: String] = [:]  // fingerprint -> name
    private var initialized = false
    private let maxEvents = 50

    private init() {}

    /// Poll for changes. On first call, snapshots current state.
    /// On subsequent calls, diffs current vs previous and records events.
    /// Returns the full event log.
    func poll() -> [USBEvent] {
        lock.lock()
        defer { lock.unlock() }

        let currentDevices = snapshotCurrentState()

        if !initialized {
            previousDevices = currentDevices
            initialized = true
            return eventLog
        }

        let currentKeys = Set(currentDevices.keys)
        let previousKeys = Set(previousDevices.keys)

        let now = Date()

        // Newly connected devices
        for key in currentKeys.subtracting(previousKeys) {
            let name = currentDevices[key] ?? "Unknown Device"
            appendEvent(USBEvent(
                timestamp: now,
                eventType: "connected",
                deviceName: name,
                vendorID: key.vendorID,
                productID: key.productID,
                serialNumber: key.serialNumber,
                locationID: key.locationID
            ))
        }

        // Disconnected devices
        for key in previousKeys.subtracting(currentKeys) {
            let name = previousDevices[key] ?? "Unknown Device"
            appendEvent(USBEvent(
                timestamp: now,
                eventType: "disconnected",
                deviceName: name,
                vendorID: key.vendorID,
                productID: key.productID,
                serialNumber: key.serialNumber,
                locationID: key.locationID
            ))
        }

        previousDevices = currentDevices
        return eventLog
    }

    /// Clear the event log and re-snapshot current state
    func clear() -> [USBEvent] {
        lock.lock()
        defer { lock.unlock() }

        eventLog.removeAll()
        previousDevices = snapshotCurrentState()
        initialized = true
        return eventLog
    }

    // MARK: - Private

    private func appendEvent(_ event: USBEvent) {
        eventLog.append(event)
        if eventLog.count > maxEvents {
            eventLog.removeFirst(eventLog.count - maxEvents)
        }
    }

    private func snapshotCurrentState() -> [DeviceFingerprint: String] {
        let devices = IOKitBridge.enumerateDevices(includeInternal: true)
        var map: [DeviceFingerprint: String] = [:]
        for device in devices {
            let fp = DeviceFingerprint(
                vendorID: device.vendorID,
                productID: device.productID,
                serialNumber: device.serialNumber,
                locationID: device.locationID
            )
            map[fp] = device.name
        }
        return map
    }
}
