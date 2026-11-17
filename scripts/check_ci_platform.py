"""Retain the original cross-platform metadata and Python compilation smoke."""
from pathlib import Path
import compileall
import json

required = ["VERSION", "README.md", ".agents/plugins/marketplace.json", ".github/branch-protection/main.json"]
missing = [name for name in required if not Path(name).exists()]
if missing:
    raise SystemExit("missing required path(s): " + ", ".join(missing))
for name in required[2:]:
    json.loads(Path(name).read_text(encoding="utf-8"))
if not compileall.compile_dir("scripts", quiet=1):
    raise SystemExit("scripts/ Python compile failed")
print("cross-platform metadata smoke passed")
