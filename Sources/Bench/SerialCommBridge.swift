import Foundation
#if canImport(Darwin)
import Darwin
#endif

/// Manages open serial port connections and provides read/write/monitor operations
final class SerialCommBridge: @unchecked Sendable {

    static let shared = SerialCommBridge()

    /// An open serial connection
    struct Connection: Sendable {
        let fd: Int32
        let path: String
        let baudRate: Int
        let originalTermios: termios
    }

    private var connections: [String: Connection] = [:]
    private let lock = NSLock()

    private init() {}

    // MARK: - Open

    /// Open a serial port with the given configuration
    func open(
        path: String,
        baudRate: Int = 115200,
        dataBits: Int = 8,
        stopBits: Int = 1,
        parity: String = "none"
    ) -> (success: Bool, message: String) {
        lock.lock()
        defer { lock.unlock() }

        // Already open?
        if connections[path] != nil {
            return (false, "Port \(path) is already open. Close it first or use it directly.")
        }

        // Validate the path exists and is a character device
        var statBuf = stat()
        guard stat(path, &statBuf) == 0 else {
            let err = String(cString: strerror(errno))
            return (false, "Cannot access \(path): \(err)")
        }

        guard (statBuf.st_mode & S_IFMT) == S_IFCHR else {
            return (false, "\(path) is not a character device (not a serial port)")
        }

        // Open the port — O_RDWR | O_NOCTTY | O_NONBLOCK
        let fd = Darwin.open(path, O_RDWR | O_NOCTTY | O_NONBLOCK)
        guard fd >= 0 else {
            let err = String(cString: strerror(errno))
            return (false, "Failed to open \(path): \(err)")
        }

        // Save original termios for restore on close
        var originalTermios = termios()
        guard tcgetattr(fd, &originalTermios) == 0 else {
            let err = String(cString: strerror(errno))
            Darwin.close(fd)
            return (false, "Failed to get terminal attributes for \(path): \(err)")
        }

        // Configure raw mode
        var options = termios()
        tcgetattr(fd, &options)

        // Input flags: no parity checking, no stripping, no flow control
        options.c_iflag &= ~tcflag_t(IGNBRK | BRKINT | PARMRK | ISTRIP | INLCR | IGNCR | ICRNL | IXON | IXOFF | IXANY)

        // Output flags: no post-processing
        options.c_oflag &= ~tcflag_t(OPOST)

        // Local flags: raw mode (no echo, no canonical, no signals)
        options.c_lflag &= ~tcflag_t(ECHO | ECHONL | ICANON | ISIG | IEXTEN)

        // Control flags: clear size, parity
        options.c_cflag &= ~tcflag_t(CSIZE | PARENB | PARODD | CSTOPB)

        // Set data bits
        switch dataBits {
        case 5: options.c_cflag |= tcflag_t(CS5)
        case 6: options.c_cflag |= tcflag_t(CS6)
        case 7: options.c_cflag |= tcflag_t(CS7)
        default: options.c_cflag |= tcflag_t(CS8)
        }

        // Set parity
        switch parity.lowercased() {
        case "even":
            options.c_cflag |= tcflag_t(PARENB)
        case "odd":
            options.c_cflag |= tcflag_t(PARENB | PARODD)
        default:
            break // none — already cleared
        }

        // Set stop bits
        if stopBits == 2 {
            options.c_cflag |= tcflag_t(CSTOPB)
        }

        // Enable receiver, ignore modem control lines
        options.c_cflag |= tcflag_t(CLOCAL | CREAD)

        // Set baud rate
        let speed = baudConstant(for: baudRate)
        cfsetispeed(&options, speed)
        cfsetospeed(&options, speed)

        // VMIN = 0, VTIME = 1 (100ms timeout for reads)
        options.c_cc.16 = 0  // VMIN
        options.c_cc.17 = 1  // VTIME

        guard tcsetattr(fd, TCSANOW, &options) == 0 else {
            let err = String(cString: strerror(errno))
            Darwin.close(fd)
            return (false, "Failed to configure \(path): \(err)")
        }

        // Clear the non-blocking flag now that we're configured
        // (we want reads to use VMIN/VTIME, not return EAGAIN)
        var flags = fcntl(fd, F_GETFL)
        flags &= ~O_NONBLOCK
        _ = fcntl(fd, F_SETFL, flags)

        // Flush any stale data
        tcflush(fd, TCIOFLUSH)

        let conn = Connection(
            fd: fd,
            path: path,
            baudRate: baudRate,
            originalTermios: originalTermios
        )
        connections[path] = conn

        let parityStr = parity.lowercased() == "none" ? "N" : (parity.lowercased() == "even" ? "E" : "O")
        return (true, "Opened \(path) at \(baudRate) \(dataBits)\(parityStr)\(stopBits)")
    }

