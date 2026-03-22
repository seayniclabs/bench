import Foundation

/// Firmware flashing interface that wraps common flashing tools
enum FirmwareBridge {

    /// Supported firmware flashing tools
    enum FlashTool: String, Sendable {
        case esptool
        case dfuUtil = "dfu-util"
        case avrdude
        case uf2
    }

    /// Result of a firmware flash operation
    struct FlashResult: Sendable {
        let success: Bool
        let command: String      // The command that was (or would be) run
        let output: String       // stdout + stderr combined
        let message: String      // Human-readable summary
    }

    // MARK: - Tool Detection

    /// Detect which flashing tool is needed based on device type and firmware extension
    static func detectTool(
        device: USBDevice?,
        firmwarePath: String
    ) -> FlashTool? {
        let ext = (firmwarePath as NSString).pathExtension.lowercased()

        // UF2 files always use UF2 copy
        if ext == "uf2" {
            return .uf2
        }

        // Check device identity from the database
        if let device = device {
            let vid = device.vendorID
            let pid = device.productID

            // ESP32/Espressif devices
            if [0x303A, 0x1A6E].contains(vid) {
                return .esptool
            }
            // Common ESP32 serial adapters (CH340, CP210x on ESP boards)
            if let known = DeviceDatabase.identify(vendorID: vid, productID: pid),
               known.notes.lowercased().contains("esp32") || known.notes.lowercased().contains("esp") {
                return .esptool
            }

            // STM32 DFU mode
            if vid == 0x0483 && pid == 0xDF11 {
                return .dfuUtil
            }
            // Generic DFU devices
            if device.deviceType == "microcontroller" && vid == 0x0483 {
                return .dfuUtil
            }

            // Arduino AVR boards
            if vid == 0x2341 {
                // Check if it's an AVR-based Arduino
                if let known = DeviceDatabase.identify(vendorID: vid, productID: pid),
                   known.notes.lowercased().contains("atmega") || known.notes.lowercased().contains("attiny") {
                    return .avrdude
                }
            }

            // RP2040 in bootloader mode
            if vid == 0x2E8A && pid == 0x0003 {
                return .uf2
            }
        }

        // Fall back to file extension
        switch ext {
        case "bin":
            return .esptool  // Most common for .bin firmware
        case "hex":
            return .avrdude
        case "elf":
            return .esptool
        default:
            return nil
        }
    }

    /// Check if a flashing tool is installed on the system
    static func isToolInstalled(_ tool: FlashTool) -> (installed: Bool, path: String?) {
        if tool == .uf2 {
            // UF2 doesn't need an external tool — just file copy
            return (true, nil)
        }

        let toolNames: [String]
        switch tool {
        case .esptool:
            toolNames = ["esptool.py", "esptool"]
        case .dfuUtil:
            toolNames = ["dfu-util"]
        case .avrdude:
            toolNames = ["avrdude"]
        case .uf2:
            return (true, nil)
        }

        for name in toolNames {
            if let path = whichTool(name) {
                return (true, path)
            }
        }

        return (false, nil)
    }

    // MARK: - Validation

    /// Validate the firmware file exists and has an appropriate extension
    static func validateFirmware(path: String) -> (valid: Bool, message: String) {
        let fm = FileManager.default

        guard fm.fileExists(atPath: path) else {
            return (false, "Firmware file not found: \(path)")
        }

        let ext = (path as NSString).pathExtension.lowercased()
        let validExtensions = ["bin", "hex", "uf2", "elf"]

        guard validExtensions.contains(ext) else {
            return (false, "Unsupported firmware extension '.\(ext)'. Expected: .bin, .hex, .uf2, or .elf")
        }

        // Check file is readable
        guard fm.isReadableFile(atPath: path) else {
            return (false, "Firmware file is not readable: \(path)")
        }

        return (true, "Firmware file validated: \(path)")
    }

    // MARK: - UF2 Volume Detection

    /// Find a mounted UF2 bootloader volume
    static func findUF2Volume() -> String? {
        let fm = FileManager.default
        let volumesPath = "/Volumes"

        guard let volumes = try? fm.contentsOfDirectory(atPath: volumesPath) else {
            return nil
        }

        for volume in volumes {
            let volumePath = "\(volumesPath)/\(volume)"
            let infoPath = "\(volumePath)/INFO_UF2.TXT"

            if fm.fileExists(atPath: infoPath) {
                return volumePath
            }
        }

        return nil
    }

    // MARK: - Flash Execution

