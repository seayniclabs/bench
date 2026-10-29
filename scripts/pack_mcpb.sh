#!/bin/bash
# Pack a built Bench binary into an MCP Bundle (.mcpb) and check the result.
#
# Usage: scripts/pack_mcpb.sh BINARY OUT_DIR
# Writes OUT_DIR/bench-<version>-darwin-<arch>.mcpb and a .sha256 next to it, where
# <arch> is arm64, x86_64 or universal (from lipo). Prints the bundle path last.
#
# The bundle layout is the one manifest.json declares:
#   manifest.json, server/bench, skills/, assets/logo/bench-icon-512.png, LICENSE, CREDITS.md
# Bench finds skills/ beside server/ the same way it finds them in a checkout.
#
# Checks, in order: the manifest validates (mcpb validate); the bundle packs (mcpb pack);
# unpacked, its binary is signed and serves exactly the locked tools and prompts, with
# the skills found inside the bundle, and matches manifest.json.
set -euo pipefail

BINARY=${1:?usage: pack_mcpb.sh BINARY OUT_DIR}
OUT_DIR=${2:?usage: pack_mcpb.sh BINARY OUT_DIR}
ROOT=$(cd "$(dirname "$0")/.." && pwd)
MCPB=(npx --yes @anthropic-ai/mcpb@2.1.2)

version=$(python3 -c 'import json, sys; print(json.load(open(sys.argv[1]))["version"])' "$ROOT/manifest.json")
case "$(lipo -archs "$BINARY")" in
  "arm64") arch=arm64 ;;
  "x86_64") arch=x86_64 ;;
  "x86_64 arm64" | "arm64 x86_64") arch=universal ;;
  *) echo "unexpected architectures: $(lipo -archs "$BINARY")" >&2; exit 1 ;;
esac

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
stage="$work/bench"
mkdir -p "$stage/server" "$stage/assets/logo" "$OUT_DIR"
cp "$ROOT/manifest.json" "$ROOT/LICENSE" "$ROOT/CREDITS.md" "$stage/"
cp "$ROOT/assets/logo/bench-icon-512.png" "$stage/assets/logo/"
cp -R "$ROOT/skills" "$stage/skills"
cp "$BINARY" "$stage/server/bench"
chmod 755 "$stage/server/bench"
# Ad-hoc signature with the entitlements, as in the pinned install. Not notarized.
codesign --force --sign - --entitlements "$ROOT/Sources/Bench/Bench.entitlements" "$stage/server/bench"

"${MCPB[@]}" validate "$stage/manifest.json"
bundle="$OUT_DIR/bench-$version-darwin-$arch.mcpb"
rm -f "$bundle"
"${MCPB[@]}" pack "$stage" "$bundle"

# Check what a client gets: unpack, then talk to the bundled binary.
"${MCPB[@]}" unpack "$bundle" "$work/unpacked"
test -x "$work/unpacked/server/bench"
codesign --verify --verbose "$work/unpacked/server/bench"
python3 "$ROOT/scripts/tool_lock.py" --check --binary "$work/unpacked/server/bench"
python3 "$ROOT/scripts/mcpb_manifest.py" --check --binary "$work/unpacked/server/bench"
"${MCPB[@]}" info "$bundle"

(cd "$OUT_DIR" && shasum -a 256 "$(basename "$bundle")" > "$(basename "$bundle").sha256")
cat "$bundle.sha256" >&2
echo "$bundle"