    // MARK: - Read

    /// Read available data from an open serial connection
    func read(path: String, timeoutSeconds: Double = 1.0) -> (success: Bool, message: String) {
        lock.lock()
        guard let conn = connections[path] else {
            lock.unlock()
            return (false, "Port \(path) is not open. Use serial_open first.")
        }
        lock.unlock()

        let fd = conn.fd
        var collected = Data()
        let deadline = Date().addingTimeInterval(timeoutSeconds)

        // Use select() for timeout-based reading
        while Date() < deadline {
            var readSet = fd_set()
            fdZero(&readSet)
            fdSet(fd, set: &readSet)

            var timeout = timeval()
            let remaining = deadline.timeIntervalSinceNow
            if remaining <= 0 { break }
            let usable = min(remaining, 0.1) // poll in 100ms chunks
            timeout.tv_sec = Int(usable)
            timeout.tv_usec = Int32((usable - Double(Int(usable))) * 1_000_000)

            let ready = select(fd + 1, &readSet, nil, nil, &timeout)
            if ready > 0 {
                var buf = [UInt8](repeating: 0, count: 4096)
                let n = Darwin.read(fd, &buf, buf.count)
                if n > 0 {
                    collected.append(contentsOf: buf[0..<n])
                } else if n == 0 {
                    break // EOF
                } else {
                    if errno == EAGAIN || errno == EWOULDBLOCK {
                        continue
                    }
                    let err = String(cString: strerror(errno))
                    return (false, "Read error on \(path): \(err)")
                }
            }
        }

        if collected.isEmpty {
            return (true, "No data available on \(path) (timeout: \(String(format: "%.1f", timeoutSeconds))s)")
        }

        let text = String(data: collected, encoding: .utf8)
            ?? collected.map { String(format: "%02X", $0) }.joined(separator: " ")
        return (true, text)
    }

    // MARK: - Write

    /// Write data to an open serial connection
    func write(path: String, data: String) -> (success: Bool, message: String) {
        lock.lock()
        guard let conn = connections[path] else {
            lock.unlock()
            return (false, "Port \(path) is not open. Use serial_open first.")
        }
        lock.unlock()

        let fd = conn.fd

        // Check if data looks like hex bytes (e.g. "0x01 0xFF" or "01FF")
        let bytes: [UInt8]
        if data.contains("0x") || isHexString(data) {
            bytes = parseHexBytes(data)
        } else {
            // Send as UTF-8 text, append \r\n if it doesn't end with a newline
            var text = data
            if !text.hasSuffix("\n") && !text.hasSuffix("\r") {
                text += "\r\n"
            }
            bytes = Array(text.utf8)
        }

        guard !bytes.isEmpty else {
            return (false, "No data to write")
        }

        let written = bytes.withUnsafeBufferPointer { buf -> Int in
            Darwin.write(fd, buf.baseAddress!, buf.count)
        }

        if written < 0 {
            let err = String(cString: strerror(errno))
            return (false, "Write error on \(path): \(err)")
        }

        return (true, "Wrote \(written) byte\(written == 1 ? "" : "s") to \(path)")
    }

    // MARK: - Close

    /// Close an open serial connection
    func close(path: String) -> (success: Bool, message: String) {
        lock.lock()
        defer { lock.unlock() }

        guard let conn = connections.removeValue(forKey: path) else {
            return (false, "Port \(path) is not open.")
        }

        // Restore original termios
        var original = conn.originalTermios
        tcsetattr(conn.fd, TCSANOW, &original)

        Darwin.close(conn.fd)
        return (true, "Closed \(path)")
    }

    // MARK: - Monitor

