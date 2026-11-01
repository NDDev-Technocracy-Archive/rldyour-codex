#!/usr/bin/env bash
set -euo pipefail

CODEX_HOME_DIR=${CODEX_HOME:-"$HOME/.codex"}
QUICK=0
STRICT_RUNTIME=0
OWNER_MODE=1

usage() {
  cat <<'EOF'
Usage: scripts/doctor_system_codex.sh [--codex-home PATH] [--quick] [--strict-runtime] [--owner-mode|--safe-mode] [--full]

Checks whether the current machine matches the rldyour Codex system setup.

Modes:
  --quick           Check installed files, config, and managed subagents only.
  --strict-runtime  Fail when enabled local MCP launchers or codex are missing.
  --owner-mode      Validate the owner-standard YOLO/full-auto profile. This is the default.
  --safe-mode       Validate the optional safe override profile.
  --full            Run the full doctor. This is the default.
EOF
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --codex-home)
      shift
      CODEX_HOME_DIR=${1:?--codex-home requires a path}
      ;;
    --quick)
      QUICK=1
      ;;
    --strict|--strict-runtime)
      STRICT_RUNTIME=1
      ;;
    --owner-mode)
      OWNER_MODE=1
      ;;
    --safe-mode)
      OWNER_MODE=0
      ;;
    --full)
      QUICK=0
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      printf 'Unknown argument: %s\n' "$1" >&2
      usage >&2
      exit 2
      ;;
  esac
  shift
done

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
if ROOT=$(git -C "$SCRIPT_DIR/.." rev-parse --show-toplevel 2>/dev/null); then
  :
else
  ROOT=$(cd "$SCRIPT_DIR/.." && pwd)
fi
SYSTEM_AGENTS="$ROOT/system/AGENTS.md"
SYSTEM_AGENT_DIR="$ROOT/system/agents"
SYSTEM_RULE_DIR="$ROOT/system/rules"
INSTALLED_AGENTS="$CODEX_HOME_DIR/AGENTS.md"
INSTALLED_AGENT_DIR="$CODEX_HOME_DIR/agents"
INSTALLED_RULE_DIR="$CODEX_HOME_DIR/rules"
CONFIG_PATH="$CODEX_HOME_DIR/config.toml"
YOLO_PROFILE_PATH="$CODEX_HOME_DIR/rldyour-yolo.config.toml"
SAFE_PROFILE_PATH="$CODEX_HOME_DIR/rldyour-safe.config.toml"
CACHE_ROOT="$CODEX_HOME_DIR/plugins/cache/rldyour-codex"
CODEX_CMD=${CODEX_BIN:-$(command -v codex 2>/dev/null || true)}
UVX_CMD=${UVX_BIN:-$(command -v uvx 2>/dev/null || true)}
BUNX_CMD=${BUNX_BIN:-$(command -v bunx 2>/dev/null || true)}
DART_CMD=${DART_BIN:-$(command -v dart 2>/dev/null || true)}

FAILURES=0
WARNINGS=0

pass() {
  printf 'ok      %s\n' "$1"
}

warn() {
  WARNINGS=$((WARNINGS + 1))
  printf 'warn    %s\n' "$1" >&2
}

fail() {
  FAILURES=$((FAILURES + 1))
  printf 'fail    %s\n' "$1" >&2
}

section() {
  printf '\n== %s ==\n' "$1"
}

section "Files"
if [ -f "$INSTALLED_AGENTS" ]; then
  pass "$INSTALLED_AGENTS exists"
  if cmp -s "$SYSTEM_AGENTS" "$INSTALLED_AGENTS"; then
    pass "system AGENTS matches repository template"
  else
    fail "system AGENTS differs from repository template"
  fi
else
  fail "$INSTALLED_AGENTS missing"
fi

if [ -f "$CODEX_HOME_DIR/AGENTS.override.md" ]; then
  warn "$CODEX_HOME_DIR/AGENTS.override.md exists and overrides AGENTS.md"
else
  pass "no global AGENTS.override.md"
