#!/usr/bin/env python3
"""Classify stderr/log noise so CI can fail on new unexpected runtime chatter."""

from __future__ import annotations

import argparse
import re
import sys
from dataclasses import dataclass
from pathlib import Path


@dataclass(frozen=True)
class NoiseRule:
    name: str
    pattern: re.Pattern[str]
    reason: str


BENIGN_RULES: tuple[NoiseRule, ...] = (
    NoiseRule(
        "terminalinfo-wezterm-fallback",
        re.compile(r"No entry for terminal type \"wezterm\";|using dumb terminal settings\."),
        "Python terminal metadata warning in local noninteractive runners.",
    ),
    NoiseRule(
        "uv-environment-setup",
        re.compile(
            r"Using CPython \d+\.\d+\.\d+|"
            r"Removed virtual environment at:|"
            r"Creating virtual environment at:|"
            r"Installed \d+ packages? in|"
            r"Resolving dependencies|"
            r"Resolved, downloaded and extracted \[\d+\]|"
            r"Saved lockfile|"
            r"Building [A-Za-z0-9_.=-]+|"
            r"Built [A-Za-z0-9_.=-]+|"
            r"Downloading [A-Za-z0-9_.-]+ \([^)]+\)|"
            r"Downloaded [A-Za-z0-9_.-]+"
        ),
        "uv may report environment setup to stderr while preparing an isolated test runtime.",
    ),
    NoiseRule(
        "pydantic-settings-forward-reference-advisory",
        re.compile(
            r"pydantic_settings/sources/utils\.py:\d+: IncompleteFieldDefinitionWarning:|"
            r"^warnings\.warn\((\s+#.*)?$"
        ),
        "pydantic-settings reports an unresolved optional lifespan annotation; the MCP startup and deterministic call remain the behavioral gate.",
    ),
    NoiseRule(
        "chrome-devtools-mcp-advisory",
        re.compile(
            r"turning off usage statistics|"
            r"chrome-devtools-mcp exposes content|"
            r"debug, and modify any data|"
            r"Avoid sharing sensitive or personal information",
            re.IGNORECASE,
        ),
        "Chrome DevTools MCP prints a non-blocking safety notice on startup.",
    ),
    NoiseRule(
        "mcp-server-stdio-startup",
        re.compile(
            r"Context7 Documentation MCP Server .* running on stdio|"
            r"Sequential Thinking MCP Server running on stdio|"
            r"Tracing initialized|"
            r"\(Use `node --trace-warnings \.\.\.` to show where the warning was created\)"
        ),
        "MCP servers print startup banners and successful safe-call traces to stderr.",
    ),
    NoiseRule(
        "mcp-transient-retry",
        re.compile(r"retry\s+[-A-Za-z0-9_]+\s+attempt\s+\d+\s+failed:\s+unhandled errors in a TaskGroup"),
        "MCP capability smoke retries transient TaskGroup failures and validates the eventual successful call.",
    ),
    NoiseRule(
        "github-mcp-server-runtime",
        re.compile(
            r"GitHub MCP Server running on stdio|"
            r'time=\d{4}-\d{2}-\d{2}T[0-9:.]+(?:Z|[+-]\d{2}:\d{2}) level=INFO msg="'
            r"(starting server|server run start|server connecting|server session connected|"
            r"session initialized|server session disconnected|server session ended)"
        ),
        "GitHub MCP server prints bounded lifecycle lines during deterministic capability smoke.",
    ),
    NoiseRule(
        "chrome-devtools-localstorage",
        re.compile(r"chrome-devtools.*localstorage|localstorage-file", re.IGNORECASE),
        "Chrome DevTools MCP warns about optional local storage in ephemeral CI.",
    ),
    NoiseRule(
        "chrome-devtools-update-advisory",
        re.compile(
            r"^(?:Update available: \d+(?:\.\d+){1,3} -> \d+(?:\.\d+){1,3}|"
            r"Run `npm install chrome-devtools-mcp@latest` to update\.)$"
        ),
        "Chrome DevTools MCP prints a non-blocking package update advisory to stderr.",
    ),
    NoiseRule(
        "serena-lsp-configuration",
        re.compile(
            r"workspace/configuration|"
            r"taplo.*catalog|"
            r"language server.*configuration|"
            r"failed to fetch configuration|"
            r"invalid configuration response",
            re.IGNORECASE,
        ),
        "Known LSP capability warning from third-party language servers.",
    ),
    NoiseRule(
        "serena-mcp-runtime-log",
        re.compile(
            r"^(?:(INFO|WARNING)  \d{4}-\d{2}-\d{2} .*"
            r"(serena|solidlsp|sensai|mcp\.server)\."
            r"|CRITICAL: Before starting to work on a coding task, call the `initial_instructions` tool)"
        ),
        "Serena MCP and its language-server dependencies log normal startup/shutdown detail to stderr.",
    ),
    NoiseRule(
        "superseded-research-claim",
        re.compile(
            r"^warning: \.serena/research/[^:]+: contains superseded historical claim "
            r"'.+': .+$"
        ),
        "Instruction validation reports explicitly superseded historical research claims without failing.",
    ),
)


def read_log(paths: list[Path]) -> list[str]:
    if not paths:
        return sys.stdin.read().splitlines()

    lines: list[str] = []
    for path in paths:
        try:
            lines.extend(path.read_text(encoding="utf-8", errors="replace").splitlines())
        except OSError as exc:
            raise SystemExit(f"failed to read {path}: {exc}") from exc
    return lines


def classify_line(line: str) -> tuple[str, str] | None:
    stripped = line.strip()
    if not stripped:
        return ("empty", "blank log line")
    for rule in BENIGN_RULES:
        if rule.pattern.search(stripped):
            return (rule.name, rule.reason)
    return None


def classify_lines(lines: list[str]) -> tuple[list[str], list[str]]:
    benign: list[str] = []
    unknown: list[str] = []
    for line in lines:
        classification = classify_line(line)
        if classification is None:
            unknown.append(line)
        elif classification[0] != "empty":
            benign.append(f"{classification[0]}: {line}")
    return benign, unknown


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("paths", nargs="*", type=Path, help="Log files to classify. Reads stdin when omitted.")
    parser.add_argument("--strict", action="store_true", help="Fail when unknown non-empty log lines are present.")
    args = parser.parse_args()

    lines = read_log(args.paths)
    benign, unknown = classify_lines(lines)

    if benign:
        print(f"Known benign noise lines: {len(benign)}")
        for line in benign:
            print(line)

    if unknown:
        print(f"Unknown noise lines: {len(unknown)}", file=sys.stderr)
        for line in unknown:
            print(line, file=sys.stderr)
        return 1 if args.strict else 0

    print("CI noise classification passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
