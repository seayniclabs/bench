---
name: board-bring-up
description: Bring a new or unknown USB maker board (Arduino, ESP32, Raspberry Pi Pico, STM32) from plugged-in to talking over serial, using Bench. Use when the user connects a board for the first time, asks which board or chip they have, cannot find the board's port, or wants to confirm a board works before writing code.
license: MIT
source: https://github.com/seayniclabs/bench
author: Seaynic Labs
---

# Board bring-up

Goal: name the board and chip, find its serial port, read its boot output, and prove a write and a reply both work. Stop at each step that fails and fix it before the next one.

## 1. Confirm the board is visible

Call `list_usb_devices`. Look for the board by name, vendor or product. Record its serial number and location ID.

- Not listed: the cable carries power only, or the board is not enumerated. Ask the person to try a data cable and a different port. Call `monitor_events` once (the first call takes a snapshot), have the person unplug and replug the board, then call `monitor_events` again. A connect event in the second reply means the board enumerated.
- Listed as a generic name: go on to step 2. `identify_device` resolves it.

## 2. Name the board

Call `identify_device` with the serial number. Bench matches the vendor and product IDs against its database of known maker boards and returns the matched board with Bench's notes on it.

Some boards share one USB product ID. ESP32-S2 and ESP32-S3 do, for example. When the answer names more than one family, go to step 4 and call `chip_detect` to settle it.

## 3. Find the serial port

Call `list_serial_ports` with `device_type: usb`. Each entry gives a `/dev/cu.*` path and the USB device it matches. Use the `/dev/cu.*` form in every serial tool. A board can show two ports (for example a USB-serial bridge and a native USB port). Use the one whose matched device is the board.

If no port is listed for a board that appears in step 1, the board has no serial interface. Use `hub_topology` or `device_descriptors` to see its interfaces, and say so to the person.

## 4. Confirm the chip (ESP32 and similar)

Call `chip_detect` with the identifier. It runs esptool, which resets the chip into its bootloader. It needs approval, so the person sees the call first.

Read back the chip type, revision and MAC address. Record them in the reply. If esptool is missing, the error names the install command: install it and retry.

## 5. Read the boot output

1. `serial_open` with the port and the baud rate the firmware uses. Use `115200` when the person does not know. ESP32 boot ROM messages come out at 115200.
2. `serial_monitor` with `seconds: 5`. It reads without approval and returns what the board printed in those seconds.

Reading the output:

- Readable text: the baud rate is right. Note the firmware version or banner.
- Garbage characters: the baud rate is wrong. Close the port with `serial_close`, reopen at 9600 and then 74880, and monitor again.
- Repeating reset lines or a `Guru Meditation Error`: the firmware crashes on boot. Go to the serial-debugging skill.
- Nothing at all: the firmware may not print on this port, or it may wait for input. Monitor for 10 seconds, then check the sketch calls `Serial.begin`.

## 6. Prove a round trip

Pick a command the person's firmware answers. If none is known, use the firmware's `echo` or `ping` command if it has one, or ask the person for one.

Call `serial_write_and_expect` with the port, the command as `data`, a `pattern` for the expected reply (for example `^OK` or `pong`), and `timeout: 5`. It needs approval.

- Match: the board is working end to end. Report the matched text.
- No match within the timeout: read the transcript in the error. It shows what the board sent back. Adjust the pattern, not the timeout, when the reply is different text.

## 7. Clean up

Call `serial_close` on the port. An open session can block the next tool that needs the port, such as a flasher.

## Report

Give the person one short block: board name, chip and revision (if checked), port path, baud rate, the boot banner or first line, and the round-trip result. Name any step that did not pass, and the exact error code.
