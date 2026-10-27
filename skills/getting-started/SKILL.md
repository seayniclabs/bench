---
name: getting-started
description: Set up and check Bench, the USB hardware MCP server, and find out what it can see. Use when the user installs Bench, asks what Bench can do, sees a bench.<module>.<code> error, a module_disabled or write_not_approved error, or wants to turn a Bench module on or off.
license: MIT
source: https://github.com/seayniclabs/bench
author: Seaynic Labs
---

# Getting started with Bench

Bench lets you see USB boards (Arduino, ESP32, Raspberry Pi Pico and others), find their serial ports, read and write those ports, detect chips, and flash firmware. It runs on this Mac and makes no network calls.

Bench is split into modules. Each module can be switched on or off:

| Module | Tools | Default |
|---|---|---|
| core | `ping`, `bench_modules` | always on |
| usb | `list_usb_devices`, `get_device_info`, `identify_device`, `hub_topology`, `diagnose_device`, `device_descriptors`, `power_info`, `monitor_events`, `snapshot_state`, `tag_device`, `port_reset`, `eject_device` | on |
| serial | `list_serial_ports`, `serial_open`, `serial_read`, `serial_write`, `serial_write_and_expect`, `serial_monitor`, `serial_close` | on |
| firmware | `chip_detect`, `flash_firmware` | on |
| hid | `hid_send` | on |
| debug | `decode_crash` | off (new in 0.4.0) |

## 1. Check the server

Call `bench_modules`. It lists each module as `[on]` or `[off]`, every tool in it, the skills folder, and whether device writes are pre-approved.

Then call `ping`. It returns the server version and confirms IOKit answers.

If the person has a terminal, have them run `bench --doctor`. It prints one line per check and a `FIX` line for each problem, then exits 0 when everything is ready and 1 when something needs fixing. Pass each FIX line on as written.

## 2. Turn modules on or off

Set these in the environment of the MCP client, then restart the client:

| Variable | Effect |
|---|---|
| `BENCH_MODULES=usb,serial,firmware,hid` | Enables exactly this list. `core` is always on. |
| `BENCH_DEBUG_ENABLED=1` | Turns on one module, here `debug` (needed for `decode_crash`). |
| `BENCH_SERIAL_ENABLED=0` | Turns off one module, here `serial`. |

Tell the person which variable to add. Do not write these settings yourself.

## 3. Find the board

1. `list_usb_devices` lists every USB device with its name, vendor, product and serial number.
2. `identify_device` with the serial number (or location ID or name) names the matched board and Bench's notes on it.
3. `list_serial_ports` with `device_type: usb` shows the `/dev/cu.*` path for each board. Use that path in every serial tool.

## 4. Approvals

Tools that change a device ask the person to approve each call: `serial_write`, `serial_write_and_expect`, `flash_firmware`, `port_reset`, `eject_device`, `chip_detect` and `hid_send` (except its read actions). The prompt shows the full arguments.

- The approval comes from the person, through the client's prompt. A `confirm: true` argument that you pass does not count as approval.
- If the client cannot show prompts, the call fails with `bench.<module>.write_not_approved`. Tell the person to set `BENCH_APPROVE_DEVICE_WRITES=1` in the server's environment and restart. Do not set it yourself.
- Every approval asked, granted, declined or refused is written to `~/.local/state/bench/approvals.jsonl` (or the path in `BENCH_APPROVAL_LOG`). Arguments are redacted there. Point the person to that file when they ask what was approved.

## 5. Read errors

Every error reads `bench.<module>.<code>: <message> Fix: <hint>`. Pass the `Fix:` text to the person as written. The common codes:

| Code | Meaning |
|---|---|
| `module_disabled` | The tool's module is off. Set the variable the hint names. |
| `missing_argument` | A required parameter is missing. Call again with it. |
| `port_not_open` | Run `serial_open` on the port first. |
| `write_not_approved` | The client cannot show approval prompts. See section 4. |
| `device_not_found` | Run `list_usb_devices` and use an identifier from it. |
| `toolchain_missing` | A flasher or addr2line is not on PATH. Install it, or set its full path in the environment. |

## 6. First session

Run these in order and report what each one shows:

1. `bench_modules`
2. `list_usb_devices` with `device_type: microcontroller`
3. `identify_device` on the board the person means
4. `list_serial_ports` with `device_type: usb`
5. `serial_monitor` on its port for 5 seconds, which reads boot output without any approval
