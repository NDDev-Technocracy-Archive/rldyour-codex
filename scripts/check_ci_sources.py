"""Parse tracked Python sources without importing adapters or writing bytecode."""
import ast
from pathlib import Path
import subprocess

for name in subprocess.check_output(["git", "ls-files", "*.py"], text=True).splitlines():
    ast.parse(Path(name).read_text(encoding="utf-8"), filename=name)
print("Authored Python sources parse.")