fi

if [ -f "$CONFIG_PATH" ]; then
  pass "$CONFIG_PATH exists"
else
  fail "$CONFIG_PATH missing"
fi

section "Config"
if [ -f "$CONFIG_PATH" ]; then
  export RLDYOUR_CODEX_CONFIG="$CONFIG_PATH"
  export RLDYOUR_YOLO_PROFILE_CONFIG="$YOLO_PROFILE_PATH"
  export RLDYOUR_SAFE_PROFILE_CONFIG="$SAFE_PROFILE_PATH"
  export RLDYOUR_REPO_ROOT="$ROOT"
  export RLDYOUR_SYSTEM_AGENT_DIR="$SYSTEM_AGENT_DIR"
  export RLDYOUR_MARKETPLACE_CONFIG="$ROOT/.agents/plugins/marketplace.json"
  export RLDYOUR_MCP_CONFIG="$ROOT/plugins/rldyour-mcps/.mcp.json"
  export RLDYOUR_OWNER_MODE="$OWNER_MODE"
  python3 <<'PY' || exit_code=$?
from __future__ import annotations

import json
import os
import re
import sys
import tomllib
from pathlib import Path

path = Path(os.environ["RLDYOUR_CODEX_CONFIG"])
yolo_profile_path = Path(os.environ["RLDYOUR_YOLO_PROFILE_CONFIG"])
safe_profile_path = Path(os.environ["RLDYOUR_SAFE_PROFILE_CONFIG"])
repo_root = os.environ["RLDYOUR_REPO_ROOT"]
codex_home = path.parent
system_agent_dir = Path(os.environ["RLDYOUR_SYSTEM_AGENT_DIR"])
marketplace_config_path = Path(os.environ["RLDYOUR_MARKETPLACE_CONFIG"])
mcp_config_path = Path(os.environ["RLDYOUR_MCP_CONFIG"])
browser_contract_path = Path(repo_root) / "config" / "rldyour-contract.json"
owner_mode = os.environ.get("RLDYOUR_OWNER_MODE") == "1"
text = path.read_text(encoding="utf-8")
config_data = tomllib.loads(text)
schema_comment = "#:schema https://developers.openai.com/codex/config-schema.json"


def load_toml(path: Path) -> dict:
    if not path.exists():
        return {}
    try:
        data = tomllib.loads(path.read_text(encoding="utf-8"))
    except tomllib.TOMLDecodeError:
        return {"__parse_error__": True}
    return data if isinstance(data, dict) else {}


# Same gating as install_system_codex.sh: cmux is a macOS application, so the
# orchestrator plugin is never installed or expected on Linux/WSL/Windows.
MACOS_ONLY_PLUGINS = {"rldyour-orchestrator"}


def load_rldyour_plugins(path: Path) -> list[str]:
    data = json.loads(path.read_text(encoding="utf-8"))
    entries = data.get("plugins")
    if not isinstance(entries, list):
        raise SystemExit(f"{path}: plugins must be a list")
    result: list[str] = []
    for index, entry in enumerate(entries):
        if not isinstance(entry, dict):
            raise SystemExit(f"{path}: plugins[{index}] must be an object")
        name = entry.get("name")
        source = entry.get("source")
        if not isinstance(name, str) or not name:
            raise SystemExit(f"{path}: plugins[{index}] missing name")
        if not isinstance(source, dict):
            raise SystemExit(f"{path}: {name} missing source")
        rel_path = source.get("path")
        if source.get("source") != "local" or rel_path != f"./plugins/{name}":
            raise SystemExit(f"{path}: {name} must use local source ./plugins/{name}")
        if name in MACOS_ONLY_PLUGINS and sys.platform != "darwin":
            continue
        if name.startswith("rldyour-"):
            result.append(name)
    if not result:
        raise SystemExit(f"{path}: no rldyour plugins found")
    return result


