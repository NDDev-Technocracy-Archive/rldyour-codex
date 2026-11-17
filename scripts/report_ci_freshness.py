"""Keep the frozen runtime's freshness report advisory and its outcome explicit."""
import json
from pathlib import Path
import subprocess
import sys

result = subprocess.run([sys.executable, "scripts/check_mcp_runtime_versions.py", "--json"], capture_output=True, text=True)
report = json.loads(result.stdout)
Path("dependency-check.json").write_text(json.dumps(report, indent=2) + "\n")
Path("dependency-check-status.json").write_text(json.dumps({"advisory": True, "command_exit": result.returncode}, indent=2) + "\n")
if result.stderr:
    print(result.stderr, file=sys.stderr)
print("Advisory MCP freshness command exit:", result.returncode)
