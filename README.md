<p align="center">
  <img src="docs/assets/bench-logo.svg" alt="Bench" width="200">
</p>

<h1 align="center">Bench</h1>

<p align="center"><strong>USB hardware discovery for your AI tools.</strong></p>

Bench is a native macOS [MCP server](https://modelcontextprotocol.io) for developers who work with hardware plugged into their Mac: Arduino, ESP32, Raspberry Pi Pico and other USB serial boards. It finds the devices, names them, opens the right serial port, and lets your AI tool talk to them.

No API keys. No drivers. No network access. One binary.

## Modules

Bench is one server made of modules. You switch modules on or off. All modules are on by default.

| Module | Status | What it does |
|--------|--------|--------------|
| `core` | Ready (always on) | Health check and module discovery |
| `usb` | Ready | Enumerate, identify and inspect USB devices; hub tree; power; events; snapshots; port reset; eject |
| `serial` | Ready | List serial ports; open, read, write, monitor and close them |
| `firmware` | Ready (needs the flashing tool installed) | Detect chip type; flash with esptool, dfu-util, avrdude or UF2 |
| `hid` | Ready | Send and read raw HID reports |

Linux is not in this release. It is planned behind the same tools.

## Tools

23 tools in total.

**core**: `ping`, `bench_modules`

**usb**: `list_usb_devices`, `get_device_info`, `identify_device`, `eject_device`, `hub_topology`, `tag_device`, `port_reset`, `power_info`, `monitor_events`, `snapshot_state`, `diagnose_device`, `device_descriptors`

**serial**: `list_serial_ports`, `serial_open`, `serial_read`, `serial_write`, `serial_close`, `serial_monitor`

**firmware**: `chip_detect`, `flash_firmware`

**hid**: `hid_send`

Call `bench_modules` first to see what is on and how to change it.

## Settings

All settings are environment variables. Bench starts with an empty environment, and a tool call tells you which variable is missing.

| Variable | Default | Effect |
|----------|---------|--------|
| `BENCH_MODULES` | all modules | Comma list of modules to enable, for example `usb,serial`. `core` is always on. |
| `BENCH_<MODULE>_ENABLED` | per module | `1` or `0` to switch one module on or off, for example `BENCH_HID_ENABLED=0`. Overrides `BENCH_MODULES`. |
| `BENCH_APPROVE_DEVICE_WRITES` | off | `1` pre-approves device-changing calls so they run without a prompt. See Safety. |

## Safety

Bench can change hardware, so some calls are gated.

- **Device writes need approval.** `serial_write`, `flash_firmware`, `port_reset`, `eject_device`, and `hid_send` with `action: send_report` change a device or its state. Bench asks you through your client's approval prompt. The prompt shows the full arguments. A flag from the model, such as `confirm: true`, does not count as approval.
- **Clients that cannot show a prompt are refused.** Set `BENCH_APPROVE_DEVICE_WRITES=1` in the server's environment to allow writes without a prompt. Only do this when you trust every tool call your AI client makes.
- **Reads are not gated.** Discovery, monitoring, serial reads and chip detection run without a prompt.
- **Local only.** Bench makes no network calls and needs no root. Serial access on Linux (future) will need the `dialout` group, not sudo.
- **Tag and snapshot data stays on your Mac.** Nothing is sent anywhere.

## Errors

Every error reads `bench.<module>.<code>: <message> Fix: <hint>`, for example:

```
bench.serial.write_not_approved: serial_write changes a device and no approval was given. ... Fix: Set BENCH_APPROVE_DEVICE_WRITES=1 in the server's environment and restart it, or use a client that supports MCP elicitation.
```

Every tool result also has `structuredContent` with `ok`, `module`, `tool` and `text`.

## Install

### Homebrew

```bash
brew install seayniclabs/tap/bench
```

The formula builds from source, so it needs Xcode 16.3 or later. Check `bench_modules` after install to confirm the server is running.

### From source

```bash
git clone https://github.com/seayniclabs/bench.git
cd bench
swift build -c release
codesign --force --sign - --entitlements Sources/Bench/Bench.entitlements .build/release/Bench
```

The binary is at `.build/release/Bench`.

## Connect your AI client

Bench speaks plain MCP over stdio. Use the full path to the binary in each snippet.

**Claude Code**

```bash
claude mcp add bench -- $(which bench)
```

**Claude Desktop** (`claude_desktop_config.json`)

```json
{
  "mcpServers": {
    "bench": {
      "command": "/absolute/path/to/bench",
      "args": []
    }
  }
}
```

**Cursor** (`~/.cursor/mcp.json`)

```json
{
  "mcpServers": {
    "bench": {
      "command": "/absolute/path/to/bench",
      "args": []
    }
  }
}
```

**VS Code** (`.vscode/mcp.json`)

```json
{
  "servers": {
    "bench": {
      "type": "stdio",
      "command": "/absolute/path/to/bench",
      "args": []
    }
  }
}
```

To set a variable, add an `env` object next to `args`, for example `"env": { "BENCH_MODULES": "usb,serial" }`.

## Usage

Once connected, ask your AI tool:

- "What USB devices are connected?"
- "What port is my Arduino on?"
- "Identify the device on /dev/cu.usbserial-2120"
- "Open a serial connection to /dev/cu.usbserial-2120 at 9600 baud"
- "Monitor the serial output from my ESP32 for 10 seconds"

## How it works

Bench uses Apple's [IOKit](https://developer.apple.com/documentation/iokit) framework to enumerate USB devices. It adds serial port detection (`/dev/cu.*`), storage details from `diskutil`, and a built-in database of known maker boards. It talks to your AI tool over stdio using the [Model Context Protocol](https://modelcontextprotocol.io).

```
AI client  --stdio/JSON-RPC-->  Bench  --IOKit-->      USB device tree
                                       --diskutil-->   storage info
                                       --/dev/cu.*-->  serial ports
                                       --device DB-->  board recognition
```

## Build and test

```bash
swift build             # debug build
swift build -c release  # release build
swift test              # unit tests and stdio tests
```

Bench requires Swift 6.1 or later and targets macOS 14 or later. The tests start the built binary with an empty environment, so run `swift build` before `swift test` if you change the server.

## License

MIT. Published by Seaynic Labs.

## Credits

Built by [Seaynic Labs](https://seayniclabs.com).