def load_disabled_codex_surfaces(path: Path) -> tuple[list[str], list[str]]:
    contract = json.loads(path.read_text(encoding="utf-8"))
    surfaces = ((contract.get("browser_providers") or {}).get("disabled_codex_surfaces") or {})
    plugins = surfaces.get("plugins")
    servers = surfaces.get("mcp_servers")
    required_plugins = {"browser@openai-bundled"}
    required_servers = {"computer-use", "node_repl"}
    if plugins != sorted(required_plugins):
        raise SystemExit(
            f"{path}: browser_providers.disabled_codex_surfaces.plugins must be "
            f"{sorted(required_plugins)!r}"
        )
    if servers != sorted(required_servers):
        raise SystemExit(
            f"{path}: browser_providers.disabled_codex_surfaces.mcp_servers must be "
            f"{sorted(required_servers)!r}"
        )
    return sorted(required_plugins), sorted(required_servers)


disabled_codex_plugins, disabled_codex_mcp_servers = load_disabled_codex_surfaces(browser_contract_path)

checks = []
browser_surface_failures: list[str] = []


def add_browser_surface_check(label: str, ok: bool) -> None:
    checks.append((label, ok))
    if not ok:
        browser_surface_failures.append(label)


checks.append(("config schema comment", text.startswith(f"{schema_comment}\n")))
marketplace = (config_data.get("marketplaces") or {}).get("rldyour-codex") or {}
checks.append(("marketplace source", marketplace.get("source") == repo_root and marketplace.get("source_type") == "local"))
project = (config_data.get("projects") or {}).get(repo_root) or {}
checks.append(("repo trusted", project.get("trust_level") == "trusted"))

features = config_data.get("features") or {}
checks.append(("hooks feature enabled", features.get("hooks") is True))
checks.append(("multi-agent feature enabled", features.get("multi_agent") is True))
deprecated_feature_keys = {
    "codex_hooks",
    "plugin_hooks",
    "use_legacy_landlock",
    "web_search",
    "web_search_cached",
    "web_search_request",
}
for feature_key in sorted(deprecated_feature_keys):
    checks.append((f"deprecated feature {feature_key} absent", feature_key not in features))

checks.append(("legacy experimental_instructions_file absent", "experimental_instructions_file" not in config_data))
checks.append(("legacy background_terminal_timeout absent", "background_terminal_timeout" not in config_data))
checks.append(("legacy experimental_use_unified_exec_tool absent", "experimental_use_unified_exec_tool" not in config_data))
checks.append(("suppress unstable feature warning enabled", config_data.get("suppress_unstable_features_warning") is True))
checks.append(("approval policy on-failure absent", config_data.get("approval_policy") != "on-failure"))
memories_config = config_data.get("memories") or {}
checks.append((
    "legacy memories.no_memories_if_mcp_or_web_search absent",
    "no_memories_if_mcp_or_web_search" not in memories_config,
))

checks.append(("legacy profile selector absent", "profile" not in config_data))
if owner_mode:
    checks.append(("owner mode approval policy never", config_data.get("approval_policy") == "never"))
    checks.append(("owner mode sandbox danger full access", config_data.get("sandbox_mode") == "danger-full-access"))
    checks.append(("owner mode default permissions absent", "default_permissions" not in config_data))
else:
    checks.append(("safe approval policy on-request", config_data.get("approval_policy") == "on-request"))
    checks.append(("safe sandbox workspace-write", config_data.get("sandbox_mode") == "workspace-write"))
    checks.append(("safe mode default permissions absent", "default_permissions" not in config_data))
checks.append(("default model gpt-5.5", config_data.get("model") == "gpt-5.5"))
checks.append(("default reasoning effort xhigh", config_data.get("model_reasoning_effort") == "xhigh"))
checks.append(("centrally managed startup update check disabled", config_data.get("check_for_update_on_startup") is False))

