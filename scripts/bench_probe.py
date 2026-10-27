"""Talk to the built Bench binary over stdio, the way an MCP client does (stdlib only).

Used by tool_lock.py and security_card.py, so both read what the binary actually serves.
Starts it with an empty environment (PATH and a scratch HOME only), as a client would
when the person has set nothing, plus any `env` the caller passes.
"""

from __future__ import annotations

import json
import os
import subprocess
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DEFAULT_BINARY = ROOT / ".build" / "release" / "Bench"


class Probe:
    def __init__(self, binary: Path = DEFAULT_BINARY, env: dict | None = None):
        self.home = tempfile.mkdtemp(prefix="bench-probe-")
        environment = {"PATH": "/usr/bin:/bin", "HOME": self.home}
        environment.update(env or {})
        self.proc = subprocess.Popen(
            [str(binary)], stdin=subprocess.PIPE, stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL, env=environment,
        )
        self._next = 1
        self.server = self.request("initialize", {
            "protocolVersion": "2025-11-25", "capabilities": {},
            "clientInfo": {"name": "bench-scripts", "version": "1"},
        })
        self._send({"jsonrpc": "2.0", "method": "notifications/initialized"})

    def _send(self, message: dict) -> None:
        self.proc.stdin.write((json.dumps(message) + "\n").encode())
        self.proc.stdin.flush()

    def request(self, method: str, params: dict | None = None) -> dict:
        """One request, waiting for its own response. Returns the `result` object."""
        rid = self._next
        self._next += 1
        self._send({"jsonrpc": "2.0", "id": rid, "method": method, "params": params or {}})
        while True:
            line = self.proc.stdout.readline()
            if not line:
                raise RuntimeError(f"bench closed stdout during {method}")
            message = json.loads(line)
            if message.get("id") == rid:
                if "error" in message:
                    raise RuntimeError(f"{method} failed: {message['error']}")
                return message["result"]

    def close(self) -> None:
        try:
            self.proc.stdin.close()
        except OSError:
            pass
        self.proc.terminate()
        self.proc.wait(timeout=10)
