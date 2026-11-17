"""Lock validation dependencies against the existing frozen MCP SDK declaration."""
from pathlib import Path
import re
import json
import subprocess

root = Path(__file__).resolve().parent.parent
pins = (root / "config/mcp-runtime-versions.env").read_text(encoding="utf-8")
match = re.search(r"(?m)^MCP_PYTHON_SDK_VERSION=([0-9]+\.[0-9]+\.[0-9]+)$", pins)
if not match:
    raise SystemExit("Expected the exact existing MCP Python SDK declaration")
subprocess.run(
    ["uv", "lock", "--python", "3.13", "--no-build", "--upgrade-package", "mcp==" + match[1]],
    cwd=root,
    check=True,
)

codex = re.search(r"(?m)^CODEX_CLI_VERSION=([0-9]+\.[0-9]+\.[0-9]+)$", pins)
if not codex:
    raise SystemExit("Expected the exact existing Codex fixture declaration")
runtime = root / ".github/ci/runtime"
runtime.mkdir(parents=True, exist_ok=True)
(runtime / "package.json").write_text(json.dumps({
    "name": "rldyour-codex-ci-runtime",
    "private": True,
    "dependencies": {"@openai/codex": codex[1]},
}, indent=2) + "\n")
subprocess.run(
    ["npm", "install", "--package-lock-only", "--ignore-scripts", "--no-audit", "--no-fund"],
    cwd=runtime,
    check=True,
)