checks.append(("legacy profiles table absent", "profiles" not in config_data))
safe_profile = load_toml(safe_profile_path)
checks.append(("profile file rldyour-safe exists", safe_profile_path.exists()))
checks.append(("profile rldyour-safe parse", "__parse_error__" not in safe_profile))
checks.append(("profile rldyour-safe approval policy", safe_profile.get("approval_policy") == "on-request"))
checks.append(("profile rldyour-safe sandbox", safe_profile.get("sandbox_mode") == "workspace-write"))
checks.append(("profile rldyour-safe startup update check disabled", safe_profile.get("check_for_update_on_startup") is False))
checks.append(("profile rldyour-safe legacy selector absent", "profile" not in safe_profile))
yolo_profile = load_toml(yolo_profile_path)
checks.append(("profile file rldyour-yolo exists", yolo_profile_path.exists()))
checks.append(("profile rldyour-yolo parse", "__parse_error__" not in yolo_profile))
checks.append(("profile rldyour-yolo approval policy", yolo_profile.get("approval_policy") == "never"))
checks.append(("profile rldyour-yolo sandbox", yolo_profile.get("sandbox_mode") == "danger-full-access"))
checks.append(("profile rldyour-yolo startup update check disabled", yolo_profile.get("check_for_update_on_startup") is False))
checks.append(("profile rldyour-yolo default permissions absent", "default_permissions" not in yolo_profile))
checks.append(("profile rldyour-yolo legacy selector absent", "profile" not in yolo_profile))
profiles_config = {
    "rldyour-safe": safe_profile,
    "rldyour-yolo": yolo_profile,
}
for profile_name, profile_data in sorted(profiles_config.items()):
    if not isinstance(profile_data, dict):
        continue
    checks.append((f"profile {profile_name} on-failure absent", profile_data.get("approval_policy") != "on-failure"))
    checks.append((
        f"profile {profile_name} legacy unified exec absent",
        "experimental_use_unified_exec_tool" not in profile_data,
    ))
    checks.append((
        f"profile {profile_name} permission dialect not mixed",
        not ("sandbox_mode" in profile_data and "default_permissions" in profile_data),
    ))

checks.append((
    "base config permission dialect not mixed",
    not ("sandbox_mode" in config_data and "default_permissions" in config_data),
))

agents_config = config_data.get("agents") or {}
checks.append(("agents max_threads", agents_config.get("max_threads") == 6))
checks.append(("agents max_depth", agents_config.get("max_depth") == 1))
configured_agents = agents_config
for agent_path in sorted(system_agent_dir.glob("*.toml")):
    agent_data = tomllib.loads(agent_path.read_text(encoding="utf-8"))
    name = agent_data.get("name")
    if not isinstance(name, str):
        checks.append((f"agent {agent_path.name} name", False))
        continue
    agent_config = configured_agents.get(name) or {}
    expected_path = str(codex_home / "agents" / agent_path.name)
    checks.append((f"agent configured {name}", agent_config.get("config_file") == expected_path))
    checks.append((f"agent description {name}", agent_config.get("description") == agent_data.get("description")))

rldyour_plugins = [f"{name}@rldyour-codex" for name in load_rldyour_plugins(marketplace_config_path)]
plugins = ["gmail@openai-curated", "github@openai-curated", *rldyour_plugins]
configured_plugins = config_data.get("plugins") or {}
for plugin in plugins:
    plugin_config = configured_plugins.get(plugin) or {}
    checks.append((f"plugin enabled {plugin}", plugin_config.get("enabled") is True))
for plugin in disabled_codex_plugins:
    plugin_config = configured_plugins.get(plugin)
    add_browser_surface_check(
        f"app-managed browser plugin explicitly disabled {plugin}",
        isinstance(plugin_config, dict) and plugin_config.get("enabled") is False,
    )
expected_rldyour_plugins = set(rldyour_plugins)
for plugin in sorted(configured_plugins):
    if plugin.startswith("rldyour-") and plugin.endswith("@rldyour-codex") and plugin not in expected_rldyour_plugins:
        checks.append((f"stale rldyour plugin absent {plugin}", False))

