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
        0x1A86: "QinHeng Electronics",       // CH340/CH341/CH9102
        0x10C4: "Silicon Labs",               // CP210x
        0x0403: "FTDI",                       // FT232, FT2232, FT4232
        0x2E8A: "Raspberry Pi",
        0x239A: "Adafruit",
        0x1B4F: "SparkFun",
        0x16C0: "Teensy (PJRC)",
        0x0483: "STMicroelectronics",
        0x1A6E: "Espressif",
        0x303A: "Espressif (USB-native)",
        0x04B4: "Cypress/Infineon",
        0x067B: "Prolific",                   // PL2303
        0x1366: "SEGGER",                     // J-Link
        0x0D28: "Arm/Mbed",
        0x04E8: "Samsung",
        0x0781: "SanDisk",
        0x0951: "Kingston",
        0x058F: "Alcor Micro",                // USB card readers
        0x05AC: "Apple",
        0x1D6B: "Linux Foundation",           // USB gadget devices
        0x1D50: "OpenMoko",                   // Open-source hardware
        0x2B04: "Particle",
        0x2886: "Seeed Studio",
        0x046D: "Logitech",
        0x1050: "Yubico",
        0x1B1C: "Corsair",
        0x0FD9: "Elgato",
        0x21A9: "Saleae",
        0x1781: "Multiple (USBtinyISP)",
        0x03EB: "Atmel/Microchip",
        0x04D8: "Microchip",
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
            name: "ESP32-S2/S3 (JTAG)", vendor: "Espressif",
            category: "microcontroller",
            notes: "USB JTAG/serial debug unit. PID 0x1001 is shared by ESP32-S2 and ESP32-S3 in JTAG mode — use chip_detect to identify the exact variant."
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
        DeviceKey(vendorID: 0x1366, productID: 0x0105): KnownDevice(
            name: "SEGGER J-Link Plus", vendor: "SEGGER",
            category: "debugger",
            notes: "J-Link Plus variant. Higher performance trace and debug."
        ),
        DeviceKey(vendorID: 0x0D28, productID: 0x0204): KnownDevice(
            name: "Arm Mbed / DAPLink", vendor: "Arm",
            category: "debugger",
            notes: "CMSIS-DAP debug probe. Common on mbed-enabled boards and BBC micro:bit."
        ),
        DeviceKey(vendorID: 0x1D50, productID: 0x6018): KnownDevice(
            name: "Black Magic Probe", vendor: "1BitSquared",
            category: "debugger",
            notes: "Open-source JTAG/SWD debug probe. GDB server built into firmware."
        ),

        // Arduino — additional boards
        DeviceKey(vendorID: 0x2341, productID: 0x8057): KnownDevice(
            name: "Arduino Nano 33 IoT", vendor: "Arduino",
            category: "microcontroller",
            notes: "ATSAMD21 + u-blox NINA-W102 (ESP32). Wi-Fi + BLE."
        ),
        DeviceKey(vendorID: 0x2341, productID: 0x805A): KnownDevice(
            name: "Arduino Nano 33 BLE", vendor: "Arduino",
            category: "microcontroller",
            notes: "nRF52840. Bluetooth 5.0, 9-axis IMU onboard."
        ),
        DeviceKey(vendorID: 0x2341, productID: 0x005E): KnownDevice(
            name: "Arduino Nano RP2040 Connect (alt)", vendor: "Arduino",
            category: "microcontroller",
            notes: "RP2040 variant. Alternate PID from some board revisions."
        ),
        DeviceKey(vendorID: 0x2341, productID: 0x025B): KnownDevice(
            name: "Arduino Portenta H7", vendor: "Arduino",
            category: "microcontroller",
            notes: "Dual-core STM32H747 (Cortex-M7 + M4). Industrial IoT."
        ),
        DeviceKey(vendorID: 0x2341, productID: 0x0266): KnownDevice(
            name: "Arduino Giga R1 WiFi", vendor: "Arduino",
            category: "microcontroller",
            notes: "STM32H747 dual-core. Wi-Fi + BLE, camera connector, 76-pin layout."
        ),

        // Raspberry Pi — additional
        DeviceKey(vendorID: 0x1D6B, productID: 0x0104): KnownDevice(
            name: "Linux USB Gadget (Composite)", vendor: "Linux Foundation",
            category: "microcontroller",
            notes: "USB gadget mode device. Common on Raspberry Pi Zero/Zero W in OTG mode."
        ),
        DeviceKey(vendorID: 0x2E8A, productID: 0x000C): KnownDevice(
            name: "Raspberry Pi Debug Probe", vendor: "Raspberry Pi",
            category: "debugger",
            notes: "Official RPi debug probe. SWD + UART for Pico and other ARM targets."
        ),

        // ESP32 — additional variants
        DeviceKey(vendorID: 0x303A, productID: 0x1003): KnownDevice(
            name: "ESP32-C3 (USB-native)", vendor: "Espressif",
            category: "microcontroller",
            notes: "RISC-V single core with native USB-JTAG. Wi-Fi + BLE 5.0."
        ),
        DeviceKey(vendorID: 0x303A, productID: 0x1004): KnownDevice(
            name: "ESP32-C6", vendor: "Espressif",
            category: "microcontroller",
            notes: "RISC-V. Wi-Fi 6, BLE 5.0, 802.15.4 (Thread/Zigbee)."
        ),
        DeviceKey(vendorID: 0x303A, productID: 0x1002): KnownDevice(
            name: "ESP32-H2", vendor: "Espressif",
            category: "microcontroller",
            notes: "RISC-V. 802.15.4 (Thread/Zigbee) + BLE 5.0. No Wi-Fi."
        ),

        // Adafruit — additional boards
        DeviceKey(vendorID: 0x239A, productID: 0x8031): KnownDevice(
            name: "Adafruit Feather M4 Express", vendor: "Adafruit",
            category: "microcontroller",
            notes: "ATSAMD51 Cortex-M4F at 120 MHz. CircuitPython compatible."
        ),
        DeviceKey(vendorID: 0x239A, productID: 0x80F4): KnownDevice(
            name: "Adafruit Feather RP2040 (alt PID)", vendor: "Adafruit",
            category: "microcontroller",
            notes: "RP2040 Feather variant. Alternate PID from some revisions."
        ),
        DeviceKey(vendorID: 0x239A, productID: 0x802B): KnownDevice(
            name: "Adafruit ItsyBitsy M4 Express", vendor: "Adafruit",
            category: "microcontroller",
            notes: "ATSAMD51 Cortex-M4F. Compact board with CircuitPython support."
        ),
        DeviceKey(vendorID: 0x239A, productID: 0x801E): KnownDevice(
            name: "Adafruit Trinket M0 (alt PID)", vendor: "Adafruit",
            category: "microcontroller",
            notes: "Tiny ATSAMD21 board. Alternate PID for some revisions."
        ),
        DeviceKey(vendorID: 0x239A, productID: 0x8060): KnownDevice(
            name: "Adafruit QT Py", vendor: "Adafruit",
            category: "microcontroller",
            notes: "ATSAMD21 in tiny form factor with STEMMA QT connector."
        ),
        DeviceKey(vendorID: 0x239A, productID: 0x8108): KnownDevice(
            name: "Adafruit MacroPad RP2040", vendor: "Adafruit",
            category: "microcontroller",
            notes: "RP2040 with 3x4 mechanical key switches, rotary encoder, OLED."
        ),
        DeviceKey(vendorID: 0x239A, productID: 0x8105): KnownDevice(
            name: "Adafruit KB2040", vendor: "Adafruit",
            category: "microcontroller",
            notes: "RP2040 in Arduino Pro Micro form factor. Designed for keyboards."
        ),

        // SparkFun — additional boards
        DeviceKey(vendorID: 0x1B4F, productID: 0x0026): KnownDevice(
            name: "SparkFun Thing Plus", vendor: "SparkFun",
            category: "microcontroller",
            notes: "Feather-compatible form factor. Various MCU variants available."
        ),
        DeviceKey(vendorID: 0x1B4F, productID: 0x0029): KnownDevice(
            name: "SparkFun MicroMod", vendor: "SparkFun",
            category: "microcontroller",
            notes: "Modular processor system. Swap MCU via M.2 connector."
        ),
        DeviceKey(vendorID: 0x1B4F, productID: 0x0036): KnownDevice(
            name: "SparkFun RedBoard", vendor: "SparkFun",
            category: "microcontroller",
            notes: "Arduino Uno-compatible board with CH340 USB-serial."
        ),

        // STM32 — additional
        DeviceKey(vendorID: 0x0483, productID: 0x374E): KnownDevice(
            name: "ST-Link V3", vendor: "STMicroelectronics",
            category: "debugger",
            notes: "Latest ST-Link generation. SWD, JTAG, virtual COM port, bridge."
        ),

        // Teensy — additional
        DeviceKey(vendorID: 0x16C0, productID: 0x0486): KnownDevice(
            name: "Teensy LC", vendor: "PJRC",
            category: "microcontroller",
            notes: "ARM Cortex-M0+. Budget Teensy with native USB."
        ),

        // USB-serial adapters — additional
        DeviceKey(vendorID: 0x10C4, productID: 0xEA61): KnownDevice(
            name: "CP2104 USB-Serial Adapter", vendor: "Silicon Labs",
            category: "serial_adapter",
            notes: "Single-port USB-UART bridge. Common on ESP32 boards."
        ),
        DeviceKey(vendorID: 0x0403, productID: 0x6011): KnownDevice(
            name: "FTDI FT4232H Quad USB-Serial", vendor: "FTDI",
            category: "serial_adapter",
            notes: "Quad-channel high-speed USB-serial. Used in multi-target debug setups."
        ),
        DeviceKey(vendorID: 0x1A86, productID: 0x55D3): KnownDevice(
            name: "CH9102F USB-Serial Adapter", vendor: "QinHeng Electronics",
            category: "serial_adapter",
            notes: "CH9102F variant. Found on newer ESP32 dev boards."
        ),
        DeviceKey(vendorID: 0x04B4, productID: 0x0002): KnownDevice(
            name: "Cypress/Infineon USB-Serial", vendor: "Cypress/Infineon",
            category: "serial_adapter",
            notes: "CY7C65213 USB-UART bridge."
        ),

        // Programmers
        DeviceKey(vendorID: 0x1781, productID: 0x0C9F): KnownDevice(
            name: "USBtinyISP", vendor: "Adafruit/Multiple",
            category: "programmer",
            notes: "AVR ISP programmer. Low-cost, widely cloned. For ATmega/ATtiny."
        ),
        DeviceKey(vendorID: 0x03EB, productID: 0x2104): KnownDevice(
            name: "AVRISP mkII", vendor: "Atmel/Microchip",
            category: "programmer",
            notes: "Official Atmel AVR ISP programmer. Supports all AVR targets."
        ),
        DeviceKey(vendorID: 0x04D8, productID: 0x9004): KnownDevice(
            name: "PICkit 3", vendor: "Microchip",
            category: "programmer",
            notes: "PIC microcontroller programmer/debugger. Supports PIC and dsPIC."
        ),
        DeviceKey(vendorID: 0x04D8, productID: 0x9012): KnownDevice(
            name: "PICkit 4", vendor: "Microchip",
            category: "programmer",
            notes: "Latest PIC programmer. Faster than PICkit 3, supports PIC, dsPIC, AVR, SAM."
        ),

        // Logic analyzers
        DeviceKey(vendorID: 0x21A9, productID: 0x1001): KnownDevice(
            name: "Saleae Logic Analyzer", vendor: "Saleae",
            category: "analyzer",
            notes: "Saleae Logic. USB logic analyzer for digital signal debugging."
        ),
        DeviceKey(vendorID: 0x21A9, productID: 0x1003): KnownDevice(
            name: "Saleae Logic Pro 8", vendor: "Saleae",
            category: "analyzer",
            notes: "8-channel mixed-signal logic analyzer. Analog + digital."
        ),
        DeviceKey(vendorID: 0x21A9, productID: 0x1004): KnownDevice(
            name: "Saleae Logic Pro 16", vendor: "Saleae",
            category: "analyzer",
            notes: "16-channel mixed-signal logic analyzer."
        ),

        // Particle
        DeviceKey(vendorID: 0x2B04, productID: 0xC006): KnownDevice(
            name: "Particle Photon", vendor: "Particle",
            category: "microcontroller",
            notes: "STM32F205 + Broadcom Wi-Fi. Cloud-connected IoT platform."
        ),
        DeviceKey(vendorID: 0x2B04, productID: 0xC00A): KnownDevice(
            name: "Particle Electron", vendor: "Particle",
            category: "microcontroller",
            notes: "STM32F205 + u-blox cellular modem. 2G/3G IoT."
        ),
        DeviceKey(vendorID: 0x2B04, productID: 0xC00D): KnownDevice(
            name: "Particle Argon", vendor: "Particle",
            category: "microcontroller",
            notes: "nRF52840 + ESP32 for Wi-Fi. Mesh networking capable."
        ),

        // Seeed Studio
        DeviceKey(vendorID: 0x2886, productID: 0x002F): KnownDevice(
            name: "Seeed Studio XIAO", vendor: "Seeed Studio",
            category: "microcontroller",
            notes: "ATSAMD21 in thumb-sized form factor. Breadboard-friendly."
        ),
        DeviceKey(vendorID: 0x2886, productID: 0x802D): KnownDevice(
            name: "Seeed Studio Wio Terminal", vendor: "Seeed Studio",
            category: "microcontroller",
            notes: "ATSAMD51 with 2.4\" LCD, Wi-Fi, BLE, IMU, microphone, buzzer."
        ),

        // Common USB peripherals
        DeviceKey(vendorID: 0x046D, productID: 0xC52B): KnownDevice(
            name: "Logitech Unifying Receiver", vendor: "Logitech",
            category: "input",
            notes: "Wireless receiver for Logitech keyboards and mice."
        ),
        DeviceKey(vendorID: 0x1050, productID: 0x0407): KnownDevice(
            name: "YubiKey 5", vendor: "Yubico",
            category: "security",
            notes: "Hardware security key. FIDO2, U2F, OTP, PIV, OpenPGP."
        ),
        DeviceKey(vendorID: 0x0FD9, productID: 0x0060): KnownDevice(
            name: "Elgato Stream Deck", vendor: "Elgato",
            category: "input",
            notes: "15-key LCD macro pad for streaming and productivity."
        ),
        DeviceKey(vendorID: 0x0FD9, productID: 0x006D): KnownDevice(
            name: "Elgato Stream Deck Mini", vendor: "Elgato",
            category: "input",
            notes: "6-key LCD macro pad. Compact Stream Deck variant."
        ),
        DeviceKey(vendorID: 0x0FD9, productID: 0x0080): KnownDevice(
            name: "Elgato Stream Deck MK.2", vendor: "Elgato",
            category: "input",
            notes: "15-key LCD macro pad. Updated design with removable USB-C cable."
        ),
    ]
}
