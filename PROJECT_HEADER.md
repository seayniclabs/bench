# Bench

**Type:** MCP server (free; native macOS, Swift)  
**Status:** active  
**Owner:** Seaynic Labs  
**Last Updated:** 2026-10-27

## Purpose
USB hardware discovery for AI tools: a native macOS MCP server that lets Claude Code, Cursor and Windsurf see connected USB hardware. No API keys, no drivers. Repo github.com/seayniclabs/bench.

## Current State
- Version 0.3.0 (bundle release). 23 tools in five modules: core, usb, serial, firmware, hid.
- Builds with Xcode 27.1 / Swift 6.4 on MCP swift-sdk 0.12.1. Tests pass.
- Device-changing tools ask for approval; see README Safety.
- Installs with Homebrew: `brew install seayniclabs/tap/bench` (formula still points at v0.2.0 until 0.3.0 is tagged).

## Next Steps

1. [Batch 1] Bump swift-sdk to >= 0.12.1 and cut v0.3.0 (tag, GitHub release, Homebrew formula): v0.2.0 does not build on Xcode 27.1
2. [Batch 1] Add a CI job on the newest Xcode so toolchain breaks show up in CI
3. [Batch 2] Add server.json; list in the MCP registry, then Glama, Smithery and awesome-mcp-servers (bench-2)
4. [Batch 2] README leads with board identification + HID and a demo GIF (bench-3)
5. [Later] Notarized prebuilt binary as a .mcpb bundle, also used by the formula (bench-1)

