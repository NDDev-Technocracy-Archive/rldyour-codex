"""Keep installed vendor runtimes outside automatic source verification."""
import os
import shutil

if os.environ.get("CODEX_BIN") or shutil.which("codex"):
    raise SystemExit("Source verification requires a profile without an installed Codex runtime")
print("Source-only profile: no installed Codex runtime.")