    /// Read from serial port for N seconds and return all output
    func monitor(path: String, seconds: Double = 5.0, autoOpen: Bool = false, baudRate: Int = 115200) -> (success: Bool, message: String) {
        // If port isn't open and autoOpen is true, open it
        lock.lock()
        let isOpen = connections[path] != nil
        lock.unlock()

        if !isOpen {
            if autoOpen {
                let result = open(path: path, baudRate: baudRate)
                if !result.success {
                    return result
                }
            } else {
                return (false, "Port \(path) is not open. Use serial_open first, or pass auto_open=true.")
            }
        }

        lock.lock()
        guard let conn = connections[path] else {
            lock.unlock()
            return (false, "Port \(path) is not open.")
        }
        lock.unlock()

        let fd = conn.fd
        var collected = Data()
        let deadline = Date().addingTimeInterval(seconds)

        // Flush any stale data before monitoring
        tcflush(fd, TCIFLUSH)

        while Date() < deadline {
            var readSet = fd_set()
            fdZero(&readSet)
            fdSet(fd, set: &readSet)

            var timeout = timeval()
            let remaining = deadline.timeIntervalSinceNow
            if remaining <= 0 { break }
            let usable = min(remaining, 0.25)
            timeout.tv_sec = Int(usable)
            timeout.tv_usec = Int32((usable - Double(Int(usable))) * 1_000_000)

            let ready = select(fd + 1, &readSet, nil, nil, &timeout)
            if ready > 0 {
                var buf = [UInt8](repeating: 0, count: 4096)
                let n = Darwin.read(fd, &buf, buf.count)
                if n > 0 {
                    collected.append(contentsOf: buf[0..<n])
                } else if n < 0 && errno != EAGAIN && errno != EWOULDBLOCK {
                    let err = String(cString: strerror(errno))
                    return (false, "Read error during monitor on \(path): \(err)")
                }
            }
        }

        if collected.isEmpty {
            return (true, "No output received from \(path) in \(String(format: "%.1f", seconds))s")
        }

        let text = String(data: collected, encoding: .utf8)
            ?? collected.map { String(format: "%02X", $0) }.joined(separator: " ")

        let header = "Serial monitor on \(path) (\(String(format: "%.1f", seconds))s, \(collected.count) bytes):\n"
        return (true, header + text)
    }

    /// List currently open connections
    func listOpen() -> [(path: String, baudRate: Int)] {
        lock.lock()
        defer { lock.unlock() }
        return connections.map { ($0.key, $0.value.baudRate) }
    }

    // MARK: - Helpers

    private func baudConstant(for rate: Int) -> speed_t {
        switch rate {
        case 300:     return speed_t(B300)
        case 600:     return speed_t(B600)
        case 1200:    return speed_t(B1200)
        case 2400:    return speed_t(B2400)
        case 4800:    return speed_t(B4800)
        case 9600:    return speed_t(B9600)
        case 19200:   return speed_t(B19200)
        case 38400:   return speed_t(B38400)
        case 57600:   return speed_t(B57600)
        case 115200:  return speed_t(B115200)
        case 230400:  return speed_t(B230400)
        default:      return speed_t(B115200)
        }
    }

    private func isHexString(_ s: String) -> Bool {
        let cleaned = s.replacingOccurrences(of: " ", with: "")
        return cleaned.count >= 2 && cleaned.count % 2 == 0
            && cleaned.allSatisfy { $0.isHexDigit }
    }

    private func parseHexBytes(_ s: String) -> [UInt8] {
        // Handle "0x01 0xFF 0x00" or "01FF00" formats
        let tokens = s.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
        var bytes: [UInt8] = []

        for token in tokens {
            let cleaned = token.hasPrefix("0x") || token.hasPrefix("0X")
                ? String(token.dropFirst(2))
                : token

            // Parse pairs of hex chars
            var idx = cleaned.startIndex
            while idx < cleaned.endIndex {
                let next = cleaned.index(idx, offsetBy: 2, limitedBy: cleaned.endIndex) ?? cleaned.endIndex
                let hexPair = String(cleaned[idx..<next])
                if let byte = UInt8(hexPair, radix: 16) {
                    bytes.append(byte)
                }
                idx = next
            }
        }

        return bytes
    }

    // MARK: - fd_set helpers (Swift doesn't expose FD_ZERO/FD_SET macros)

    private func fdZero(_ set: inout fd_set) {
        set = fd_set()
    }

    private func fdSet(_ fd: Int32, set: inout fd_set) {
        let intOffset = Int(fd) / (MemoryLayout<Int32>.size * 8)
        let bitOffset = Int(fd) % (MemoryLayout<Int32>.size * 8)
        let mask = Int32(1 << bitOffset)
        withUnsafeMutablePointer(to: &set) { ptr in
            let rawPtr = UnsafeMutableRawPointer(ptr)
            let arrayPtr = rawPtr.assumingMemoryBound(to: Int32.self)
            arrayPtr[intOffset] |= mask
        }
    }
}
