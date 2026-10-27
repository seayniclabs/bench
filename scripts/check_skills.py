#!/usr/bin/env python3
"""Fail if a skill could ship without its license, its credit, or with a promotion in it.

Every skills/<name>/SKILL.md needs `name`, `description`, `license` and `source` in its
frontmatter, and its folder name must match `name`. A skill whose source is not this
repository is third-party: it must keep a LICENSE file in its folder, use a permissive
license, and be listed in CREDITS.md. The body of a skill never links the publisher's site.
Usage: python3 scripts/check_skills.py   (exit 0 = all good)
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
OWN = "https://github.com/seayniclabs/bench"
PERMISSIVE = {"MIT", "Apache-2.0", "BSD-2-Clause", "BSD-3-Clause", "CC-BY-4.0", "CC0-1.0", "ISC"}
SITE = "seayniclabs.com"


def front(text: str) -> dict[str, str]:
    m = re.match(r"^---\n(.*?)\n---\n", text, re.S)
    meta = {}
    for line in (m.group(1).splitlines() if m else []):
        if line and not line[0].isspace() and ":" in line:
            k, _, v = line.partition(":")
            meta[k.strip()] = v.strip().strip("\"'")
    return meta


def body(text: str) -> str:
    m = re.match(r"^---\n.*?\n---\n", text, re.S)
    return text[m.end():] if m else text


def main() -> int:
    credits = (ROOT / "CREDITS.md").read_text(encoding="utf-8") if (ROOT / "CREDITS.md").exists() else ""
    problems = []
    skills = sorted((ROOT / "skills").glob("*/SKILL.md"))
    if not skills:
        problems.append("no skills/<name>/SKILL.md found")
    for path in skills:
        folder = path.parent
        name = folder.name
        text = path.read_text(encoding="utf-8")
        meta = front(text)
        for key in ("name", "description", "license", "source"):
            if not meta.get(key):
                problems.append(f"{name}: frontmatter is missing `{key}`")
        if meta.get("name") and meta["name"] != name:
            problems.append(f"{name}: frontmatter name {meta['name']!r} does not match the folder")
        if meta.get("license") and meta["license"] not in PERMISSIVE:
            problems.append(f"{name}: license {meta['license']!r} is not on the permissive list")
        if SITE in body(text):
            problems.append(f"{name}: the body links {SITE} (credit belongs in frontmatter author only)")
        if SITE in front(text).get("description", ""):
            problems.append(f"{name}: the description links {SITE}")
        third_party = not meta.get("source", "").startswith(OWN)
        if third_party:
            if not any(p.name.upper().startswith(("LICENSE", "LICENCE")) for p in folder.iterdir()):
                problems.append(f"{name}: third-party skill without a LICENSE file in its folder")
            if f"`{name}`" not in credits:
                problems.append(f"{name}: third-party skill not listed in CREDITS.md")
    for p in problems:
        print(p)
    print(f"check_skills: {len(skills)} skill(s), {len(problems)} problem(s)", file=sys.stderr)
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
