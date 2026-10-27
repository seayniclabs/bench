#!/usr/bin/env python3
"""Lock the text the model reads, so it cannot change silently.

Writes tool-manifest.lock.json: a SHA-256 of every tool's name, description, input and
output schema and annotations, every prompt's description, arguments and text, and the
server instructions, read from the built binary over stdio. `--check` (CI) exits 1 when
the binary differs from the lock. Someone who installs a version can run the same check
against that binary to see that nothing moved.

Usage: python3 scripts/tool_lock.py [--check] [--binary PATH]
"""

from __future__ import annotations

import hashlib
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from bench_probe import DEFAULT_BINARY, ROOT, Probe  # noqa: E402

LOCK = ROOT / "tool-manifest.lock.json"


def normalize(obj):
    """Collapse runs of whitespace in every string, so line endings and indentation hash the same everywhere."""
    if isinstance(obj, str):
        return " ".join(obj.split())
    if isinstance(obj, list):
        return [normalize(x) for x in obj]
    if isinstance(obj, dict):
        return {k: normalize(v) for k, v in obj.items()}
    return obj


def digest(obj) -> str:
    return hashlib.sha256(json.dumps(normalize(obj), sort_keys=True, ensure_ascii=False).encode()).hexdigest()


# Every module on, so a switched-off tool (decode_crash) is locked too.
ALL_MODULES = {"BENCH_MODULES": "usb,serial,firmware,hid,debug"}


def snapshot(binary: Path) -> dict:
    probe = Probe(binary, env=ALL_MODULES)
    try:
        tools = probe.request("tools/list")["tools"]
        prompts = probe.request("prompts/list")["prompts"]
        entries = {}
        for tool in tools:
            entries[f"tool:{tool['name']}"] = digest({
                "name": tool["name"],
                "description": tool.get("description"),
                "inputSchema": tool.get("inputSchema"),
                "outputSchema": tool.get("outputSchema"),
                "annotations": tool.get("annotations"),
            })
        for prompt in prompts:
            got = probe.request("prompts/get", {"name": prompt["name"]})
            text = "\n".join(m["content"].get("text", "") for m in got["messages"])
            entries[f"prompt:{prompt['name']}"] = digest({
                "description": prompt.get("description"), "arguments": prompt.get("arguments"), "text": text,
            })
        entries["instructions"] = digest(probe.server.get("instructions") or "")
        version = probe.server["serverInfo"]["version"]
    finally:
        probe.close()
    return {"bundle": "bench", "version": version, "entries": dict(sorted(entries.items()))}


def main(argv: list[str]) -> int:
    binary = DEFAULT_BINARY
    if "--binary" in argv:
        binary = Path(argv[argv.index("--binary") + 1])
    if not binary.exists():
        print(f"no binary at {binary}: run swift build -c release first", file=sys.stderr)
        return 2
    snap = snapshot(binary)
    if "--check" in argv:
        locked = json.loads(LOCK.read_text()) if LOCK.exists() else {"entries": {}}
        changed = sorted(k for k in set(snap["entries"]) | set(locked["entries"])
                         if snap["entries"].get(k) != locked["entries"].get(k))
        for key in changed:
            print(f"changed since the lock: {key}")
        print(f"tool_lock: {len(snap['entries'])} entries, {len(changed)} changed", file=sys.stderr)
        return 1 if changed else 0
    LOCK.write_text(json.dumps(snap, indent=2) + "\n")
    print(f"wrote {LOCK.name}: {len(snap['entries'])} entries")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
