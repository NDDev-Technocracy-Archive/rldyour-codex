#!/usr/bin/env python3
from __future__ import annotations

import argparse
import asyncio
import importlib
import json
import os
import shutil
import sys
import tomllib
from collections.abc import Awaitable, Callable
from contextlib import AsyncExitStack, suppress
from pathlib import Path
from typing import Any

EXPECTED_TOOLS: dict[str, set[str]] = {
    "serena": {"initial_instructions", "onboarding", "list_memories", "get_symbols_overview", "find_symbol", "read_memory"},
    "sequential-thinking": {"sequentialthinking"},
    "chrome-devtools": {"new_page", "list_console_messages", "take_screenshot"},
    "context7": {"resolve-library-id", "query-docs"},
    "deepwiki": {"read_wiki_structure", "ask_wiki_question"},
    "grep": {"searchGitHub"},
    "shadcn": {"get_project_registries", "search_items_in_registries"},
    "dart-flutter": {"analyze_files", "pub_dev_search"},
    "figma": {"get_design_context", "get_screenshot"},
    "openaiDeveloperDocs": {"search_openai_docs", "list_openai_docs", "fetch_openai_doc"},
}

AUTH_REQUIRED = {"figma"}
STARTUP_ENV_REQUIRED = {"github"}
# Hosted/external MCP resilience is two-layered, and both layers are deliberate:
#  1. In-probe: _probe_with_retries downgrades transient failures (504s, timeouts,
#     anyio cancel-scope teardown) from servers in this set to a graceful "skip"
#     rather than failing the smoke (see tests/unit/test_smoke_mcp_capabilities.py).
#  2. CI policy: the same external (grep) and localhost (figma) servers are also
#     passed via --skip-server in CI. GitHub-hosted runners cannot reach them
#     reliably, AND the MCP client's anyio cancel scope can still raise during
#     event-loop shutdown (after _main_async has already returned its exit code),
#     which is outside every per-server handler. Both servers stay statically
#     config-validated and work in real owner use. Do not drop the CI skips or
#     this transient set without re-proving both layers.
TRANSIENT_EXTERNAL_MCP_SERVERS = {"grep"}
TRANSIENT_EXTERNAL_FAILURE_MARKERS = (
    "504 Gateway Timeout",
    "Server error '504",
    "timed out after",
    "Cancelled via cancel scope",
    "aclose(): asynchronous generator is already running",
    "Attempted to exit cancel scope",
)


class ProbeFailure(Exception):
    pass


def _require_mcp_imports() -> tuple[Any, Any, Any]:
    try:
        mcp_module = importlib.import_module("mcp")
        stdio_module = importlib.import_module("mcp.client.stdio")
        stream_http_module = importlib.import_module("mcp.client.streamable_http")
    except ModuleNotFoundError as exc:
        raise ProbeFailure(
            "missing optional MCP runtime dependency; install it to run MCP probes in runtime mode"
        ) from exc
    return mcp_module, stdio_module, stream_http_module


def _exception_chain_text(exc: BaseException) -> str:
    parts: list[str] = []
    stack: list[BaseException] = [exc]
    seen: set[int] = set()
    while stack:
        current = stack.pop()
        ident = id(current)
        if ident in seen:
            continue
        seen.add(ident)
        parts.append(f"{type(current).__name__}: {current}")
        if isinstance(current, BaseExceptionGroup):
            stack.extend(current.exceptions)
        if current.__cause__ is not None:
            stack.append(current.__cause__)
        if current.__context__ is not None:
            stack.append(current.__context__)
    return "\n".join(parts)


def _is_transient_external_failure(name: str, exc: BaseException) -> bool:
    if name not in TRANSIENT_EXTERNAL_MCP_SERVERS:
        return False
    if isinstance(exc, (KeyboardInterrupt, SystemExit)):
        return False
    if isinstance(exc, (TimeoutError, asyncio.CancelledError)):
        return True
    text = _exception_chain_text(exc)
    return any(marker in text for marker in TRANSIENT_EXTERNAL_FAILURE_MARKERS)


