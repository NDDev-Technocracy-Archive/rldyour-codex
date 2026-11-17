"""Check that the prepared validation environment uses the frozen SDK."""
from importlib.metadata import PackageNotFoundError, version
from pathlib import Path
import re

root = Path(__file__).resolve().parent.parent
pins = (root / "config/mcp-runtime-versions.env").read_text(encoding="utf-8")
match = re.search(r"(?m)^MCP_PYTHON_SDK_VERSION=([0-9]+\.[0-9]+\.[0-9]+)$", pins)
try:
    actual = version("mcp")
except PackageNotFoundError:
    raise SystemExit("The CI environment is not prepared; run just setup") from None
if not match or actual != match[1]:
    raise SystemExit("The locked CI MCP SDK differs from the existing runtime declaration; refresh the CI lock")
print("Prepared CI MCP SDK:", actual)
