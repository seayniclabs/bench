---
name: serial-debugging
description: Debug a USB serial session with Bench when the device output is garbled, silent, looping, or does not reply to commands, or when the device crashed and printed a Guru Meditation Error or HardFault. Use when the user says their board prints nothing, prints junk, reboots in a loop, ignores commands, or shows a crash dump.
license: MIT
source: https://github.com/seayniclabs/bench
author: Seaynic Labs
---

# Serial debugging

Work from the cheapest check to the most expensive. Each step narrows the cause, and the approval-gated tools come last.

## 1. Read before writing

Use only the read tools first. They run without approval.

1. `serial_open` on the port with the baud rate the firmware sets (in its `Serial.begin` call or its config). Leave out `baud_rate` for 115200.
2. `serial_monitor` with `seconds: 10`.
3. Read the output and match it to a row below.

| Output | Likely cause | Next step |
|---|---|---|
| Readable text | Working link | Go to step 2 |
| Random bytes, `�` characters | Wrong baud rate | Reopen at 9600, 19200, 57600, 74880, 115200 and monitor each for 3 seconds. The right one reads cleanly. |
| Nothing for 10 seconds | Board silent, port wrong, or board waiting | Check the port with `list_serial_ports`. Try `serial_read` with `timeout: 3`. Send a newline with `serial_write` if the board waits for input. |
| The same boot lines repeat | Reset loop | Look for a crash line (step 4). |
| `Guru Meditation Error`, `Backtrace:` | ESP32 crash | Step 4 |
| `HardFault`, `CFSR`, `PC =` | ARM Cortex-M crash | Step 4 |

## 2. Confirm the reply path

Use `serial_write_and_expect` to send one command and wait for its reply. It needs approval, and the person sees the full command first.

- Set `pattern` to the exact text the firmware prints, as a regular expression. `^OK` matches a line that starts with OK. `temp=[0-9.]+` matches a reading.
- Set `timeout` to the longest the firmware takes to answer. 5 seconds covers most sketches.
- On no match, the error returns the last 8 KB of output. Compare it to the pattern before changing anything else.

A device that echoes the command but never replies usually has a line-ending mismatch. Send with a trailing newline in `data` (Bench adds CR LF when there is none) and try again.

## 3. Check the port is free

- `port_not_open`: `serial_open` was not called, or `serial_close` ran. Open the port again.
- `Read error` or `Write error`: the board was unplugged or reset. Run `list_serial_ports` again, since the path can change when the board re-enumerates.
- A second session on the same port: close one. Bench holds the port until `serial_close`.

## 4. Decode a crash

Crash dumps show code addresses that point into the firmware. `decode_crash` maps them to source lines.

Requirements:

- The `debug` module is on. Set `BENCH_DEBUG_ENABLED=1` in the client's environment and restart it. Tell the person to do this; do not set it yourself.
- An addr2line for the chip is on PATH: `xtensa-esp32-elf-addr2line` or `riscv32-esp-elf-addr2line` for ESP32 parts, `arm-none-eabi-addr2line` for ARM. Or set `BENCH_ADDR2LINE` to its full path.
- The `.elf` file from the same build that is crashing. A `.bin` or `.hex` will not work.

Call `decode_crash` with:

- `output`: the crash block, from the `Guru Meditation` or `HardFault` line through the `Backtrace:` or register lines.
- `elf`: the absolute path to the `.elf`, for example `/Users/you/project/build/firmware.elf`.

Read the frames top to bottom. Frame `#0` is the instruction that faulted. The rest are the calls that led there. A frame marked `??` is not in the `.elf`, which usually means the `.elf` is from a different build.

Then fix the code at frame `#0` or the first frame that is in the person's own source. Use the `systematic-debugging` skill to confirm the cause before changing code.

## 5. Common crash causes

- `LoadProhibited` or `StoreProhibited` on an address near 0 or in the 0x3ffb range: a null pointer, or a buffer written past its end.
- `IllegalInstruction` after a flash update: the firmware and bootloader do not match. Reflash the whole image.
- `InstrFetchProhibited` on an address in RAM: a function pointer or stack overflow jumped into data.
- `Stack overflow` or `Stack canary watchpoint`: a task stack is too small. Increase it or move large buffers off the stack.
- ARM `HardFault` with `IACCVIOL` or `IBUSERR`: a jump to a bad address, often a corrupted function pointer.
- ARM `HardFault` with `PRECISERR` or `BFARVALID`: the address in `BFAR` is the bad access.

## 6. When to stop and ask

Stop and ask the person before any of these:

- Re-flashing the board (see the safe-flashing skill).
- Changing any setting in the client's environment.
- Sending a command to a device the person has not named.

## Report

Give the person the port and baud rate, the first crash line or the matched reply, the decoded top frame with its file and line, and the next check you suggest.
