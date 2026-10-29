#!/usr/bin/env python3
"""Keep manifest.json (the MCP Bundle manifest) in step with what the binary serves.

Fills the manifest's `version`, `tools` and `prompts` from the built binary over stdio, with
every module on (like tool_lock.py), so `decode_crash` is listed too. The rest of the
manifest (name, author, server, compatibility) is edited by hand. `--check` (CI) exits 1
when the manifest differs from the binary, when its tool and prompt names differ from
tool-manifest.lock.json, or when its version differs from the lock or server.json.

Usage: python3 scripts/mcpb_manifest.py [--check] [--binary PATH]
"""

from __future__ import annotations

import difflib
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from bench_probe import DEFAULT_BINARY, ROOT, Probe  # noqa: E402
from tool_lock import ALL_MODULES, LOCK  # noqa: E402

MANIFEST = ROOT / "manifest.json"
SERVER_JSON = ROOT / "server.json"


def served(binary: Path) -> dict:
    probe = Probe(binary, env=ALL_MODULES)
    try:
        tools = probe.request("tools/list")["tools"]
        prompts = []
        for prompt in probe.request("prompts/list")["prompts"]:
            got = probe.request("prompts/get", {"name": prompt["name"]})
            entry = {"name": prompt["name"], "description": prompt.get("description") or ""}
            if prompt.get("arguments"):
                entry["arguments"] = [a["name"] for a in prompt["arguments"]]
            entry["text"] = "\n".join(m["content"].get("text", "") for m in got["messages"])
            prompts.append(entry)
        version = probe.server["serverInfo"]["version"]
    finally:
        probe.close()
    return {
        "version": version,
        "tools": [{"name": t["name"], "description": t.get("description") or ""} for t in tools],
        "prompts": prompts,
    }


def mismatches(manifest: dict) -> list[str]:
    """Names and versions that must agree with the lock and server.json."""
    lock = json.loads(LOCK.read_text())
    server = json.loads(SERVER_JSON.read_text())
    out = []
    names = {f"tool:{t['name']}" for t in manifest.get("tools", [])}
    names |= {f"prompt:{p['name']}" for p in manifest.get("prompts", [])}
    locked = {k for k in lock["entries"] if k != "instructions"}
    for key in sorted(names - locked):
        out.append(f"in manifest.json, not in the lock: {key}")
    for key in sorted(locked - names):
        out.append(f"in the lock, not in manifest.json: {key}")
    for label, version in (("tool-manifest.lock.json", lock["version"]), ("server.json", server["version"])):
        if manifest.get("version") != version:
            out.append(f"manifest.json version {manifest.get('version')} != {label} version {version}")
    for package in server.get("packages", []):
        if package.get("registryType") == "mcpb" and f"/v{server['version']}/" not in package["identifier"]:
            out.append(f"server.json mcpb identifier does not name v{server['version']}: {package['identifier']}")
    return out


def main(argv: list[str]) -> int:
    binary = DEFAULT_BINARY
    if "--binary" in argv:
        binary = Path(argv[argv.index("--binary") + 1])
    if not binary.exists():
        print(f"no binary at {binary}: run swift build -c release first", file=sys.stderr)
        return 2
    current = json.loads(MANIFEST.read_text())
    wanted = {**current, **served(binary)}
    text = json.dumps(wanted, indent=2, ensure_ascii=False) + "\n"
    if "--check" in argv:
        problems = mismatches(wanted)
        old = json.dumps(current, indent=2, ensure_ascii=False) + "\n"
        if old != text:
            sys.stdout.writelines(difflib.unified_diff(
                old.splitlines(keepends=True), text.splitlines(keepends=True), "manifest.json", "from the binary"))
            problems.append("manifest.json differs from the binary: run python3 scripts/mcpb_manifest.py")
        for problem in problems:
            print(problem)
        print(f"mcpb_manifest: {len(wanted['tools'])} tools, {len(wanted['prompts'])} prompts, "
              f"{len(problems)} problem(s)", file=sys.stderr)
        return 1 if problems else 0
    MANIFEST.write_text(text)
    print(f"wrote {MANIFEST.name}: {len(wanted['tools'])} tools, {len(wanted['prompts'])} prompts")
    for problem in mismatches(wanted):
        print(problem)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