def _clear_current_task_cancellation() -> None:
    task = asyncio.current_task()
    if task is None or not hasattr(task, "uncancel"):
        return
    while task.cancelling():
        task.uncancel()


def _load_servers(root: Path, codex_home: Path) -> dict[str, dict[str, Any]]:
    repo_servers = _load_repo_servers(root)
    config_path = codex_home / "config.toml"
    if not config_path.is_file():
        raise ProbeFailure(f"missing {config_path}")

    config_servers = tomllib.loads(config_path.read_text(encoding="utf-8")).get("mcp_servers", {})
    if set(repo_servers) != set(config_servers):
        raise ProbeFailure(
            "MCP server name mismatch: "
            f"repo={sorted(repo_servers)} installed={sorted(config_servers)}"
        )
    return {name: dict(config_servers[name]) for name in sorted(repo_servers)}


def _load_repo_servers(root: Path) -> dict[str, dict[str, Any]]:
    repo_path = root / "plugins/rldyour-mcps/.mcp.json"
    if not repo_path.is_file():
        raise ProbeFailure(f"missing {repo_path}")
    try:
        payload = json.loads(repo_path.read_text(encoding="utf-8"))
    except json.JSONDecodeError as exc:
        raise ProbeFailure(f"{repo_path}: invalid JSON: {exc}") from exc
    servers = payload.get("mcpServers")
    if not isinstance(servers, dict):
        raise ProbeFailure(f"{repo_path}: mcpServers must be an object")
    return {str(name): dict(spec) for name, spec in sorted(servers.items())}


def _static_record(name: str, spec: dict[str, Any]) -> tuple[dict[str, Any], str | None]:
    has_command = "command" in spec
    has_url = "url" in spec
    error: str | None = None
    if has_command == has_url:
        error = "must define exactly one of command or url"
    elif has_command and not isinstance(spec.get("command"), str):
        error = "command must be a string"
    elif has_url and not isinstance(spec.get("url"), str):
        error = "url must be a string"
    elif "args" in spec and not isinstance(spec.get("args"), list):
        error = "args must be an array"
    elif "env" in spec and not isinstance(spec.get("env"), dict):
        error = "env must be an object"
    elif "env_vars" in spec and not isinstance(spec.get("env_vars"), list):
        error = "env_vars must be an array"

    record: dict[str, Any] = {
        "server": name,
        "status": "static" if error is None else "fail",
        "transport": "http" if has_url else "stdio" if has_command else "invalid",
        "expected_tools": sorted(EXPECTED_TOOLS.get(name, set())),
    }
    if has_command:
        record["command"] = spec.get("command")
        record["args"] = [str(arg) for arg in spec.get("args") or []]
    if has_url:
        record["url"] = spec.get("url")
    if "env" in spec:
        record["env_keys"] = sorted(str(key) for key in (spec.get("env") or {}))
    if "env_vars" in spec:
        record["env_vars"] = [str(key) for key in spec.get("env_vars") or []]
    if error:
        record["error"] = error
    return record, error


def _main_static(args: argparse.Namespace) -> int:
    root = args.root.resolve()
    servers = _load_repo_servers(root)
    selected = set(args.server or servers)
    skipped = set(args.skip_server or [])
    records: list[dict[str, Any]] = []
    errors: list[str] = []

    for name, spec in servers.items():
        if name not in selected or name in skipped:
            continue
        record, error = _static_record(name, spec)
        records.append(record)
        if error:
            errors.append(f"{name}: {error}")

    if args.json:
        print(json.dumps({"mode": "static", "count": len(records), "results": records, "errors": errors}, indent=2))
    else:
        print("rldyour MCP capability smoke")
        print(f"root: {root}")
        print("mode: static")
        for record in records:
            prefix = "fail" if record["status"] == "fail" else "ok"
            detail = record.get("error") or f"{record['transport']} config parsed"
            print(f"{prefix:<7} {record['server']}: {detail}")
        if errors:
            print("\n".join(errors), file=sys.stderr)
        else:
            print("MCP static capability smoke passed.")
    return 1 if errors else 0