mcp_servers = sorted(json.loads(mcp_config_path.read_text(encoding="utf-8"))["mcpServers"])
configured_mcp_servers = config_data.get("mcp_servers") or {}
approved_mcp_servers = set(mcp_servers)
allowed_disabled_mcp_servers = set(disabled_codex_mcp_servers)
for server in mcp_servers:
    checks.append((f"mcp configured {server}", server in configured_mcp_servers))
for server in sorted(configured_mcp_servers):
    checks.append((f"mcp server approved {server}", server in approved_mcp_servers | allowed_disabled_mcp_servers))
for server in disabled_codex_mcp_servers:
    server_config = configured_mcp_servers.get(server)
    add_browser_surface_check(
        f"app-managed MCP disabled when present {server}",
        server_config is None or (isinstance(server_config, dict) and server_config.get("enabled") is False),
    )

tool_approvals = {
    "sequential-thinking": {"sequentialthinking": "approve"},
    "deepwiki": {
        "ask_wiki_question": "approve",
        "read_wiki_structure": "approve",
    },
    "grep": {"searchGitHub": "approve"},
}
for server, tools in tool_approvals.items():
    server_config = configured_mcp_servers.get(server) or {}
    configured_tools = server_config.get("tools") or {}
    for tool, expected_mode in tools.items():
        tool_config = configured_tools.get(tool) or {}
        checks.append((f"mcp tool approval {server}.{tool}", tool_config.get("approval_mode") == expected_mode))

failed = False
for label, ok in checks:
    if ok:
        print(f"ok      {label}")
    else:
        print(f"fail    {label}", file=sys.stderr)
        failed = True

if browser_surface_failures:
    print(
        "fail    forbidden raw/in-app/computer-use Codex surface is active or was reinjected; "
        f"rerun {repo_root}/scripts/install_system_codex.sh --apply --codex-home {codex_home} "
        "and restart Codex",
        file=sys.stderr,
    )

raise SystemExit(1 if failed else 0)
PY
  if [ "${exit_code:-0}" -ne 0 ]; then
    FAILURES=$((FAILURES + 1))
  fi
fi

section "Subagents"
export RLDYOUR_SYSTEM_AGENT_DIR="$SYSTEM_AGENT_DIR"
export RLDYOUR_INSTALLED_AGENT_DIR="$INSTALLED_AGENT_DIR"
export RLDYOUR_MCP_CONFIG="$ROOT/plugins/rldyour-mcps/.mcp.json"
python3 <<'PY' || FAILURES=$((FAILURES + 1))
from __future__ import annotations

import json
import os
import sys
import tomllib
from pathlib import Path

system_dir = Path(os.environ["RLDYOUR_SYSTEM_AGENT_DIR"])
installed_dir = Path(os.environ["RLDYOUR_INSTALLED_AGENT_DIR"])
mcp_config_path = Path(os.environ["RLDYOUR_MCP_CONFIG"])
mcp_registry = json.loads(mcp_config_path.read_text(encoding="utf-8"))["mcpServers"]
valid_mcp_servers = set(mcp_registry)
temporary_allowlist = {
    "context7",
    "deepwiki",
    "grep",
    "openaiDeveloperDocs",
    "sequential-thinking",
    "serena",
}
temporary_builtins = {"codex_apps"}
mcp_transport_keys = {
    "args",
    "bearer_token_env_var",
    "command",
    "cwd",
    "disabled_tools",
    "enabled_tools",
    "env",
    "env_http_headers",
    "env_vars",
    "experimental_environment",
    "http_headers",
    "oauth_resource",
    "required",
    "scopes",
    "startup_timeout_ms",
    "startup_timeout_sec",
    "tool_timeout_sec",
    "url",
}
errors = False

