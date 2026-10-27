# Changelog

All notable changes to Bench are recorded here. Versions follow semver.

## 0.3.0

Bundle release. Bench is now one MCP server with modules you can switch on or off.

### Fixed
- The release build failed on Xcode 27 / Swift 6.4 because the pinned MCP Swift SDK
  (0.11.0) did not compile. Bench now pins swift-sdk 0.12.1, which builds.

### Added
- `bench_modules` tool: lists modules, whether each is on, its tools, and how to switch it.
- Modules: `core`, `usb`, `serial`, `firmware`, `hid`. Switch with `BENCH_MODULES` or
  `BENCH_<MODULE>_ENABLED`. Every module shipped before 0.3.0, so all are on by default.
- Device writes need approval. `serial_write`, `flash_firmware`, `port_reset`, `eject_device`
  and `hid_send` (send_report) ask the person through MCP elicitation. Clients that cannot
  answer prompts are refused unless `BENCH_APPROVE_DEVICE_WRITES=1` is set.
- Every tool result has `structuredContent` (`ok`, `module`, `tool`, `text`) and an
  `outputSchema`. Every tool has MCP annotations (read-only, destructive, idempotent).
- Errors read `bench.<module>.<code>: <message> Fix: <hint>`.
- Test suite (31 tests), including subprocess tests that start the binary with an empty
  environment and exercise the approval paths over stdio.
- `server.json` for the MCP registry (`io.github.seayniclabs/bench`).

### Changed
- Starts with an empty environment. Missing hardware or permissions return a coded error
  instead of stopping the server.
- The server runs with the SDK's strict configuration, so elicitation is refused for
  clients that did not declare support instead of hanging.
- A HID bridge force-cast that could crash on an unexpected IOKit result now returns an error.

### Compatibility
- Tool names and arguments are unchanged. The tool count goes from 22 to 23 (`bench_modules`).
- Tool results now include `structuredContent`. Text content is unchanged apart from error text.
- Device-writing tools now need approval. Scripts that relied on them running unattended
  must set `BENCH_APPROVE_DEVICE_WRITES=1`.

## 0.2.0

Released 2026-03-25 (tag `v0.2.0`). 22 tools, one server with no modules.

## 0.1.0

Tag `v0.1.0`. First tagged version.