def _merged_env(spec: dict[str, Any]) -> tuple[dict[str, str], list[str]]:
    env = dict(os.environ)
    missing: list[str] = []
    for key, value in (spec.get("env") or {}).items():
        env[str(key)] = str(value)
    for key in spec.get("env_vars") or []:
        key_text = str(key)
        value = os.environ.get(key_text)
        if value is None:
            missing.append(key_text)
        else:
            env[key_text] = value
    return env, missing


def _missing_forwarded_env(spec: dict[str, Any]) -> list[str]:
    return [str(key) for key in spec.get("env_vars") or [] if os.environ.get(str(key)) is None]


def _content_len(result: Any) -> int:
    content = getattr(result, "content", None)
    return len(content) if isinstance(content, list) else 0


async def _safe_call(name: str, session: Any, missing_env: list[str]) -> str | None:
    if name == "serena":
        result = await session.call_tool("list_memories", {})
        if result.isError:
            raise ProbeFailure("list_memories returned isError=true")
        return "list_memories"

    if name == "sequential-thinking":
        result = await session.call_tool(
            "sequentialthinking",
            {
                "thought": "MCP capability smoke test.",
                "nextThoughtNeeded": False,
                "thoughtNumber": 1,
                "totalThoughts": 1,
            },
        )
        if result.isError:
            raise ProbeFailure("sequentialthinking returned isError=true")
        return "sequentialthinking"

    if name == "chrome-devtools":
        result = await session.call_tool(
            "new_page",
            {"url": "data:text/html,<title>mcp-smoke</title><h1>ok</h1>"},
        )
        if result.isError:
            raise ProbeFailure("new_page returned isError=true")
        return "new_page"

    if name == "context7":
        if missing_env:
            return None
        result = await session.call_tool(
            "resolve-library-id",
            {"libraryName": "react", "query": "React documentation smoke test"},
        )
        if result.isError or _content_len(result) == 0:
            raise ProbeFailure("resolve-library-id returned an empty or error result")
        return "resolve-library-id"

    if name == "deepwiki":
        result = await session.call_tool(
            "read_wiki_structure",
            {"repoName": "modelcontextprotocol/python-sdk"},
        )
        if result.isError or _content_len(result) == 0:
            raise ProbeFailure("read_wiki_structure returned an empty or error result")
        return "read_wiki_structure"

    if name == "grep":
        result = await session.call_tool(
            "searchGitHub",
            {"query": "useState(", "useRegexp": False, "language": ["TSX"]},
        )
        if result.isError or _content_len(result) == 0:
            raise ProbeFailure("searchGitHub returned an empty or error result")
        return "searchGitHub"

    if name == "shadcn":
        result = await session.call_tool("get_project_registries", {})
        if result.isError or _content_len(result) == 0:
            raise ProbeFailure("get_project_registries returned an empty or error result")
        return "get_project_registries"

    if name == "openaiDeveloperDocs":
        result = await session.call_tool(
            "search_openai_docs",
            {"query": "Codex MCP configuration", "limit": 3},
        )
        if result.isError or _content_len(result) == 0:
            raise ProbeFailure("search_openai_docs returned an empty or error result")
        return "search_openai_docs"

    return None