for source in sorted(system_dir.glob("*.toml")):
    target = installed_dir / source.name
    label = source.stem
    if not target.is_file():
        print(f"fail    subagent installed {label}", file=sys.stderr)
        errors = True
        continue
    source_text = source.read_text(encoding="utf-8")
    target_text = target.read_text(encoding="utf-8")
    if source_text == target_text:
        print(f"ok      subagent file in sync {label}")
    else:
        print(f"fail    subagent file differs {label}", file=sys.stderr)
        errors = True
    try:
        data = tomllib.loads(source_text)
    except Exception as exc:
        print(f"fail    subagent TOML parses {label}: {exc}", file=sys.stderr)
        errors = True
        continue
    checks = {
        "name": data.get("name") == label,
        "model gpt-5.5": data.get("model") == "gpt-5.5",
        "reasoning medium": data.get("model_reasoning_effort") == "medium",
        "description": isinstance(data.get("description"), str) and bool(data.get("description", "").strip()),
        "developer instructions": isinstance(data.get("developer_instructions"), str) and bool(data.get("developer_instructions", "").strip()),
        "temporary MCP policy": isinstance(data.get("mcp_servers"), dict),
    }
    for check, ok in checks.items():
        if ok:
            print(f"ok      subagent {label} {check}")
        else:
            print(f"fail    subagent {label} {check}", file=sys.stderr)
            errors = True
    mcp_servers = data.get("mcp_servers") or {}
    known_servers = valid_mcp_servers | temporary_builtins
    for server in sorted(mcp_servers):
        if server not in known_servers:
            print(f"fail    subagent {label} unknown MCP policy {server}", file=sys.stderr)
            errors = True
    for server in sorted(valid_mcp_servers - temporary_allowlist):
        if not isinstance(mcp_servers.get(server), dict) or mcp_servers[server].get("enabled") is not False:
            print(f"fail    subagent {label} disables temporary non-core MCP {server}", file=sys.stderr)
            errors = True
        else:
            print(f"ok      subagent {label} disables temporary non-core MCP {server}")
            server_config = mcp_servers[server]
            if "command" not in server_config and "url" not in server_config:
                print(f"fail    subagent {label} MCP {server} has disabled policy without transport", file=sys.stderr)
                errors = True
            registry_spec = mcp_registry.get(server) or {}
            for key in sorted(registry_spec):
                if key not in mcp_transport_keys:
                    continue
                if server_config.get(key) != registry_spec[key]:
                    print(f"fail    subagent {label} MCP {server} transport drift: {key}", file=sys.stderr)
                    errors = True
    for server in sorted(temporary_allowlist & valid_mcp_servers):
        if isinstance(mcp_servers.get(server), dict) and mcp_servers[server].get("enabled") is False:
            print(f"fail    subagent {label} does not disable allowlisted MCP {server}", file=sys.stderr)
            errors = True
    for server in sorted(temporary_builtins):
        if isinstance(mcp_servers.get(server), dict):
            print(f"fail    subagent {label} declares built-in MCP surface {server} under mcp_servers", file=sys.stderr)
            errors = True

raise SystemExit(1 if errors else 0)
PY

section "Execpolicy rules"
export RLDYOUR_SYSTEM_RULE_DIR="$SYSTEM_RULE_DIR"
export RLDYOUR_INSTALLED_RULE_DIR="$INSTALLED_RULE_DIR"
python3 <<'PY' || FAILURES=$((FAILURES + 1))
from __future__ import annotations

import os
import sys
from pathlib import Path

system_dir = Path(os.environ["RLDYOUR_SYSTEM_RULE_DIR"])
installed_dir = Path(os.environ["RLDYOUR_INSTALLED_RULE_DIR"])
errors = False

for source in sorted(system_dir.glob("*.rules")):
    target = installed_dir / source.name
    if not target.is_file():
        print(f"fail    execpolicy rule installed {source.name}", file=sys.stderr)
        errors = True
        continue
    if source.read_text(encoding="utf-8") == target.read_text(encoding="utf-8"):
        print(f"ok      execpolicy rule in sync {source.name}")
    else:
        print(f"fail    execpolicy rule differs {source.name}", file=sys.stderr)
        errors = True

raise SystemExit(1 if errors else 0)
PY

