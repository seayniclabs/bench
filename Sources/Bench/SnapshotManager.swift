import Foundation

/// Manages named USB state snapshots in memory for comparison.
final class SnapshotManager: @unchecked Sendable {

    static let shared = SnapshotManager()

    /// A captured USB state snapshot
    struct Snapshot: Sendable {
        let name: String
        let timestamp: Date
        let devices: [DeviceEntry]
    }

    /// A device entry within a snapshot
    struct DeviceEntry: Sendable, Equatable {
        let name: String
        let vendorID: Int
        let productID: Int
        let vendorName: String
        let serialNumber: String
        let deviceType: String
        let usbSpeed: String
        let locationID: String
        let busPowerMA: Int

        static func from(_ device: USBDevice) -> DeviceEntry {
            DeviceEntry(
                name: device.name,
                vendorID: device.vendorID,
                productID: device.productID,
                vendorName: device.vendorName,
                serialNumber: device.serialNumber,
                deviceType: device.deviceType,
                usbSpeed: device.usbSpeed,
                locationID: device.locationID,
                busPowerMA: device.busPowerMA
            )
        }
    }

    /// Result of comparing two snapshots
    struct CompareResult: Sendable {
        let fromName: String
        let toName: String
        let added: [DeviceEntry]
        let removed: [DeviceEntry]
        let changed: [(old: DeviceEntry, new: DeviceEntry)]
    }

    private let lock = NSLock()
    private var snapshots: [String: Snapshot] = [:]

    private init() {}

    /// Capture current USB state into a named snapshot
    func capture(name: String?) -> Snapshot {
        lock.lock()
        defer { lock.unlock() }

        let snapshotName = name ?? timestampName()
        let devices = IOKitBridge.enumerateDevices(includeInternal: true)
        let entries = devices.map { DeviceEntry.from($0) }

        let snapshot = Snapshot(
            name: snapshotName,
            timestamp: Date(),
            devices: entries
        )

        snapshots[snapshotName] = snapshot
        return snapshot
    }

    /// List all saved snapshots (names and timestamps)
    func list() -> [(name: String, timestamp: Date, deviceCount: Int)] {
        lock.lock()
        defer { lock.unlock() }

        return snapshots.values
            .sorted { $0.timestamp < $1.timestamp }
            .map { (name: $0.name, timestamp: $0.timestamp, deviceCount: $0.devices.count) }
    }

    /// Compare two snapshots, or a snapshot to current state
    func compare(name: String, compareTo: String?) -> CompareResult? {
        lock.lock()
        defer { lock.unlock() }

        guard let fromSnapshot = snapshots[name] else { return nil }

        let toEntries: [DeviceEntry]
        let toName: String

        if let otherName = compareTo {
            guard let toSnapshot = snapshots[otherName] else { return nil }
            toEntries = toSnapshot.devices
            toName = otherName
        } else {
            // Compare to current state
            let devices = IOKitBridge.enumerateDevices(includeInternal: true)
            toEntries = devices.map { DeviceEntry.from($0) }
            toName = "current"
        }

        return diff(from: fromSnapshot.devices, fromName: name, to: toEntries, toName: toName)
    }

    /// Delete a snapshot
    func delete(name: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }

        return snapshots.removeValue(forKey: name) != nil
    }

    // MARK: - Private

    private func timestampName() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        return formatter.string(from: Date())
    }

    /// Diff two device lists using locationID as the primary key
    private func diff(
        from: [DeviceEntry], fromName: String,
        to: [DeviceEntry], toName: String
    ) -> CompareResult {
        let fromByLocation = Dictionary(from.map { ($0.locationID, $0) }, uniquingKeysWith: { first, _ in first })
        let toByLocation = Dictionary(to.map { ($0.locationID, $0) }, uniquingKeysWith: { first, _ in first })

        let fromKeys = Set(fromByLocation.keys)
        let toKeys = Set(toByLocation.keys)

        let added = toKeys.subtracting(fromKeys).compactMap { toByLocation[$0] }
        let removed = fromKeys.subtracting(toKeys).compactMap { fromByLocation[$0] }

        var changed: [(old: DeviceEntry, new: DeviceEntry)] = []
        for key in fromKeys.intersection(toKeys) {
            let old = fromByLocation[key]!
            let new = toByLocation[key]!
            if old != new {
                changed.append((old: old, new: new))
            }
        }

        return CompareResult(
            fromName: fromName,
            toName: toName,
            added: added,
            removed: removed,
            changed: changed
        )
    }
}