async def _stdio_session(
    spec: dict[str, Any],
    body: Callable[[Any, list[str]], Awaitable[None]],
) -> None:
    mcp_module, stdio_module, _ = _require_mcp_imports()

    command = str(spec.get("command") or "")
    if not command:
        raise ProbeFailure("missing command")
    if Path(command).is_absolute():
        if not os.access(command, os.X_OK):
            raise ProbeFailure(f"command is not executable: {command}")
    elif shutil.which(command) is None:
        raise ProbeFailure(f"command not found: {command}")

    env, missing_env = _merged_env(spec)
    params = stdio_module.StdioServerParameters(
        command=command, args=[str(arg) for arg in spec.get("args") or []], env=env
    )
    stack = AsyncExitStack()
    try:
        read, write = await stack.enter_async_context(stdio_module.stdio_client(params))
        session = await stack.enter_async_context(mcp_module.ClientSession(read, write))
        await session.initialize()
        await body(session, missing_env)
    except Exception:
        with suppress(Exception):
            await stack.aclose()
        raise
    with suppress(Exception):
        await stack.aclose()


async def _http_session(
    spec: dict[str, Any],
    body: Callable[[Any, list[str]], Awaitable[None]],
) -> None:
    mcp_module, _, stream_http_module = _require_mcp_imports()

    url = str(spec.get("url") or "")
    if not url:
        raise ProbeFailure("missing url")
    stack = AsyncExitStack()
    try:
        read, write, _ = await stack.enter_async_context(stream_http_module.streamablehttp_client(url))
        session = await stack.enter_async_context(mcp_module.ClientSession(read, write))
        await session.initialize()
        await body(session, [])
    except Exception:
        with suppress(Exception):
            await stack.aclose()
        raise
    with suppress(Exception):
        await stack.aclose()


async def _probe_server(
    name: str,
    spec: dict[str, Any],
    *,
    list_only: bool,
    allow_missing_env: bool,
    include_auth: bool,
    timeout: float,
) -> tuple[str, str]:
    if name in AUTH_REQUIRED and not include_auth:
        return "skip", f"{name}: auth-required MCP skipped; use --include-auth to probe it"
    missing_env = _missing_forwarded_env(spec)
    if missing_env and name in STARTUP_ENV_REQUIRED:
        message = f"{name}: startup skipped; missing env: {', '.join(missing_env)}"
        if allow_missing_env:
            return "skip", message
        raise ProbeFailure(message)

    async def body(session: Any, missing_env: list[str]) -> None:
        if missing_env and not allow_missing_env:
            raise ProbeFailure(f"missing required environment variables: {', '.join(missing_env)}")
        tools_result = await session.list_tools()
        tool_names = {tool.name for tool in tools_result.tools}
        expected = EXPECTED_TOOLS.get(name, set())
        missing_tools = sorted(expected - tool_names)
        if missing_tools:
            raise ProbeFailure(f"missing expected tools: {', '.join(missing_tools)}")
        print(f"ok      {name} list_tools {len(tool_names)} tools", flush=True)
        if list_only:
            return
        called = await _safe_call(name, session, missing_env)
        if called:
            print(f"ok      {name} call_tool {called}", flush=True)
        elif missing_env:
            print(f"skip    {name} call_tool skipped; missing env: {', '.join(missing_env)}", flush=True)
        else:
            print(f"ok      {name} list-only capability has no safe call", flush=True)

    session_factory = _http_session if "url" in spec else _stdio_session
    try:
        async with asyncio.timeout(timeout):
            await session_factory(spec, body)
    except TimeoutError as exc:
        raise ProbeFailure(f"timed out after {timeout:g}s") from exc
    return "ok", f"{name}: capability smoke passed"