if [ "$STRICT_RUNTIME" -eq 1 ]; then
  section "Runtime prerequisites"
  if UVX_BIN="${UVX_CMD:-uvx}" \
    BUNX_BIN="${BUNX_CMD:-bunx}" \
    DART_BIN="${DART_CMD:-dart}" \
    CODEX_BIN="${CODEX_CMD:-}" \
    python3 "$ROOT/scripts/validate_runtime_prereqs.py" \
      --mcp-config "$ROOT/plugins/rldyour-mcps/.mcp.json" \
      --require-codex \
      --strict; then
    pass "strict runtime prerequisites"
  else
    fail "strict runtime prerequisites"
  fi
fi

if [ "$QUICK" -eq 1 ]; then
  section "Summary"
  printf 'warnings: %s\n' "$WARNINGS"
  printf 'failures: %s\n' "$FAILURES"
  if [ "$FAILURES" -ne 0 ]; then
    exit 1
  fi
  printf 'System Codex quick doctor passed.\n'
  exit 0
fi

section "Repository validation"
if "$ROOT/scripts/validate_marketplace.sh"; then
  pass "repository marketplace validation"
else
  fail "repository marketplace validation"
fi

section "MCP runtime"
if [ -n "$CODEX_CMD" ]; then
  if env CODEX_HOME="$CODEX_HOME_DIR" "$CODEX_CMD" mcp list >/tmp/rldyour-codex-mcp-list.txt 2>/tmp/rldyour-codex-mcp-list.err; then
    while IFS= read -r server; do
      [ -n "$server" ] || continue
      if grep -q "^${server}[[:space:]]" /tmp/rldyour-codex-mcp-list.txt; then
        pass "mcp listed $server"
      else
        fail "mcp not listed $server"
      fi
    done < <(python3 - "$ROOT/plugins/rldyour-mcps/.mcp.json" <<'PY'
from __future__ import annotations

import json
import sys
from pathlib import Path

servers = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))["mcpServers"]
print("\n".join(sorted(servers)))
PY
)
    if grep -E '^context7[[:space:]].*CONTEXT7_API_KEY=\*+' /tmp/rldyour-codex-mcp-list.txt >/dev/null; then
      pass "context7 runtime environment registered"
    else
      warn "context7 runtime environment is not visible in codex mcp list output"
    fi
  else
    fail "codex mcp list failed"
    sed -n '1,40p' /tmp/rldyour-codex-mcp-list.err >&2 || true
  fi
else
  fail "codex command missing"
fi

section "Plugin cache"
if python3 "$ROOT/scripts/plugin_cache_contract.py" --cache-root "$CACHE_ROOT" --include-local verify; then
  :
else
  fail "plugin cache parity"
fi

section "Hook trust"
if [ -n "$CODEX_CMD" ]; then
  export RLDYOUR_CODEX_CMD="$CODEX_CMD"
  export RLDYOUR_CODEX_HOME="$CODEX_HOME_DIR"
  export RLDYOUR_REPO_ROOT="$ROOT"
  python3 <<'PY' || FAILURES=$((FAILURES + 1))
from __future__ import annotations

import json
import os
import queue
import subprocess
import threading
import time
from pathlib import Path

codex_cmd = os.environ["RLDYOUR_CODEX_CMD"]
codex_home = os.environ["RLDYOUR_CODEX_HOME"]
repo_root = Path(os.environ["RLDYOUR_REPO_ROOT"])


def timeout_seconds() -> float:
    raw = os.environ.get("CODEX_APP_SERVER_TIMEOUT_SECONDS", "10")
    try:
        return max(0.1, float(raw))
    except ValueError:
        return 10.0


app_server_timeout = timeout_seconds()


def expected_hook_count() -> int:
    total = 0
    for hooks_json in sorted(repo_root.glob("plugins/rldyour-*/hooks.json")):
        data = json.loads(hooks_json.read_text(encoding="utf-8"))
        for groups in data.get("hooks", {}).values():
            if not isinstance(groups, list):
                continue
            for group in groups:
                if isinstance(group, dict):
                    total += sum(1 for hook in group.get("hooks", []) if isinstance(hook, dict) and hook.get("type") == "command")
    return total


