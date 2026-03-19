<p align="center">
  <img src="docs/assets/bench-logo.svg" alt="Bench" width="200">
</p>

<h1 align="center">Bench</h1>

<p align="center"><strong>USB hardware discovery for your AI tools.</strong></p>

Bench is a native macOS [MCP server](https://modelcontextprotocol.io) that gives AI tools like Claude Code, Cursor, and Windsurf visibility into connected USB hardware. It identifies devices, finds serial ports, and recognizes common maker boards — so your AI assistant knows what's on your bench.

No API keys. No drivers. One command to install.

## What it does

| Tool | Description |
|------|-------------|
| `list_usb_devices` | List all connected USB devices with type, vendor, speed, and serial port info |
| `get_device_info` | Detailed info on a specific device by serial, location ID, or name |
| `identify_device` | Recognize common maker boards (Arduino, Raspberry Pi Pico, ESP32, etc.) |
| `eject_device` | Safely unmount and eject removable storage |
| `ping` | Health check |

## Features

- **Device classification** — automatically categorizes devices as storage, input, hub, video, serial adapter, microcontroller, or debugger
- **Serial port detection** — maps USB devices to their `/dev/cu.*` serial ports (the #1 question makers ask)
- **35+ known boards** — recognizes Arduino, Raspberry Pi, ESP32, Adafruit, SparkFun, Teensy, STM32, and common USB-serial chips
- **Storage info** — mount points, capacity, and free space for USB drives

## Requirements

- macOS 14+ (Sonoma or later) on Apple Silicon
- An MCP-compatible AI tool (Claude Code, Cursor, Windsurf, etc.)
- For building from source: Xcode 16.3+ / Swift 6.1+

## Install

### Homebrew (recommended)

```bash
brew install seayniclabs/tap/bench
```

### From source

```bash
git clone https://github.com/seayniclabs/bench.git
cd bench
swift build -c release
codesign --force --sign - --entitlements Sources/Bench/Bench.entitlements .build/release/Bench
```

The binary is at `.build/release/Bench`.

### Add to Claude Code

```bash
claude mcp add bench -- $(which bench)
```

Or add manually to `~/.claude.json`:

```json
{
  "mcpServers": {
    "bench": {
      "command": "/path/to/bench",
      "args": []
    }
  }
}
```

## Usage

Once connected, just talk to your AI tool:

- "What USB devices are connected?"
- "What port is my Arduino on?"
- "Identify the device on /dev/cu.usbserial-2120"
- "Eject the Samsung T7"
- "Show me all storage devices"

## How it works

Bench uses Apple's [IOKit](https://developer.apple.com/documentation/iokit) framework to enumerate USB devices natively on macOS. It enriches results with serial port detection (`/dev/cu.*` scanning), storage info (`diskutil`), and a built-in database of known maker boards. It communicates with AI tools over stdio using the [Model Context Protocol](https://modelcontextprotocol.io) (JSON-RPC).

```
AI Tool  --stdio/JSON-RPC-->  Bench  --IOKit-->  USB Device Tree
                                     --diskutil-->  Storage Info
                                     --/dev/cu.*-->  Serial Ports
                                     --DeviceDB-->  Board Recognition
```

No special permissions needed. IOKit USB enumeration works without entitlements from a CLI binary.

## Building

```bash
swift build             # debug build
swift build -c release  # release build
swift test              # run tests
```

Bench requires Swift 6.1+ and targets macOS 14+.

## License

MIT

## Credits

Built by [Seaynic Labs](https://seayniclabs.com).
