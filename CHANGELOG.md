# Changelog

All notable changes to Bench are recorded here. Versions follow semver.

## 0.4.3 (2026-10-29)

### Added
- MCP Bundle for Claude Desktop: `manifest.json` (MCPB manifest 0.3, binary server, macOS only) and `bench-<version>-darwin-universal.mcpb` on each release, with its SHA-256. Open the `.mcpb` in Claude Desktop to install Bench with its skills, no Homebrew or Xcode needed.
- Release workflow (`.github/workflows/release.yml`): on a version tag, builds a universal (arm64 and x86_64) binary, packs and checks the bundle, and attaches the bundle, its `.sha256` and a `server.json` with the hash filled in to the release.
- `server.json` has an `mcpb` package for the official MCP registry. The repository copy holds a placeholder hash; the release asset holds the real one.
- Scripts: `mcpb_manifest.py` (keeps the manifest's tools and prompts equal to the binary and the lock) and `pack_mcpb.sh`.

### Changed
- CI packs the bundle from the release build, validates it with `mcpb validate`, and checks the unpacked binary against the lock and the manifest. CI also validates `server.json` with `mcp-publisher validate`.

## 0.4.2

### Changed
- `bench_modules` now lists the names of the skills it serves, not only the count, like the other Seaynic Labs bundles.

### Known limitation
- A client that sends requests before the `initialize` reply arrives gets no answer to them (MCP Swift SDK behavior, also in 0.4.0). Every tested app waits for the reply first.

## 0.4.1

### Fixed
- Bench now answers requests that arrive before `initialize` with the request's own id: `ping` gets an empty result, anything else gets "method not found". Clients on MCP 2026-07-28, such as Antigravity, open with `server/discover`; the Swift SDK answered it under a different id, so those clients waited forever and never connected. They now fall back to `initialize` and connect. Tested in Antigravity CLI.

## 0.4.0

Bundle release: tools, skills and trust. Bench now ships skills next to the server, served to any MCP app as prompts and resources.

### Added
- Skills in `skills/`, served as one MCP prompt per skill and one resource per file (`skill://bench/<skill>/<path>`): `getting-started`, `board-bring-up`, `serial-debugging`, `safe-flashing`, and `systematic-debugging` (MIT, from obra/superpowers, see CREDITS.md).
- `decode_crash` (read-only, module `debug`, off by default): resolves the program counters in an ESP32 Guru Meditation Error or an ARM HardFault dump with addr2line and the matching `.elf`. Finds the toolchain on PATH, or at `BENCH_ADDR2LINE`. A missing toolchain names what to install.
- `serial_write_and_expect` (needs approval, like `serial_write`): writes a line and reads until a regular expression matches or the timeout passes. Returns the transcript.
- `bench --doctor`: checks the modules, USB and serial access, esptool, addr2line, approvals, the skills folder and the network stance. Prints a `FIX` line per problem and exits 1 when something needs fixing.
- Local approval log, `~/.local/state/bench/approvals.jsonl` (or `BENCH_APPROVAL_LOG`). Every device-write approval asked, granted, declined, refused or pre-approved is appended. Payloads are not logged.
- Server instructions for every client, naming the getting-started prompt. Discovery (`bench_modules`) names the publisher, the homepage, the skills and the approval log.
- Tool and prompt lock (`tool-manifest.lock.json`), generated security card, `SECURITY.md`, `CREDITS.md`, `.claude-plugin/plugin.json`, `.mcp.json`.
- Scripts: `check_skills.py`, `tool_lock.py`, `security_card.py`.

### Changed
- 25 tools (was 23). Default install lists 24; `decode_crash` appears when `BENCH_DEBUG_ENABLED=1`.
- A write to a port that is not open returns `bench.serial.port_not_open` with a fix, instead of the generic error.
- `serial_write_and_expect` needs approval, like `serial_write`. `decode_crash` is read-only.
- CI checks the skills, the tool lock and the security card, and expects 24 tools by default.

### Compatibility
- Existing tool names and arguments are unchanged.
- New module `debug` ships switched off (`BENCH_DEBUG_ENABLED=1` turns it on). Modules shipped before 0.4.0 keep their defaults.
- The Homebrew formula installs the skills to `share/bench/skills`. A binary run from anywhere else finds them through `BENCH_SKILLS_DIR`.

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
