import Foundation

/// Known maker boards and USB devices, identified by vendor ID + product ID pairs.
struct KnownDevice: Sendable {
    let name: String
    let vendor: String
    let category: String
    let notes: String
}

/// Maps (vendorID, productID) to known device info.
/// Vendor/product IDs are UInt16 values from the USB descriptor.
enum DeviceDatabase {

    /// Lookup by exact vendor + product ID match
    static func identify(vendorID: Int, productID: Int) -> KnownDevice? {
        return devices[DeviceKey(vendorID: vendorID, productID: productID)]
    }

    /// Lookup by vendor ID only — returns the vendor name if known
    static func vendorName(for vendorID: Int) -> String? {
        return vendors[vendorID]
    }

    // MARK: - Internal

    private struct DeviceKey: Hashable {
        let vendorID: Int
        let productID: Int
    }

    // -- Known vendors --

    private static let vendors: [Int: String] = [
        0x2341: "Arduino",
        0x1A86: "QinHeng Electronics",       // CH340/CH341
        0x10C4: "Silicon Labs",               // CP210x
        0x0403: "FTDI",                       // FT232, FT2232
        0x2E8A: "Raspberry Pi",
        0x239A: "Adafruit",
        0x1B4F: "SparkFun",
        0x16C0: "Teensy (PJRC)",
        0x0483: "STMicroelectronics",
        0x1A6E: "Espressif",
        0x303A: "Espressif (USB-native)",
        0x04B4: "Cypress Semiconductor",
        0x067B: "Prolific",                   // PL2303
        0x1366: "SEGGER",                     // J-Link
        0x0D28: "Arm/Mbed",
        0x04E8: "Samsung",
        0x0781: "SanDisk",
        0x0951: "Kingston",
        0x058F: "Alcor Micro",                // USB card readers
        0x05AC: "Apple",
    ]

    // -- Known devices (vendor + product) --

