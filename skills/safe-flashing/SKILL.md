---
name: safe-flashing
description: Flash firmware onto a USB maker board with Bench, safely, by checking the target, the file and the tool before the write. Use when the user asks to flash, upload, program or update a board's firmware, or when a flash fails with a tool error, a wrong-file error, or a timeout.
license: MIT
source: https://github.com/seayniclabs/bench
author: Seaynic Labs
---

# Safe flashing

Flashing overwrites the board's firmware. A wrong target or a wrong file can leave the board unbootable until someone reflashes it by hand. The steps below check the target, the file and the tool first, and each write needs the person's approval.

## 1. Identify the target

1. `list_usb_devices`, then `identify_device` with the board's serial number or location ID. Use that identifier for every later call. Do not use a name when two boards share one.
2. `chip_detect` (ESP32 and similar) to confirm the exact chip. It resets the chip into its bootloader, so the person approves it first.
3. Record the chip, the port path from `list_serial_ports`, and the board family.

If two or more boards of the same family are attached, stop. Ask the person which board is the target, and get its serial number.

## 2. Check the firmware file

Call nothing that writes yet. Check the file yourself:

| Target | Expected file | Tool Bench picks |
|---|---|---|
| ESP32, ESP32-S2, S3, C3 | `.bin` | esptool |
| STM32 in DFU mode | `.bin` | dfu-util |
| Arduino Uno, Nano, Mega (AVR) | `.hex` | avrdude |
| Raspberry Pi Pico (RP2040) | `.uf2` | uf2 (copies to the RPI-RP2 drive) |

Confirm the file exists, is not empty, and was built for this chip. Ask the person where it came from if the build output is unclear. A `.elf` cannot be flashed directly to most of these targets. Use the `.bin` or `.hex` the build produced next to it.

## 3. Close other sessions on the port

Call `serial_close` on the target's port if you opened it. A session open in Bench can block the flasher from using the port.

## 4. Read the approval, then flash

Call `flash_firmware` with:

- `identifier`: the serial number or location ID from step 1
- `firmware_path`: the absolute path to the file from step 2
- `tool`: only when auto-detection picked the wrong one. Use `esptool`, `dfu-util`, `avrdude` or `uf2`.
- `port`: only to override the detected port. It must be a `/dev/cu.*` path.
- `confirm`: `true`

The approval prompt shows these arguments. Read them against steps 1 and 2 before the person approves. If anything differs (another identifier, another file, a file from another project), do not approve it: tell the person what differs.

`confirm: true` must be set only for a call the person has approved in the prompt. A flash with `confirm` unset or false is refused, and that is correct.

If the client cannot show approval prompts, the call fails with `write_not_approved`. Tell the person to set `BENCH_APPROVE_DEVICE_WRITES=1` themselves and restart the client. Do not set it.

## 5. Verify the result

1. Read the tool's result. It names the tool used, the command it ran, and the exit status.
2. `serial_open` on the port at 115200 and `serial_monitor` with `seconds: 10`. A good flash shows the new firmware's boot banner.
3. A boot loop or a `Guru Meditation Error` after a successful flash points to a bad image, or a bootloader that does not match. Go to the serial-debugging skill, and do not flash again until the cause is known.
4. `serial_close` when done.

## Errors

| Code or message | What to do |
|---|---|
| "is not installed" | The flasher is missing. Install the tool the message names, put it on PATH, and retry. |
| "confirm must be true" | The call was made without `confirm`. Repeat it with `confirm: true` only after the approval. |
| "Could not auto-detect flashing tool" | Pass `tool` explicitly, using the table in step 2. |
| "Invalid port" | Use the `/dev/cu.*` path from `list_serial_ports`. |
| A timeout while writing | Put the board in its bootloader mode (hold BOOT, press RESET on most ESP32 boards), then retry. |
| Repeated failures | Stop after two. Report the tool's output and ask the person how to proceed. |

## Never

- Flash a board the person has not named by serial number or location.
- Flash a file that is not the one the person chose.
- Set `BENCH_APPROVE_DEVICE_WRITES` or any other environment variable.
- Retry a declined flash. A decline is the person's answer for that call.
