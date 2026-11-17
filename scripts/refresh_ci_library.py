"""Refresh existing CI guard/document outputs from one complete caller revision."""
from pathlib import Path
import re

root = Path(__file__).resolve().parent.parent
repository = "NDDev-Technocracy-OpenNetwork/nddev-ci"
pattern = re.compile(r"^\s*(?:-\s*)?uses:\s*" + re.escape(repository) + r"/[^@\s]+@([0-9a-f]{40})\s+#\s*(v[0-9]+\.[0-9]+\.[0-9]+)\s*$")
pins = set()
for file in (root / ".github/workflows").glob("*.yml"):
    for line in file.read_text().splitlines():
        if "std-0004-ci-cd-workflows/" in line:
            raise SystemExit("Retired caller remains; no coherent CI outputs can be generated")
        if repository + "/" in line:
            match = pattern.fullmatch(line)
            if not match:
                raise SystemExit("CI caller is not an immutable release declaration: " + str(file))
            pins.add((match[1], match[2]))
if len(pins) != 1:
    raise SystemExit("Expected one complete CI caller revision before refreshing outputs")
sha, tag = pins.pop()
test = root / "tests/unit/test_shared_workflow_pin.py"
text = test.read_text()
for name, value in (("SHARED_REPO", repository), ("SHARED_SHA", sha), ("SHARED_VERSION", tag)):
    text, count = re.subn(r"(?m)^" + name + r' = "[^"]+"$', name + ' = "' + value + '"', text)
    if count != 1:
        raise SystemExit("Expected one existing CI guard declaration: " + name)
text = text.replace("no STD-0004 library callers found", "no CI library callers found")
test.write_text(text)
doc = root / ".github/workflows/README.md"
text = doc.read_text()
start = text.index("## Shared Workflow Pin")
end = text.index("## Required", start)
tick = chr(96)
section = "## Shared Workflow Pin\n\nThe caller declarations use engine version " + tick + tag + tick + " at commit\n" + tick + sha + tick + ". " + tick + "just ci-refresh" + tick + " derives this section and the\nexisting coherence guard from the complete workflow input set. It never moves a caller pin.\n\n"
doc.write_text(text[:start] + section + text[end:])
print("Refreshed CI guard/document outputs from", tag, sha)