    /// Build the flash command for the given tool and parameters
    static func buildCommand(
        tool: FlashTool,
        toolPath: String?,
        firmwarePath: String,
        port: String?,
        baud: Int?
    ) -> String? {
        switch tool {
        case .esptool:
            let executable = toolPath ?? "esptool.py"
            var args = [executable]
            if let port = port {
                args += ["--port", port]
            }
            if let baud = baud {
                args += ["--baud", String(baud)]
            }
            args += ["write_flash", "0x0", firmwarePath]
            return args.joined(separator: " ")

        case .dfuUtil:
            let executable = toolPath ?? "dfu-util"
            var args = [executable, "-D", firmwarePath]
            if let port = port {
                // dfu-util uses -S for serial/path
                args += ["-S", port]
            }
            return args.joined(separator: " ")

        case .avrdude:
            let executable = toolPath ?? "avrdude"
            let ext = (firmwarePath as NSString).pathExtension.lowercased()
            let format = ext == "hex" ? "i" : "r"  // Intel hex or raw
            var args = [executable]
            if let port = port {
                args += ["-P", port]
            }
            if let baud = baud {
                args += ["-b", String(baud)]
            }
            // Default to Arduino (ATmega328P) — user can override via tool params
            args += ["-p", "atmega328p", "-c", "arduino"]
            args += ["-U", "flash:w:\(firmwarePath):\(format)"]
            return args.joined(separator: " ")

        case .uf2:
            // UF2 is a file copy, not a command
            return nil
        }
    }

    /// Execute a firmware flash
    static func flash(
        tool: FlashTool,
        toolPath: String?,
        firmwarePath: String,
        port: String?,
        baud: Int?
    ) -> FlashResult {
        // UF2 is special — just copy the file
        if tool == .uf2 {
            return flashUF2(firmwarePath: firmwarePath)
        }

        guard let command = buildCommand(
            tool: tool,
            toolPath: toolPath,
            firmwarePath: firmwarePath,
            port: port,
            baud: baud
        ) else {
            return FlashResult(
                success: false,
                command: "(none)",
                output: "",
                message: "Failed to build flash command for \(tool.rawValue)"
            )
        }

        // Execute via /bin/sh
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", command]

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return FlashResult(
                success: false,
                command: command,
                output: "",
                message: "Failed to execute: \(error.localizedDescription)"
            )
        }

        let outData = stdout.fileHandleForReading.readDataToEndOfFile()
        let errData = stderr.fileHandleForReading.readDataToEndOfFile()
        let outStr = String(data: outData, encoding: .utf8) ?? ""
        let errStr = String(data: errData, encoding: .utf8) ?? ""
        let combined = [outStr, errStr].filter { !$0.isEmpty }.joined(separator: "\n")

        let success = process.terminationStatus == 0

        return FlashResult(
            success: success,
            command: command,
            output: combined,
            message: success
                ? "Firmware flashed successfully via \(tool.rawValue)"
                : "Flash failed (exit code \(process.terminationStatus))"
        )
    }

    // MARK: - Private

    private static func flashUF2(firmwarePath: String) -> FlashResult {
        guard let volumePath = findUF2Volume() else {
            return FlashResult(
                success: false,
                command: "cp \(firmwarePath) /Volumes/<UF2_VOLUME>/",
                output: "",
                message: "No UF2 bootloader volume found. Put the device in BOOTSEL/UF2 mode first."
            )
        }

        // Verify this is actually a UF2 volume
        let infoPath = "\(volumePath)/INFO_UF2.TXT"
        guard FileManager.default.fileExists(atPath: infoPath) else {
            return FlashResult(
                success: false,
                command: "cp \(firmwarePath) \(volumePath)/",
                output: "",
                message: "Volume '\(volumePath)' does not appear to be a UF2 bootloader volume."
            )
        }

        let fileName = (firmwarePath as NSString).lastPathComponent
        let destPath = "\(volumePath)/\(fileName)"
        let command = "cp \(firmwarePath) \(destPath)"

        do {
            try FileManager.default.copyItem(atPath: firmwarePath, toPath: destPath)
        } catch {
            return FlashResult(
                success: false,
                command: command,
                output: error.localizedDescription,
                message: "Failed to copy UF2 firmware to \(volumePath): \(error.localizedDescription)"
            )
        }

        return FlashResult(
            success: true,
            command: command,
            output: "Copied \(fileName) to \(volumePath)",
            message: "UF2 firmware copied to \(volumePath). Device will reboot automatically."
        )
    }

    private static func whichTool(_ name: String) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        process.arguments = [name]

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
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
