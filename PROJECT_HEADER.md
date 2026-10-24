# Bench

**Type:** MCP server (free; native macOS, Swift)  
**Status:** active  
**Owner:** Charlie  
**Last Updated:** 2026-10-20

## Purpose
USB hardware discovery for AI tools: a native macOS MCP server that lets Claude Code, Cursor and Windsurf see connected USB hardware. No API keys, no drivers. Repo github.com/seayniclabs/bench.

## Current State
- Working: all 22 tools pass (CMDB release status, verified 2026-10-19: builds, 11/11 tests, v0.2.0).
- Installs with Homebrew: `brew install seayniclabs/tap/bench`.
- One of the two MCPs in the free catalog on Bridge (with Lathe). Blueprint stored in the KB ("Bench — Blueprint").

## Next Steps

1. [Batch 1] Bump swift-sdk to >= 0.12.1 and cut v0.3.0 (tag, GitHub release, Homebrew formula): v0.2.0 does not build on Xcode 27.1
2. [Batch 1] Add a CI job on the newest Xcode so toolchain breaks show up in CI
3. [Batch 2] Add server.json; list in the MCP registry, then Glama, Smithery and awesome-mcp-servers (bench-2)
4. [Batch 2] README leads with board identification + HID and a demo GIF (bench-3)
5. [Later] Notarized prebuilt binary as a .mcpb bundle, also used by the formula (bench-1)