async def _probe_with_retries(
    name: str,
    spec: dict[str, Any],
    *,
    list_only: bool,
    allow_missing_env: bool,
    include_auth: bool,
    timeout: float,
    retries: int,
) -> tuple[str, str]:
    last_error: BaseException | None = None
    for attempt in range(1, retries + 1):
        try:
            return await _probe_server(
                name,
                spec,
                list_only=list_only,
                allow_missing_env=allow_missing_env,
                include_auth=include_auth,
                timeout=timeout,
            )
        except asyncio.CancelledError as exc:
            if _is_transient_external_failure(name, exc):
                _clear_current_task_cancellation()
                detail = _exception_chain_text(exc).splitlines()[0]
                return "skip", f"{name}: transient external MCP unavailable ({detail})"
            raise
        except Exception as exc:
            last_error = exc
            if _is_transient_external_failure(name, exc):
                _clear_current_task_cancellation()
                detail = _exception_chain_text(exc).splitlines()[0]
                return "skip", f"{name}: transient external MCP unavailable ({detail})"
            if attempt < retries:
                print(f"retry   {name} attempt {attempt} failed: {exc}", file=sys.stderr)
                await asyncio.sleep(min(2 * attempt, 5))
        except BaseExceptionGroup as exc:
            if _is_transient_external_failure(name, exc):
                _clear_current_task_cancellation()
                detail = _exception_chain_text(exc).splitlines()[0]
                return "skip", f"{name}: transient external MCP unavailable ({detail})"
            raise
    return "fail", f"{name}: {last_error}"


async def _main_async(args: argparse.Namespace) -> int:
    root = args.root.resolve()
    codex_home = args.codex_home.expanduser().resolve()
    servers = _load_servers(root, codex_home)
    selected = set(args.server or servers)
    skipped = set(args.skip_server or [])
    errors: list[str] = []

    print("rldyour MCP capability smoke")
    print(f"codex_home: {codex_home}")
    print(f"mode: {'list-only' if args.list_only else 'list+safe-call'}")

    for name, spec in servers.items():
        if name not in selected:
            continue
        if name in skipped:
            print(f"skip    {name}: skipped by --skip-server")
            continue
        status, message = await _probe_with_retries(
            name,
            spec,
            list_only=args.list_only,
            allow_missing_env=args.allow_missing_env,
            include_auth=args.include_auth,
            timeout=args.timeout,
            retries=args.retries,
        )
        if status == "fail":
            errors.append(message)
            print(f"fail    {message}", file=sys.stderr)
        elif status == "skip":
            print(f"skip    {message}")
        else:
            print(f"ok      {message}")

    if errors:
        print("\n".join(errors), file=sys.stderr)
        return 1

    print("MCP capability smoke passed.")
    return 0


def _parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Probe MCP initialize/list_tools/safe call_tool behavior.")
    parser.add_argument("--root", type=Path, default=Path.cwd(), help="Repository root.")
    parser.add_argument("--codex-home", type=Path, default=Path(os.environ.get("CODEX_HOME", "~/.codex")))
    parser.add_argument(
        "--mode",
        choices=("static", "local-launch"),
        default="local-launch",
        help="static parses repo MCP config only; local-launch probes the installed Codex MCP runtime.",
    )
    parser.add_argument("--json", action="store_true", help="Emit JSON. Supported for --mode static.")
    parser.add_argument("--server", action="append", help="Only probe this server. Repeatable.")
    parser.add_argument("--skip-server", action="append", help="Skip this server. Repeatable.")
    parser.add_argument("--list-only", action="store_true", help="Only initialize and list tools.")
    parser.add_argument(
        "--allow-missing-env",
        action="store_true",
        default=False,
        help="Allow capability probes when env vars are absent.",
    )
    parser.add_argument("--require-env", dest="allow_missing_env", action="store_false", help="Fail when env_vars are absent.")
    parser.add_argument("--include-auth", action="store_true", help="Probe auth-required MCP servers such as figma.")
    parser.add_argument("--timeout", type=float, default=90.0, help="Per-server timeout in seconds.")
    parser.add_argument("--retries", type=int, default=5, help="Per-server retry count.")
    return parser.parse_args()


def main() -> int:
    args = _parse_args()
    if args.mode == "static":
        return _main_static(args)
    if args.json:
        print("--json is only supported with --mode static", file=sys.stderr)
        return 2
    return asyncio.run(_main_async(args))


if __name__ == "__main__":
    raise SystemExit(main())
