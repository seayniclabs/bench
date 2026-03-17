import Foundation

/// Storage volume information from diskutil
struct VolumeInfo: Sendable {
    let bsdName: String        // e.g. "disk4s1"
    let mountPoint: String?    // e.g. "/Volumes/T7"
    let volumeName: String?    // e.g. "T7"
    let filesystemType: String? // e.g. "APFS", "ExFAT"
    let totalSizeBytes: Int64
    let freeSizeBytes: Int64
}

/// Bridge to diskutil for storage device information
enum DiskUtilBridge {

    /// Get volume information for all external/removable disks
    static func externalVolumes() -> [VolumeInfo] {
        guard let plistData = runDiskutil(["list", "-plist", "external"]) else {
            return []
        }

        guard let plist = try? PropertyListSerialization.propertyList(
            from: plistData, format: nil
        ) as? [String: Any] else {
            return []
        }

        guard let disksArray = plist["AllDisksAndPartitions"] as? [[String: Any]] else {
            return []
        }

        var volumes: [VolumeInfo] = []

        for disk in disksArray {
            // Check partitions
            if let partitions = disk["Partitions"] as? [[String: Any]] {
                for partition in partitions {
                    if let vol = volumeInfoFromPartition(partition) {
                        volumes.append(vol)
                    }
                }
            }

            // Also check the disk itself (for non-partitioned media like some USB drives)
            if let vol = volumeInfoFromPartition(disk) {
                volumes.append(vol)
            }
        }

        return volumes
    }

    /// Get detailed info for a specific BSD device (e.g. "disk4s1")
    static func volumeDetail(bsdName: String) -> VolumeInfo? {
        guard let plistData = runDiskutil(["info", "-plist", bsdName]) else {
            return nil
        }

        guard let plist = try? PropertyListSerialization.propertyList(
            from: plistData, format: nil
        ) as? [String: Any] else {
            return nil
        }

        let mountPoint = plist["MountPoint"] as? String
        let volumeName = plist["VolumeName"] as? String
        let fsType = plist["FilesystemType"] as? String
        let totalSize = plist["TotalSize"] as? Int64 ?? plist["Size"] as? Int64 ?? 0
        let freeSpace = plist["FreeSpace"] as? Int64 ?? plist["APFSContainerFree"] as? Int64 ?? 0

        return VolumeInfo(
            bsdName: bsdName,
            mountPoint: (mountPoint?.isEmpty ?? true) ? nil : mountPoint,
            volumeName: (volumeName?.isEmpty ?? true) ? nil : volumeName,
            filesystemType: fsType,
            totalSizeBytes: totalSize,
            freeSizeBytes: freeSpace
        )
    }

    /// Eject a disk by BSD name, mount point, or volume name
    static func eject(identifier: String, force: Bool = false) -> (success: Bool, message: String) {
        let args: [String]
        if force {
            args = ["unmountDisk", "force", identifier]
        } else {
            args = ["eject", identifier]
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/diskutil")
        process.arguments = args

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return (false, "Failed to run diskutil: \(error.localizedDescription)")
        }

        let outData = stdout.fileHandleForReading.readDataToEndOfFile()
        let errData = stderr.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: outData, encoding: .utf8) ?? ""
        let errorOutput = String(data: errData, encoding: .utf8) ?? ""

        if process.terminationStatus == 0 {
            return (true, output.trimmingCharacters(in: .whitespacesAndNewlines))
        } else {
            let msg = errorOutput.isEmpty ? output : errorOutput
            return (false, msg.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }

    // MARK: - Private

    private static func volumeInfoFromPartition(_ partition: [String: Any]) -> VolumeInfo? {
        guard let bsdName = partition["DeviceIdentifier"] as? String else { return nil }

        // Skip container/scheme entries
        let content = partition["Content"] as? String ?? ""
        if content == "GUID_partition_scheme" || content == "Apple_APFS" { return nil }

        let mountPoint = partition["MountPoint"] as? String
        let volumeName = partition["VolumeName"] as? String
        let size = partition["Size"] as? Int64 ?? 0

        // Skip entries with no mount point and no volume name (partition maps, etc.)
        if (mountPoint?.isEmpty ?? true) && (volumeName?.isEmpty ?? true) && size == 0 {
            return nil
        }

        return VolumeInfo(
            bsdName: bsdName,
            mountPoint: (mountPoint?.isEmpty ?? true) ? nil : mountPoint,
            volumeName: (volumeName?.isEmpty ?? true) ? nil : volumeName,
            filesystemType: content.isEmpty ? nil : content,
            totalSizeBytes: size,
            freeSizeBytes: 0 // Need volumeDetail() for free space
        )
    }

    private static func runDiskutil(_ args: [String]) -> Data? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/diskutil")
        process.arguments = args

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return nil
        }

        guard process.terminationStatus == 0 else { return nil }
        return pipe.fileHandleForReading.readDataToEndOfFile()
    }
}
