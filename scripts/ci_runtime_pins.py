"""Read only the two validated operator SDK selections from their existing source."""
import os
from pathlib import Path
import re

root = Path(__file__).resolve().parent.parent
text = (root / "config/mcp-runtime-versions.env").read_text()
values = {}
for key, output in (("BUN_VERSION", "bun"), ("DART_SDK_VERSION", "dart")):
    match = re.search(r"(?m)^" + key + r"=([0-9]+\.[0-9]+\.[0-9]+)$", text)
    if not match:
        raise SystemExit("Expected the exact existing operator SDK declaration: " + key)
    values[output] = match[1]
with Path(os.environ["GITHUB_OUTPUT"]).open("a") as stream:
    for key, value in values.items():
        stream.write(key + "=" + value + "\n")
