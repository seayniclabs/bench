# Security policy

## Reporting a vulnerability

Report it privately on GitHub: open the repository's **Security** tab and choose **Report a vulnerability**. Please don't open a public issue.

We acknowledge reports within 2 business days and aim to ship a fix for confirmed high-severity issues within 14 days. We credit reporters in the release notes unless you ask us not to.

## What Bench does and doesn't do

- It makes no network calls and has no telemetry. Nothing leaves your Mac.
- It runs external tools (esptool, dfu-util, avrdude, addr2line) with an argument array and never through a shell. Values from the model are data, never command text. Serial paths are checked against `/dev/cu.*` or `/dev/tty.*`.
- Device-changing tools need a person's approval, shown by your client through MCP elicitation, or pre-approved by you with `BENCH_APPROVE_DEVICE_WRITES=1`. A flag from the model, such as `confirm: true`, is never approval. A client that cannot show a prompt is refused.
- Every approval asked, granted, declined or refused is written to `~/.local/state/bench/approvals.jsonl`. Payloads and file contents are not logged; device identifiers and action names are.
- `tool-manifest.lock.json` records a hash of every tool, prompt and the server instructions. CI fails if they change without the lock changing too.
- `bench --doctor` reads settings and tool paths. It opens no device for writing and changes nothing.

## Supported versions

The latest minor release receives security fixes.
