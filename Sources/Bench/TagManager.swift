import Foundation

/// Manages persistent user-defined aliases (tags) for USB devices.
/// Tags are stored in `~/.bench/device-tags.json` keyed by a stable device identifier.
enum TagManager {

    /// The directory for Bench config files
    private static var configDir: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".bench")
    }

    /// Path to the tags JSON file
    private static var tagsFile: URL {
        configDir.appendingPathComponent("device-tags.json")
    }

    // MARK: - Public API

    /// Build a stable key for a device: prefer serial number, fall back to VID:PID
    static func stableKey(for device: USBDevice) -> String {
        if !device.serialNumber.isEmpty {
            return device.serialNumber
        }
        return String(format: "0x%04X:0x%04X", device.vendorID, device.productID)
    }

    /// Set a tag for a device identifier
    static func setTag(identifier: String, tag: String) -> (success: Bool, message: String) {
        guard let device = IOKitBridge.findDevice(identifier: identifier) else {
            return (false, "No device found matching '\(identifier)'")
        }

        var tags = loadTags()
        let key = stableKey(for: device)
        tags[key] = TagEntry(tag: tag, deviceName: device.name, vendorID: device.vendorID, productID: device.productID)
        let saved = saveTags(tags)

        if saved {
            return (true, "Tagged '\(device.name)' (key: \(key)) as '\(tag)'")
        } else {
            return (false, "Failed to write tags file")
        }
    }

    /// Get the tag for a device identifier
    static func getTag(identifier: String) -> (success: Bool, message: String) {
        guard let device = IOKitBridge.findDevice(identifier: identifier) else {
            return (false, "No device found matching '\(identifier)'")
        }

        let tags = loadTags()
        let key = stableKey(for: device)

        if let entry = tags[key] {
            return (true, "Device '\(device.name)' (key: \(key)) is tagged as '\(entry.tag)'")
        } else {
            return (true, "Device '\(device.name)' (key: \(key)) has no tag")
        }
    }

    /// List all tagged devices
    static func listTags() -> (success: Bool, message: String) {
        let tags = loadTags()

        if tags.isEmpty {
            return (true, "No devices are tagged.")
        }

        var lines: [String] = ["Tagged devices (\(tags.count)):"]
        for (key, entry) in tags.sorted(by: { $0.key < $1.key }) {
            lines.append("")
            lines.append("  Key: \(key)")
            lines.append("    Tag: \(entry.tag)")
            lines.append("    Device: \(entry.deviceName)")
            lines.append("    VID:PID: \(String(format: "0x%04X:0x%04X", entry.vendorID, entry.productID))")
        }

        return (true, lines.joined(separator: "\n"))
    }

    /// Remove a tag by device identifier or tag key
    static func removeTag(identifier: String) -> (success: Bool, message: String) {
        var tags = loadTags()

        // First try to match against a connected device
        if let device = IOKitBridge.findDevice(identifier: identifier) {
            let key = stableKey(for: device)
            if tags.removeValue(forKey: key) != nil {
                let saved = saveTags(tags)
                if saved {
                    return (true, "Removed tag for '\(device.name)' (key: \(key))")
                } else {
                    return (false, "Failed to write tags file")
                }
            }
            return (false, "Device '\(device.name)' (key: \(key)) has no tag to remove")
        }

        // Fall back to matching against stored keys or tag values
        let id = identifier.lowercased()

        // Try exact key match
        if tags.removeValue(forKey: identifier) != nil {
            let saved = saveTags(tags)
            return saved
                ? (true, "Removed tag for key '\(identifier)'")
                : (false, "Failed to write tags file")
        }

        // Try matching by tag value
        if let matchKey = tags.first(where: { $0.value.tag.lowercased() == id })?.key {
            let entry = tags.removeValue(forKey: matchKey)!
            let saved = saveTags(tags)
            return saved
                ? (true, "Removed tag '\(entry.tag)' for key '\(matchKey)'")
                : (false, "Failed to write tags file")
        }

        return (false, "No tag found matching '\(identifier)'")
    }

    /// Look up a tag for a device by its stable key (used by other tools for enrichment)
    static func tagForDevice(_ device: USBDevice) -> String? {
        let tags = loadTags()
        let key = stableKey(for: device)
        return tags[key]?.tag
    }

    // MARK: - Persistence

    struct TagEntry: Codable {
        let tag: String
        let deviceName: String
        let vendorID: Int
        let productID: Int
    }

    private static func loadTags() -> [String: TagEntry] {
        guard let data = try? Data(contentsOf: tagsFile) else {
            return [:]
        }
        return (try? JSONDecoder().decode([String: TagEntry].self, from: data)) ?? [:]
    }

    private static func saveTags(_ tags: [String: TagEntry]) -> Bool {
        let fm = FileManager.default

        // Ensure ~/.bench/ exists
        if !fm.fileExists(atPath: configDir.path) {
            do {
                try fm.createDirectory(at: configDir, withIntermediateDirectories: true)
            } catch {
                return false
            }
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        guard let data = try? encoder.encode(tags) else {
            return false
        }

        do {
            try data.write(to: tagsFile, options: .atomic)
            return true
        } catch {
            return false
        }
    }
}