proc = subprocess.Popen(
    [codex_cmd, "app-server", "--listen", "stdio://"],
    stdin=subprocess.PIPE,
    stdout=subprocess.PIPE,
    stderr=subprocess.PIPE,
    text=True,
    bufsize=1,
    env={**os.environ, "CODEX_HOME": codex_home},
)
assert proc.stdin is not None
assert proc.stdout is not None

line_queue = queue.Queue()


def read_stdout() -> None:
    try:
        for stdout_line in proc.stdout:
            line_queue.put(stdout_line)
    finally:
        line_queue.put(None)


threading.Thread(target=read_stdout, daemon=True).start()


def send(payload: dict[str, object]) -> None:
    proc.stdin.write(json.dumps(payload) + "\n")
    proc.stdin.flush()


def recv(target_id: int) -> dict[str, object]:
    deadline = time.monotonic() + app_server_timeout
    while True:
        remaining = deadline - time.monotonic()
        if remaining <= 0:
            raise TimeoutError(f"codex app-server did not respond to request {target_id} within {app_server_timeout:g}s")
        try:
            line = line_queue.get(timeout=remaining)
        except queue.Empty as exc:
            raise TimeoutError(
                f"codex app-server did not respond to request {target_id} within {app_server_timeout:g}s"
            ) from exc
        if line is None:
            stderr = proc.stderr.read() if proc.stderr is not None and proc.poll() is not None else ""
            raise RuntimeError(f"codex app-server exited before response {target_id}: {stderr}")
        payload = json.loads(line)
        if payload.get("id") == target_id:
            return payload


def checked_response(target_id: int) -> dict[str, object]:
    payload = recv(target_id)
    if "error" in payload:
        raise RuntimeError(json.dumps(payload["error"], ensure_ascii=False))
    return payload


failed = False

try:
    send(
        {
            "id": 1,
            "method": "initialize",
            "params": {
                "clientInfo": {
                    "name": "rldyour_codex_doctor",
                    "title": "rldyour Codex doctor",
                    "version": "0.0.0",
                },
                "capabilities": {"experimentalApi": True},
            },
        }
    )
    checked_response(1)
    send({"id": 2, "method": "hooks/list", "params": {"cwds": [str(repo_root)]}})
    response = checked_response(2)
    data = response.get("result", {}).get("data", [])  # type: ignore[union-attr]
    hooks = data[0].get("hooks", []) if data else []
    rldyour_hooks = [
        hook
        for hook in hooks
        if isinstance(hook, dict)
        and isinstance(hook.get("pluginId"), str)
        and hook["pluginId"].startswith("rldyour-")
        and hook["pluginId"].endswith("@rldyour-codex")
    ]
    expected = expected_hook_count()
    if len(rldyour_hooks) == expected:
        print(f"ok      rldyour plugin hook count {expected}")
    else:
        print(f"fail    rldyour plugin hook count {len(rldyour_hooks)} expected {expected}", file=os.sys.stderr)
        failed = True
    for hook in rldyour_hooks:
        key = hook.get("key", "unknown")
        trust_status = hook.get("trustStatus")
        enabled = hook.get("enabled")
        current_hash = hook.get("currentHash")
        if trust_status == "trusted" and enabled is True and isinstance(current_hash, str):
            print(f"ok      hook trusted {key}")
        else:
            print(
                f"fail    hook trust {key}: status={trust_status!r} enabled={enabled!r} hash={current_hash!r}",
                file=os.sys.stderr,
            )
            failed = True
finally:
    proc.terminate()
    try:
        proc.wait(timeout=3)
    except subprocess.TimeoutExpired:
        proc.kill()

raise SystemExit(1 if failed else 0)
PY
else
  fail "codex command missing for hook trust check"
fi

section "Summary"
printf 'warnings: %s\n' "$WARNINGS"
printf 'failures: %s\n' "$FAILURES"

if [ "$FAILURES" -ne 0 ]; then
  exit 1
fi

printf 'System Codex doctor passed.\n'
