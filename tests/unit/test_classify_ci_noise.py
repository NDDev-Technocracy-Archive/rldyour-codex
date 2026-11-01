from __future__ import annotations

import subprocess
import sys
from pathlib import Path

from tests.support.importing import import_script

mod = import_script("scripts/classify_ci_noise.py")


def test_known_noise_is_classified_as_benign() -> None:
    benign, unknown = mod.classify_lines(
        [
            'No entry for terminal type "wezterm";',
            "using dumb terminal settings.",
            "Using CPython 3.13.12",
            "Resolving dependencies",
            "Resolved, downloaded and extracted [422]",
            "Saved lockfile",
            "   Building proxy-tools==0.1.0",
            "      Built proxy-tools==0.1.0",
            "Downloading pygments (1.2MiB)",
            " Downloaded pygments",
            "/opt/cache/pydantic_settings/sources/utils.py:47: IncompleteFieldDefinitionWarning: Field 'lifespan' has an incomplete definition",
            "  warnings.warn(",
            "  warnings.warn(  # noqa: B028  (called from many sources at differing depths, so no stacklevel is correct)",
            "turning off usage statistics. process.env['CI'] || process.env['CHROME_DEVTOOLS_MCP_NO_USAGE_STATISTICS'] is set.",
            "chrome-devtools-mcp exposes content of the browser instance to the MCP clients allowing them to inspect,",
            "debug, and modify any data in the browser or DevTools.",
            "Avoid sharing sensitive or personal information that you do not want to share with MCP clients.",
            "Update available: 1.2.0 -> 1.3.0",
            "Run `npm install chrome-devtools-mcp@latest` to update.",
            "Context7 Documentation MCP Server v3.1.0 running on stdio",
            "Tracing initialized",
            "Sequential Thinking MCP Server running on stdio",
            "retry   grep attempt 1 failed: unhandled errors in a TaskGroup (1 sub-exception)",
            'time=2026-05-21T12:18:51.376Z level=INFO msg="starting server" version=1.0.5 host="" dynamicToolsets=false readOnly=false lockdownEnabled=false',
            "GitHub MCP Server running on stdio",
            'time=2026-05-21T12:18:51.378Z level=INFO msg="server run start"',
            'time=2026-05-21T12:18:51.378Z level=INFO msg="server connecting"',
            'time=2026-05-21T12:18:51.378Z level=INFO msg="server session connected" session_id=""',
            'time=2026-05-21T12:18:51.379Z level=INFO msg="session initialized"',
            'time=2026-05-21T12:18:51.386Z level=INFO msg="server session disconnected" session_id=""',
            'time=2026-05-21T12:18:51.386Z level=INFO msg="server session ended"',
            "ERROR 2026-05-17 12:30:55,789 [LSP-stderr-reader:toml] solidlsp.ls_process:_read_ls_process_stderr:600 - ERROR taplo:update_configuration: failed to fetch configuration error=invalid configuration response",
            "INFO  2026-05-17 12:25:06,842 [MainThread] serena.cli:start_mcp_server:346 - Initializing Serena MCP server",
            "INFO  2026-05-17 12:25:07,197 [StartLS:bash] solidlsp.language_servers.common:_run_command:115 - Running command 'npm install --prefix ./ bash-language-server@5.6.0'",
            "INFO  2026-05-17 12:25:06,979 [SerenaAgentTaskExecutor] serena.task_executor:_process_task_queue:123 - Starting execution",
            "CRITICAL: Before starting to work on a coding task, call the `initial_instructions` tool to read the 'Serena Instructions Manual'.",
            "warning: .serena/research/CODEX-2026-05-15-OFFICIAL-CAPABILITIES.md: contains superseded historical claim '[features].plugin_hooks = true': Codex 0.134 treats plugin_hooks as a removed feature flag",
        ]
    )

    assert len(benign) == 37
    assert unknown == []


def test_unknown_noise_is_reported() -> None:
    benign, unknown = mod.classify_lines(["new unexpected stderr line"])

    assert benign == []
    assert unknown == ["new unexpected stderr line"]


def test_cli_strict_fails_on_unknown_noise(tmp_path: Path) -> None:
    log = tmp_path / "stderr.log"
    log.write_text("unexpected\n", encoding="utf-8")

    proc = subprocess.run(
        [sys.executable, "scripts/classify_ci_noise.py", "--strict", str(log)],
        capture_output=True,
        text=True,
        check=False,
    )

    assert proc.returncode == 1
    assert "Unknown noise lines" in proc.stderr
