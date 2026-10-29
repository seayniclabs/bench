# Bench

**Type:** MCP server (free; native macOS, Swift)  
**Status:** active  
**Owner:** Seaynic Labs  
**Last Updated:** 2026-10-29

## Purpose
USB hardware discovery for AI tools: a native macOS MCP server that lets Claude Code, Cursor and Windsurf see connected USB hardware. No API keys, no drivers. Repo github.com/seayniclabs/bench.

## Current State
- Version 0.4.3 (released 2026-10-28). 24 tools by default (25 with the debug module), 5 skills. Builds with Xcode 27.1 / Swift 6.4 on MCP swift-sdk 0.12.1; 62 tests pass.
- Ships as an MCP Bundle: `bench-0.4.3-darwin-universal.mcpb` on the GitHub release, signed with Developer ID and notarized by Apple (re-signed and notarized by hand for 0.4.3; CI still packs an ad-hoc-signed bundle).
- Listed in the official MCP registry as `io.github.seayniclabs/bench` 0.4.3. Also on MCP Market and submitted to mcpservers.org and MCP.so. Not on Smithery: its CLI requires tool inputSchema that MCPB forbids (upstream issues #787/#806).
- Installs with Homebrew: `brew install seayniclabs/tap/bench` (formula at 0.4.3, `brew test` passes).
- Device-changing tools ask for approval; see README Safety.

## Next Steps

1. [Batch 1] Notarize the bundle in the release workflow (Developer ID cert and the App Store Connect API key as GitHub secrets), so releases need no manual re-sign
2. [Batch 2] README leads with board identification + HID and a demo GIF (bench-3)
3. [Batch 2] Glama shows "Not graded": add the build hints Glama needs (glama.json is claimed)
4. [Later] List on Smithery once its CLI accepts MCPB tool metadata