    private static let devices: [DeviceKey: KnownDevice] = [
        // Arduino boards
        DeviceKey(vendorID: 0x2341, productID: 0x0043): KnownDevice(
            name: "Arduino Uno R3", vendor: "Arduino",
            category: "microcontroller",
            notes: "ATmega328P. Uses CH340 or ATmega16U2 for USB-serial."
        ),
        DeviceKey(vendorID: 0x2341, productID: 0x0001): KnownDevice(
            name: "Arduino Uno", vendor: "Arduino",
            category: "microcontroller",
            notes: "ATmega328P with ATmega8U2 USB-serial."
        ),
        DeviceKey(vendorID: 0x2341, productID: 0x0010): KnownDevice(
            name: "Arduino Mega 2560", vendor: "Arduino",
            category: "microcontroller",
            notes: "ATmega2560. 54 digital I/O pins, 16 analog inputs."
        ),
        DeviceKey(vendorID: 0x2341, productID: 0x0042): KnownDevice(
            name: "Arduino Mega 2560 R3", vendor: "Arduino",
            category: "microcontroller",
            notes: "ATmega2560 with ATmega16U2 USB-serial."
        ),
        DeviceKey(vendorID: 0x2341, productID: 0x8036): KnownDevice(
            name: "Arduino Leonardo", vendor: "Arduino",
            category: "microcontroller",
            notes: "ATmega32U4. Native USB — no separate USB-serial chip."
        ),
        DeviceKey(vendorID: 0x2341, productID: 0x8037): KnownDevice(
            name: "Arduino Micro", vendor: "Arduino",
            category: "microcontroller",
            notes: "ATmega32U4. Compact form factor with native USB."
        ),
        DeviceKey(vendorID: 0x2341, productID: 0x003D): KnownDevice(
            name: "Arduino Due (Programming Port)", vendor: "Arduino",
            category: "microcontroller",
            notes: "ARM Cortex-M3 (SAM3X8E). 32-bit, 84 MHz."
        ),
        DeviceKey(vendorID: 0x2341, productID: 0x003E): KnownDevice(
            name: "Arduino Due (Native USB Port)", vendor: "Arduino",
            category: "microcontroller",
            notes: "ARM Cortex-M3. Native USB port for host/device mode."
        ),
        DeviceKey(vendorID: 0x2341, productID: 0x0058): KnownDevice(
            name: "Arduino Nano Every", vendor: "Arduino",
            category: "microcontroller",
            notes: "ATMega4809. Small form factor, 5V logic."
        ),
        DeviceKey(vendorID: 0x2341, productID: 0x0070): KnownDevice(
            name: "Arduino Nano ESP32", vendor: "Arduino",
            category: "microcontroller",
            notes: "ESP32-S3 in Nano form factor. Wi-Fi + BLE."
        ),
        DeviceKey(vendorID: 0x2341, productID: 0x0069): KnownDevice(
            name: "Arduino Nano RP2040 Connect", vendor: "Arduino",
            category: "microcontroller",
            notes: "RP2040 dual-core. Wi-Fi + BLE via Nina W102 module."
        ),

        // Raspberry Pi
        DeviceKey(vendorID: 0x2E8A, productID: 0x0005): KnownDevice(
            name: "Raspberry Pi Pico", vendor: "Raspberry Pi",
            category: "microcontroller",
            notes: "RP2040 dual-core ARM Cortex-M0+. MicroPython or C/C++."
        ),
        DeviceKey(vendorID: 0x2E8A, productID: 0x000A): KnownDevice(
            name: "Raspberry Pi Pico W", vendor: "Raspberry Pi",
            category: "microcontroller",
            notes: "RP2040 with CYW43439 Wi-Fi + BLE."
        ),
        DeviceKey(vendorID: 0x2E8A, productID: 0x0003): KnownDevice(
            name: "Raspberry Pi RP2040 (Boot Mode)", vendor: "Raspberry Pi",
            category: "microcontroller",
            notes: "RP2040 in BOOTSEL/UF2 mode. Ready for firmware flash."
        ),

        // ESP32 / Espressif (often via USB-serial chips, but native USB variants exist)
        DeviceKey(vendorID: 0x303A, productID: 0x1001): KnownDevice(
            name: "ESP32-S2", vendor: "Espressif",
            category: "microcontroller",
            notes: "Single-core Xtensa LX7. Native USB. Wi-Fi only (no BLE)."
        ),
        DeviceKey(vendorID: 0x303A, productID: 0x0002): KnownDevice(
            name: "ESP32-S3", vendor: "Espressif",
            category: "microcontroller",
            notes: "Dual-core Xtensa LX7. Native USB OTG. Wi-Fi + BLE."
        ),
        DeviceKey(vendorID: 0x303A, productID: 0x0042): KnownDevice(
            name: "ESP32-C3", vendor: "Espressif",
            category: "microcontroller",
            notes: "RISC-V single core. Wi-Fi + BLE 5.0."
        ),

        // USB-serial adapters (these are what most ESP32/Arduino clones use)
        DeviceKey(vendorID: 0x1A86, productID: 0x7523): KnownDevice(
            name: "CH340 USB-Serial Adapter", vendor: "QinHeng Electronics",
            category: "serial_adapter",
            notes: "Common on Arduino clones and ESP32 dev boards. Requires CH340 driver on some systems."
        ),
        DeviceKey(vendorID: 0x1A86, productID: 0x55D4): KnownDevice(
            name: "CH9102 USB-Serial Adapter", vendor: "QinHeng Electronics",
            category: "serial_adapter",
            notes: "Newer CH340 variant. Common on ESP32-S2/S3 dev boards."
        ),
        DeviceKey(vendorID: 0x10C4, productID: 0xEA60): KnownDevice(
            name: "CP2102 USB-Serial Adapter", vendor: "Silicon Labs",
            category: "serial_adapter",
            notes: "Common on ESP32 DevKit boards. macOS driver usually built-in."
        ),
        DeviceKey(vendorID: 0x10C4, productID: 0xEA70): KnownDevice(
            name: "CP2105 Dual USB-Serial Adapter", vendor: "Silicon Labs",
            category: "serial_adapter",
            notes: "Dual-channel USB-serial bridge."
        ),
        DeviceKey(vendorID: 0x0403, productID: 0x6001): KnownDevice(
            name: "FTDI FT232R USB-Serial", vendor: "FTDI",
            category: "serial_adapter",
            notes: "Industry-standard USB-serial. Used in many Arduino boards and breakouts."
        ),
        DeviceKey(vendorID: 0x0403, productID: 0x6010): KnownDevice(
            name: "FTDI FT2232 Dual USB-Serial", vendor: "FTDI",
            category: "serial_adapter",
            notes: "Dual-channel. Often used for JTAG + serial on dev boards."
        ),
        DeviceKey(vendorID: 0x0403, productID: 0x6014): KnownDevice(
            name: "FTDI FT232H", vendor: "FTDI",
            category: "serial_adapter",
            notes: "Multi-protocol: UART, SPI, I2C, JTAG. Popular for hardware debugging."
        ),
        DeviceKey(vendorID: 0x067B, productID: 0x2303): KnownDevice(
            name: "Prolific PL2303 USB-Serial", vendor: "Prolific",
            category: "serial_adapter",
            notes: "Older USB-serial chip. Driver support varies by macOS version."
        ),

        // Adafruit
        DeviceKey(vendorID: 0x239A, productID: 0x8022): KnownDevice(
            name: "Adafruit Feather M0", vendor: "Adafruit",
            category: "microcontroller",
            notes: "ATSAMD21 ARM Cortex-M0+. CircuitPython compatible."
        ),
        DeviceKey(vendorID: 0x239A, productID: 0x80CB): KnownDevice(
            name: "Adafruit Feather RP2040", vendor: "Adafruit",
            category: "microcontroller",
            notes: "RP2040 in Feather form factor. CircuitPython compatible."
        ),
        DeviceKey(vendorID: 0x239A, productID: 0x8018): KnownDevice(
            name: "Adafruit Circuit Playground Express", vendor: "Adafruit",
            category: "microcontroller",
            notes: "ATSAMD21 with onboard sensors, LEDs, speaker. Great for learning."
        ),
        DeviceKey(vendorID: 0x239A, productID: 0x800B): KnownDevice(
            name: "Adafruit Trinket M0", vendor: "Adafruit",
            category: "microcontroller",
            notes: "Tiny ATSAMD21 board. CircuitPython or Arduino."
        ),

        // SparkFun
        DeviceKey(vendorID: 0x1B4F, productID: 0x9206): KnownDevice(
            name: "SparkFun Pro Micro", vendor: "SparkFun",
            category: "microcontroller",
            notes: "ATmega32U4. Popular for custom keyboards and small projects."
        ),

        // Teensy
        DeviceKey(vendorID: 0x16C0, productID: 0x0483): KnownDevice(
            name: "Teensy (Serial)", vendor: "PJRC",
            category: "microcontroller",
            notes: "Teensy board in USB Serial mode. High-performance ARM Cortex-M."
        ),
        DeviceKey(vendorID: 0x16C0, productID: 0x0478): KnownDevice(
            name: "Teensy (HalfKay Bootloader)", vendor: "PJRC",
            category: "microcontroller",
            notes: "Teensy in bootloader mode. Ready for firmware upload via Teensy Loader."
        ),

        // STM32
        DeviceKey(vendorID: 0x0483, productID: 0x374B): KnownDevice(
            name: "STM32 Nucleo (ST-Link V2-1)", vendor: "STMicroelectronics",
            category: "microcontroller",
            notes: "STM32 Nucleo board with onboard ST-Link debugger."
        ),
        DeviceKey(vendorID: 0x0483, productID: 0x3748): KnownDevice(
            name: "ST-Link V2", vendor: "STMicroelectronics",
            category: "debugger",
            notes: "STM32 programmer/debugger. SWD and JTAG."
        ),
        DeviceKey(vendorID: 0x0483, productID: 0xDF11): KnownDevice(
            name: "STM32 DFU Bootloader", vendor: "STMicroelectronics",
            category: "microcontroller",
            notes: "STM32 in DFU (Device Firmware Upgrade) mode."
        ),

        // Debug probes
        DeviceKey(vendorID: 0x1366, productID: 0x0101): KnownDevice(
            name: "SEGGER J-Link", vendor: "SEGGER",
            category: "debugger",
            notes: "Professional ARM debugger/programmer. JTAG and SWD."
        ),
        DeviceKey(vendorID: 0x0D28, productID: 0x0204): KnownDevice(
            name: "Arm Mbed / DAPLink", vendor: "Arm",
            category: "debugger",
            notes: "CMSIS-DAP debug probe. Common on mbed-enabled boards."
        ),
    ]
}
