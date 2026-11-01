from __future__ import annotations

import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
WORKFLOWS = ROOT / ".github/workflows"
WORKFLOW_DOC = WORKFLOWS / "README.md"
SHARED_REPO = "NDDev-Technocracy-Standarts/std-0004-ci-cd-workflows"
SHARED_SHA = "9cc44a5043ddd266f3e73fefacc52f5cf5a7d70f"
SHARED_VERSION = "nddev-cicd-v0.6.18"
PIN_RE = re.compile(
    rf"^\s*(?:-\s*)?uses:\s*{re.escape(SHARED_REPO)}/[^@\s]+@{SHARED_SHA}"
    rf"\s+#\s*{re.escape(SHARED_VERSION)}\s*$"
)


def test_all_shared_workflow_callers_use_one_verified_pin() -> None:
    callers: list[tuple[Path, int, str]] = []
    for path in sorted(WORKFLOWS.glob("*.yml")):
        for line_number, line in enumerate(
            path.read_text(encoding="utf-8").splitlines(), start=1
        ):
            if f"{SHARED_REPO}/" in line:
                callers.append((path, line_number, line))

    assert callers, "no STD-0004 library callers found"
    drift = [
        f"{path.relative_to(ROOT)}:{line_number}: {line.strip()}"
        for path, line_number, line in callers
        if PIN_RE.fullmatch(line) is None
    ]
    assert not drift, "shared workflow pin drift:\n" + "\n".join(drift)


def test_shared_workflow_pin_is_documented() -> None:
    text = WORKFLOW_DOC.read_text(encoding="utf-8")
    assert f"engine version `{SHARED_VERSION}`" in text
    assert f"`{SHARED_SHA}`" in text
