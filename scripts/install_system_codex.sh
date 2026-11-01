#!/usr/bin/env bash
set -euo pipefail

APPLY=0
TRUST_HOME=0
STRICT_RUNTIME=0
OWNER_MODE=1
CODEX_HOME_DIR=${CODEX_HOME:-"$HOME/.codex"}

usage() {
  cat <<'EOF'
Usage: scripts/install_system_codex.sh [--dry-run] [--apply] [--codex-home PATH] [--trust-home] [--strict-runtime] [--owner-mode|--safe-mode]

Installs the current rldyour Codex system state into CODEX_HOME.

Default mode is --dry-run. Use --apply to write files.

Managed state:
- CODEX_HOME/AGENTS.md from system/AGENTS.md
- CODEX_HOME/agents/*.toml from system/agents/*.toml
- rldyour-codex marketplace registration
- enabled rldyour plugins plus curated GitHub and Gmail plugins
- disabled app-managed browser, Node REPL, and computer-use surfaces
- hooks feature flag
- plugin hook trust state
- multi-agent feature flag
- Codex config deprecated-key migration for managed global setup
- owner-standard YOLO/full-auto permission defaults by default
- optional safe permission override only with --safe-mode
- owner-selected model defaults
- owner-selected subagent model defaults
- rldyour MCP server definitions
- rldyour MCP tool approval overrides
- active rldyour plugin cache copies
- trusted hashes for installed rldyour plugin hooks

Secrets are not installed. Keep Context7, Figma, GitHub, Gmail, and other auth outside this repository.
EOF
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --dry-run)
      APPLY=0
      ;;
    --apply)
      APPLY=1
      ;;
    --codex-home)
      shift
      CODEX_HOME_DIR=${1:?--codex-home requires a path}
      ;;
    --trust-home)
      TRUST_HOME=1
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
CONFIG_PATH="$CODEX_HOME_DIR/config.toml"
YOLO_PROFILE_PATH="$CODEX_HOME_DIR/rldyour-yolo.config.toml"
SAFE_PROFILE_PATH="$CODEX_HOME_DIR/rldyour-safe.config.toml"
CODEX_AGENT_DIR="$CODEX_HOME_DIR/agents"
CODEX_RULE_DIR="$CODEX_HOME_DIR/rules"
CACHE_ROOT="$CODEX_HOME_DIR/plugins/cache/rldyour-codex"
BACKUP_ROOT="$CODEX_HOME_DIR/backups/rldyour-codex"
TIMESTAMP=$(date -u +%Y%m%dT%H%M%SZ)
BACKUP_DIR="$BACKUP_ROOT/$TIMESTAMP"

UVX_CMD=${UVX_BIN:-$(command -v uvx 2>/dev/null || true)}
BUNX_CMD=${BUNX_BIN:-$(command -v bunx 2>/dev/null || true)}
DART_CMD=${DART_BIN:-$(command -v dart 2>/dev/null || true)}
CODEX_CMD=${CODEX_BIN:-$(command -v codex 2>/dev/null || true)}

if [ -z "$UVX_CMD" ]; then
  UVX_CMD="uvx"
  printf 'warning: uvx not found on PATH; config will use "uvx"\n' >&2
fi
if [ -z "$BUNX_CMD" ]; then
  BUNX_CMD="bunx"
  printf 'warning: bunx not found on PATH; config will use "bunx"\n' >&2
fi
if [ -z "$DART_CMD" ]; then
  DART_CMD="dart"
  printf 'warning: dart not found on PATH; config will use "dart"\n' >&2
fi

if [ ! -f "$SYSTEM_AGENTS" ]; then
  printf 'Missing system AGENTS template: %s\n' "$SYSTEM_AGENTS" >&2
  exit 1
fi
if [ ! -d "$SYSTEM_AGENT_DIR" ]; then
  printf 'Missing system agent directory: %s\n' "$SYSTEM_AGENT_DIR" >&2
  exit 1
fi
if [ ! -d "$SYSTEM_RULE_DIR" ]; then
  printf 'Missing system rules directory: %s\n' "$SYSTEM_RULE_DIR" >&2
  exit 1
fi

run_or_print() {
  if [ "$APPLY" -eq 1 ]; then
    "$@"
  else
    printf 'dry-run:'
    printf ' %q' "$@"
    printf '\n'
  fi
}

backup_file() {
  local path=$1
  if [ "$APPLY" -ne 1 ] || [ ! -e "$path" ]; then
    return 0
  fi
  mkdir -p "$BACKUP_DIR"
  cp -p "$path" "$BACKUP_DIR/"
  printf 'backed up %s -> %s/\n' "$path" "$BACKUP_DIR"
}

backup_agent_file() {
  local path=$1
  if [ "$APPLY" -ne 1 ] || [ ! -e "$path" ]; then
    return 0
  fi
  mkdir -p "$BACKUP_DIR/agents"
  cp -p "$path" "$BACKUP_DIR/agents/"
  printf 'backed up %s -> %s/agents/\n' "$path" "$BACKUP_DIR"
}

backup_rule_file() {
  local path=$1
  if [ "$APPLY" -ne 1 ] || [ ! -e "$path" ]; then
    return 0
  fi
  mkdir -p "$BACKUP_DIR/rules"
  cp -p "$path" "$BACKUP_DIR/rules/"
  printf 'backed up %s -> %s/rules/\n' "$path" "$BACKUP_DIR"
}

print_plan() {
  cat <<EOF
rldyour Codex system install
mode: $([ "$APPLY" -eq 1 ] && printf 'apply' || printf 'dry-run')
repo: $ROOT
codex home: $CODEX_HOME_DIR
system AGENTS: $CODEX_HOME_DIR/AGENTS.md
system agents: $CODEX_AGENT_DIR
system rules: $CODEX_RULE_DIR
config: $CONFIG_PATH
yolo profile: $YOLO_PROFILE_PATH
safe profile: $SAFE_PROFILE_PATH
cache root: $CACHE_ROOT
uvx: $UVX_CMD
bunx: $BUNX_CMD
dart: $DART_CMD
codex: ${CODEX_CMD:-not found}
trust home: $TRUST_HOME
strict runtime: $STRICT_RUNTIME
full-auto standard mode: $OWNER_MODE
EOF
}

validate_existing_config() {
  if [ ! -f "$CONFIG_PATH" ]; then
    return 0
  fi
  python3 - "$CONFIG_PATH" <<'PY'
from __future__ import annotations

import sys
import tomllib
from pathlib import Path

path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8")
if not text.strip():
    raise SystemExit(0)
try:
    tomllib.loads(text)
except tomllib.TOMLDecodeError as exc:
    raise SystemExit(
        f"Malformed existing Codex config: {path}: {exc}. "
        "Repair the file or restore an installer backup before running install_system_codex.sh."
    )
PY
}

validate_runtime_prereqs() {
  if [ "$STRICT_RUNTIME" -ne 1 ]; then
    return 0
  fi
  UVX_BIN="$UVX_CMD" \
    BUNX_BIN="$BUNX_CMD" \
    DART_BIN="$DART_CMD" \
    CODEX_BIN="${CODEX_CMD:-}" \
    python3 "$ROOT/scripts/validate_runtime_prereqs.py" \
      --mcp-config "$ROOT/plugins/rldyour-mcps/.mcp.json" \
      --require-codex \
      --strict
}

patch_config() {
  export RLDYOUR_CODEX_CONFIG="$CONFIG_PATH"
  export RLDYOUR_YOLO_PROFILE_CONFIG="$YOLO_PROFILE_PATH"
  export RLDYOUR_SAFE_PROFILE_CONFIG="$SAFE_PROFILE_PATH"
  export RLDYOUR_REPO_ROOT="$ROOT"
  export RLDYOUR_HOME="$HOME"
  export RLDYOUR_UVX_CMD="$UVX_CMD"
  export RLDYOUR_BUNX_CMD="$BUNX_CMD"
  export RLDYOUR_DART_CMD="$DART_CMD"
  export RLDYOUR_TRUST_HOME="$TRUST_HOME"
  export RLDYOUR_OWNER_MODE="$OWNER_MODE"
  export RLDYOUR_DRY_RUN=$((1 - APPLY))
  export RLDYOUR_MCP_CONFIG="$ROOT/plugins/rldyour-mcps/.mcp.json"
  export RLDYOUR_SYSTEM_AGENT_DIR="$SYSTEM_AGENT_DIR"
  export RLDYOUR_CODEX_AGENT_DIR="$CODEX_AGENT_DIR"
  export RLDYOUR_MARKETPLACE_CONFIG="$ROOT/.agents/plugins/marketplace.json"

  python3 <<'PY'
from __future__ import annotations

import json
import os
import re
import sys
import tomllib
from pathlib import Path

SCHEMA_COMMENT = "#:schema https://developers.openai.com/codex/config-schema.json"

config_path = Path(os.environ["RLDYOUR_CODEX_CONFIG"])
yolo_profile_path = Path(os.environ["RLDYOUR_YOLO_PROFILE_CONFIG"])
safe_profile_path = Path(os.environ["RLDYOUR_SAFE_PROFILE_CONFIG"])
repo_root = os.environ["RLDYOUR_REPO_ROOT"]
home = os.environ["RLDYOUR_HOME"]
uvx_cmd = os.environ["RLDYOUR_UVX_CMD"]
bunx_cmd = os.environ["RLDYOUR_BUNX_CMD"]
dart_cmd = os.environ["RLDYOUR_DART_CMD"]
trust_home = os.environ.get("RLDYOUR_TRUST_HOME") == "1"
owner_mode = os.environ.get("RLDYOUR_OWNER_MODE") == "1"
dry_run = os.environ.get("RLDYOUR_DRY_RUN") == "1"
mcp_config_path = Path(os.environ["RLDYOUR_MCP_CONFIG"])
system_agent_dir = Path(os.environ["RLDYOUR_SYSTEM_AGENT_DIR"])
codex_agent_dir = Path(os.environ["RLDYOUR_CODEX_AGENT_DIR"])
marketplace_config_path = Path(os.environ["RLDYOUR_MARKETPLACE_CONFIG"])
browser_contract_path = Path(repo_root) / "config" / "rldyour-contract.json"


# macOS-only plugins: cmux (manaflow-ai/cmux) is a macOS application, so the
# orchestrator plugin is never enabled or cached on Linux/WSL/Windows.
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


rldyour_plugins = load_rldyour_plugins(marketplace_config_path)
curated_plugins = ["gmail@openai-curated", "github@openai-curated"]


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
managed_model = "gpt-5.5"
managed_reasoning_effort = "xhigh"
managed_subagent_model = "gpt-5.5"
managed_subagent_reasoning_effort = "medium"
mcp_tool_approvals = {
    "sequential-thinking": {"sequentialthinking": "approve"},
    "deepwiki": {
        "ask_wiki_question": "approve",
        "read_wiki_structure": "approve",
    },
    "grep": {"searchGitHub": "approve"},
}

managed_agents = []
for agent_path in sorted(system_agent_dir.glob("*.toml")):
    agent_data = tomllib.loads(agent_path.read_text(encoding="utf-8"))
    name = agent_data.get("name")
    description = agent_data.get("description")
    if not isinstance(name, str) or not name:
        raise SystemExit(f"{agent_path}: missing name")
    if not isinstance(description, str) or not description:
        raise SystemExit(f"{agent_path}: missing description")
    if agent_data.get("model") != managed_subagent_model:
        raise SystemExit(f"{agent_path}: model must be {managed_subagent_model}")
    if agent_data.get("model_reasoning_effort") != managed_subagent_reasoning_effort:
        raise SystemExit(f"{agent_path}: model_reasoning_effort must be {managed_subagent_reasoning_effort}")
    managed_agents.append(
        {
            "name": name,
            "description": description,
            "config_file": str(codex_agent_dir / agent_path.name),
        }
    )
if not managed_agents:
    raise SystemExit(f"{system_agent_dir}: no managed subagent configs found")

mcp_source = json.loads(mcp_config_path.read_text(encoding="utf-8"))["mcpServers"]
command_overrides = {
    "uvx": uvx_cmd,
    "bunx": bunx_cmd,
    "dart": dart_cmd,
}
secret_placeholder_re = re.compile(r"^\$\{([A-Z0-9_]+)\}$")


def normalized_mcp_spec(raw_spec: dict[str, object]) -> dict[str, object]:
    spec = dict(raw_spec)
    env = spec.get("env")
    if not isinstance(env, dict):
        return spec

    static_env: dict[str, object] = {}
    raw_env_vars = spec.get("env_vars")
    env_vars = list(raw_env_vars) if isinstance(raw_env_vars, list) else []
    for key, value in env.items():
        if isinstance(key, str) and isinstance(value, str) and secret_placeholder_re.match(value):
            if key not in env_vars:
                env_vars.append(key)
            continue
        static_env[key] = value

    if static_env:
        spec["env"] = static_env
    else:
        spec.pop("env", None)
    if env_vars:
        spec["env_vars"] = env_vars
    return spec


mcp_servers = {}
for name, raw_spec in mcp_source.items():
    spec = normalized_mcp_spec(raw_spec)
    command = spec.get("command")
    if isinstance(command, str) and command in command_overrides:
        spec["command"] = command_overrides[command]
    mcp_servers[name] = spec

managed_headers = {
    "agents",
    "marketplaces.rldyour-codex",
    "profiles.rldyour-safe",
    "profiles.rldyour-yolo",
    f'projects."{repo_root}"',
}
for agent in managed_agents:
    managed_headers.add(f"agents.{agent['name']}")
if trust_home:
    managed_headers.add(f'projects."{home}"')
for plugin in curated_plugins:
    managed_headers.add(f'plugins."{plugin}"')
for plugin in disabled_codex_plugins:
    managed_headers.add(f'plugins."{plugin}"')
for plugin in rldyour_plugins:
    managed_headers.add(f'plugins."{plugin}@rldyour-codex"')
for server, spec in mcp_servers.items():
    managed_headers.add(f"mcp_servers.{server}")
    if "env" in spec:
        managed_headers.add(f"mcp_servers.{server}.env")
for server, tools in mcp_tool_approvals.items():
    for tool in tools:
        managed_headers.add(f"mcp_servers.{server}.tools.{tool}")

header_re = re.compile(r"^\s*\[([^\]]+)\]\s*$")
assignment_re = re.compile(r"^\s*((?:[A-Za-z0-9_-]+|\"[^\"]+\"|'[^']+')(?:\s*\.\s*(?:[A-Za-z0-9_-]+|\"[^\"]+\"|'[^']+'))*)\s*=(.*)$")
bare_key_re = re.compile(r"^[A-Za-z0-9_-]+$")
existing = config_path.read_text(encoding="utf-8") if config_path.exists() else ""
yolo_profile_existing = yolo_profile_path.read_text(encoding="utf-8") if yolo_profile_path.exists() else ""
if (
    "[mcp_servers." not in existing
    and "[plugins." not in existing
    and "[agents]" not in existing
    and (
        "[mcp_servers." in yolo_profile_existing
        or "[plugins." in yolo_profile_existing
        or "[agents]" in yolo_profile_existing
    )
):
    existing = yolo_profile_existing
try:
    existing_data = tomllib.loads(existing) if existing.strip() else {}
except tomllib.TOMLDecodeError as exc:
    raise SystemExit(
        f"Malformed existing Codex config: {config_path}: {exc}. "
        "Repair the file or restore an installer backup before running install_system_codex.sh."
    )
existing_features = existing_data.get("features") if isinstance(existing_data.get("features"), dict) else {}
existing_memories = existing_data.get("memories") if isinstance(existing_data.get("memories"), dict) else {}
existing_mcp_servers = existing_data.get("mcp_servers")
if existing_mcp_servers is not None and not isinstance(existing_mcp_servers, dict):
    raise SystemExit(f"{config_path}: mcp_servers must be a table")
preserved_disabled_mcp_servers: dict[str, dict[object, object]] = {}
for server in disabled_codex_mcp_servers:
    raw_spec = (existing_mcp_servers or {}).get(server)
    if raw_spec is None:
        continue
    if not isinstance(raw_spec, dict):
        raise SystemExit(
            f"{config_path}: mcp_servers.{server} must be a table so its app-managed "
            "transport metadata can be preserved safely"
        )
    spec = dict(raw_spec)
    spec["enabled"] = False
    preserved_disabled_mcp_servers[server] = spec
managed_plugin_names = set(curated_plugins) | set(disabled_codex_plugins) | {
    f"{plugin}@rldyour-codex" for plugin in rldyour_plugins
}
managed_root_keys = {
    "profile",
    "approval_policy",
    "check_for_update_on_startup",
    "suppress_unstable_features_warning",
    "sandbox_mode",
    "default_permissions",
    "model",
    "model_reasoning_effort",
}
out: list[str] = [
    SCHEMA_COMMENT,
    "",
    'approval_policy = "never"' if owner_mode else 'approval_policy = "on-request"',
    'sandbox_mode = "danger-full-access"' if owner_mode else 'sandbox_mode = "workspace-write"',
    f"model = {json.dumps(managed_model)}",
    f"model_reasoning_effort = {json.dumps(managed_reasoning_effort)}",
    "check_for_update_on_startup = false",
    "suppress_unstable_features_warning = true",
]
skip_managed = False
in_features = False
in_memories = False
in_tui = False
features_table_seen = False
tui_table_seen = False
feature_dotted_lines: list[str] = []
tui_preserved_lines: list[str] = []
preserved_inline_plugins: dict[str, dict[object, object]] = {}
hooks_written = False
multi_agent_written = False
tui_managed_written = False
memories_external_context_written = "disable_on_external_context" in existing_memories
current_header: str | None = None
managed_feature_keys = {
    "codex_hooks",
    "hooks",
    "multi_agent",
    "plugin_hooks",
    "use_legacy_landlock",
    "web_search",
    "web_search_cached",
    "web_search_request",
}
# Owner-standard TUI status line (Codex CLI 0.119.0+ [tui].status_line):
# model + reasoning, context left, five-hour/weekly rate-limit remainder,
# git branch, and working directory. Only these two keys are managed; any
# other user [tui] keys (notifications, animations, terminal_title) survive.
managed_tui_keys = {"status_line", "status_line_use_colors"}
managed_tui_lines = [
    'status_line = ["model-with-reasoning", "context-remaining", "five-hour-limit", "weekly-limit", "git-branch", "current-dir"]',
    "status_line_use_colors = true",
]
legacy_hook_feature_keys = {"codex_hooks"}
deprecated_root_keys = {
    "background_terminal_timeout",
    "experimental_instructions_file",
    "experimental_use_unified_exec_tool",
}
deprecated_feature_keys = {
    "plugin_hooks",
    "use_legacy_landlock",
    "web_search",
    "web_search_cached",
    "web_search_request",
}


def unquote_toml_key(segment: str) -> str:
    segment = segment.strip()
    if (segment.startswith('"') and segment.endswith('"')) or (segment.startswith("'") and segment.endswith("'")):
        return segment[1:-1]
    return segment


def split_toml_key(key: str) -> list[str]:
    segments: list[str] = []
    current: list[str] = []
    quote: str | None = None
    escape = False
    for char in key:
        if quote:
            current.append(char)
            if quote == '"' and char == "\\" and not escape:
                escape = True
                continue
            if char == quote and not escape:
                quote = None
            escape = False
            continue
        if char in ("'", '"'):
            quote = char
            current.append(char)
            continue
        if char == ".":
            segments.append(unquote_toml_key("".join(current)))
            current = []
            continue
        current.append(char)
    if current or key.endswith("."):
        segments.append(unquote_toml_key("".join(current)))
    return [segment.strip() for segment in segments]


def assignment_key_path(raw_line: str) -> tuple[list[str], str] | None:
    match = assignment_re.match(raw_line)
    if not match:
        return None
    return split_toml_key(match.group(1)), match.group(2).strip()


def toml_key(key: str) -> str:
    return key if bare_key_re.match(key) else json.dumps(key)


def toml_value(value: object) -> str:
    if isinstance(value, str):
        return json.dumps(value)
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, int):
        return str(value)
    if isinstance(value, list):
        return json.dumps(value)
    if isinstance(value, dict):
        return "{ " + ", ".join(f"{toml_key(str(key))} = {toml_value(item)}" for key, item in value.items()) + " }"
    raise TypeError(f"Unsupported TOML value: {value!r}")


if "model_instructions_file" not in existing_data and isinstance(existing_data.get("experimental_instructions_file"), str):
    out.append(f"model_instructions_file = {toml_value(existing_data['experimental_instructions_file'])}")
if "background_terminal_max_timeout" not in existing_data and isinstance(existing_data.get("background_terminal_timeout"), int):
    out.append(f"background_terminal_max_timeout = {toml_value(existing_data['background_terminal_timeout'])}")
if "web_search" not in existing_data:
    legacy_web_search = None
    if existing_features.get("web_search_request") is True:
        legacy_web_search = "live"
    elif existing_features.get("web_search_cached") is True:
        legacy_web_search = "cached"
    elif existing_features.get("web_search") is True:
        legacy_web_search = "live"
    elif existing_features.get("web_search") is False:
        legacy_web_search = "disabled"
    if legacy_web_search:
        out.append(f"web_search = {toml_value(legacy_web_search)}")
if "unified_exec" not in existing_features and isinstance(existing_data.get("experimental_use_unified_exec_tool"), bool):
    feature_dotted_lines.append(f"unified_exec = {toml_value(existing_data['experimental_use_unified_exec_tool'])}")

out.append("")


def add_blank() -> None:
    if out and out[-1] != "":
        out.append("")


def append_managed_features() -> None:
    global hooks_written, multi_agent_written
    if not hooks_written:
        out.append("hooks = true")
        hooks_written = True
    if not multi_agent_written:
        out.append("multi_agent = true")
        multi_agent_written = True


def append_features_block() -> None:
    add_blank()
    out.append("[features]")
    out.extend(feature_dotted_lines)
    append_managed_features()


def append_managed_tui() -> None:
    global tui_managed_written
    if not tui_managed_written:
        out.extend(managed_tui_lines)
        tui_managed_written = True


def append_tui_block() -> None:
    add_blank()
    out.append("[tui]")
    out.extend(tui_preserved_lines)
    append_managed_tui()


def is_rldyour_plugin_header(header_path: list[str]) -> bool:
    return (
        len(header_path) == 2
        and header_path[0] == "plugins"
        and header_path[1].startswith("rldyour-")
        and header_path[1].endswith("@rldyour-codex")
    )


def is_managed_header(header: str, header_path: list[str]) -> bool:
    if header in managed_headers:
        return True
    if len(header_path) >= 2 and header_path[0] == "mcp_servers":
        return True
    if len(header_path) >= 2 and header_path[0] == "plugins" and header_path[1] in managed_plugin_names:
        return True
    return (
        len(header_path) >= 2
        and header_path[0] == "profiles"
        and header_path[1] in {"rldyour-safe", "rldyour-yolo"}
    )


def append_preserved_toml_table(header_path: list[str], table: dict[object, object]) -> None:
    scalar_items: list[tuple[str, object]] = []
    nested_items: list[tuple[str, dict[object, object]]] = []
    for key, value in table.items():
        key_text = str(key)
        if isinstance(value, dict):
            nested_items.append((key_text, value))
        else:
            scalar_items.append((key_text, value))

    add_blank()
    out.append("[" + ".".join(toml_key(str(segment)) for segment in header_path) + "]")
    for key, value in scalar_items:
        out.append(f"{toml_key(key)} = {toml_value(value)}")
    for key, value in nested_items:
        append_preserved_toml_table([*header_path, key], value)


def should_drop_mcp_server_name(server_name: str) -> bool:
    return True


def should_drop_plugin_name(plugin_name: str) -> bool:
    return plugin_name in managed_plugin_names


for raw_line in existing.splitlines():
    if raw_line.strip() == SCHEMA_COMMENT:
        continue

    match = header_re.match(raw_line)
    if match:
        if in_features:
            append_managed_features()
        if in_tui:
            append_managed_tui()
        header = match.group(1)
        header_path = split_toml_key(header)
        if is_managed_header(header, header_path) or is_rldyour_plugin_header(header_path):
            skip_managed = True
            in_features = False
            in_memories = False
            in_tui = False
            continue
        skip_managed = False
        in_features = header_path == ["features"]
        in_memories = header_path == ["memories"]
        in_tui = header_path == ["tui"]
        if in_features:
            features_table_seen = True
        if in_tui:
            tui_table_seen = True
        current_header = header
        out.append(raw_line)
        continue

    if skip_managed:
        continue

    if current_header is None:
        key_info = assignment_key_path(raw_line)
        key_path = key_info[0] if key_info else []
        if len(key_path) == 1 and key_path[0] in managed_root_keys:
            continue
        if len(key_path) == 1 and key_path[0] in deprecated_root_keys:
            continue
        if len(key_path) >= 2 and key_path[0] == "mcp_servers" and should_drop_mcp_server_name(key_path[1]):
            continue
        if len(key_path) >= 2 and key_path[0] == "plugins" and should_drop_plugin_name(key_path[1]):
            continue
        if len(key_path) == 1 and key_path[0] == "plugins":
            try:
                inline_plugins = tomllib.loads(raw_line).get("plugins") or {}
            except Exception as exc:
                raise SystemExit(
                    "Could not safely migrate inline plugins assignment in "
                    f"{config_path}: {exc}. Rewrite it as [plugins.\"<name>\"] tables "
                    "or restore an installer backup before running install_system_codex.sh."
                )
            if not isinstance(inline_plugins, dict):
                raise SystemExit(f"{config_path}: plugins inline assignment must be a table")
            for plugin, spec in inline_plugins.items():
                plugin_name = str(plugin)
                if should_drop_plugin_name(plugin_name):
                    continue
                if not isinstance(spec, dict):
                    raise SystemExit(
                        f"{config_path}: plugins.{plugin_name} must be a table so it can be preserved safely"
                    )
                preserved_inline_plugins[plugin_name] = spec
            continue
        if len(key_path) == 1 and key_path[0] == "mcp_servers":
            try:
                inline_mcp_servers = tomllib.loads(raw_line).get("mcp_servers") or {}
            except Exception as exc:
                raise SystemExit(
                    "Could not safely migrate inline mcp_servers assignment in "
                    f"{config_path}: {exc}. Rewrite it as [mcp_servers.<name>] tables "
                    "or restore an installer backup before running install_system_codex.sh."
                )
            if not isinstance(inline_mcp_servers, dict):
                raise SystemExit(
                    f"{config_path}: mcp_servers inline assignment must be a table "
                    "so managed servers can be migrated safely."
                )
            for server, spec in inline_mcp_servers.items():
                server_name = str(server)
                if should_drop_mcp_server_name(server_name):
                    continue
                if not isinstance(spec, dict):
                    raise SystemExit(
                        f"{config_path}: mcp_servers.{server_name} must be a table "
                        "so it can be preserved while managed servers are regenerated."
                    )
                append_preserved_toml_table(["mcp_servers", server_name], spec)
            continue
        if len(key_path) == 1 and key_path[0] == "features":
            try:
                inline_features = tomllib.loads(raw_line).get("features") or {}
            except Exception:
                inline_features = {}
            if not isinstance(inline_features, dict):
                continue
            for feature_key, feature_value in inline_features.items():
                if feature_key in managed_feature_keys:
                    continue
                feature_dotted_lines.append(f"{toml_key(str(feature_key))} = {toml_value(feature_value)}")
            continue
        if len(key_path) == 2 and key_path[0] == "features":
            feature_key = key_path[1]
            if feature_key in managed_feature_keys:
                continue
            feature_dotted_lines.append(f"{toml_key(feature_key)} = {key_info[1]}")
            continue
        if len(key_path) == 1 and key_path[0] == "tui":
            try:
                inline_tui = tomllib.loads(raw_line).get("tui") or {}
            except Exception:
                inline_tui = {}
            if not isinstance(inline_tui, dict):
                continue
            for tui_key, tui_value in inline_tui.items():
                if tui_key in managed_tui_keys:
                    continue
                tui_preserved_lines.append(f"{toml_key(str(tui_key))} = {toml_value(tui_value)}")
            continue
        if len(key_path) >= 2 and key_path[0] == "tui":
            if key_path[1] in managed_tui_keys:
                continue
            tui_subkey = ".".join(toml_key(segment) for segment in key_path[1:])
            tui_preserved_lines.append(f"{tui_subkey} = {key_info[1]}")
            continue
        if (
            len(key_path) == 2
            and key_path[0] == "memories"
            and key_path[1] == "no_memories_if_mcp_or_web_search"
        ):
            if not memories_external_context_written:
                out.append(f"memories.disable_on_external_context = {key_info[1]}")
                memories_external_context_written = True
            continue

    if current_header and split_toml_key(current_header) == ["mcp_servers"]:
        key_info = assignment_key_path(raw_line)
        key_path = key_info[0] if key_info else []
        if key_path and should_drop_mcp_server_name(key_path[0]):
            continue

    if current_header and split_toml_key(current_header) == ["plugins"]:
        key_info = assignment_key_path(raw_line)
        key_path = key_info[0] if key_info else []
        if key_path and should_drop_plugin_name(key_path[0]):
            continue

    if in_features:
        key_info = assignment_key_path(raw_line)
        key_path = key_info[0] if key_info else []
        feature_key = key_path[0] if len(key_path) == 1 else ""
        if feature_key in legacy_hook_feature_keys:
            continue
        if feature_key in deprecated_feature_keys:
            continue
        if feature_key == "hooks":
            if not hooks_written:
                out.append("hooks = true")
                hooks_written = True
            continue
        if feature_key == "plugin_hooks":
            continue
        if feature_key == "multi_agent":
            if not multi_agent_written:
                out.append("multi_agent = true")
                multi_agent_written = True
            continue

    if in_tui:
        key_info = assignment_key_path(raw_line)
        key_path = key_info[0] if key_info else []
        if key_path and key_path[0] in managed_tui_keys:
            continue

    if in_memories:
        key_info = assignment_key_path(raw_line)
        key_path = key_info[0] if key_info else []
        memory_key = key_path[0] if len(key_path) == 1 else ""
        if memory_key == "no_memories_if_mcp_or_web_search":
            if not memories_external_context_written:
                out.append(f"disable_on_external_context = {key_info[1]}")
                memories_external_context_written = True
            continue
        if memory_key == "disable_on_external_context":
            memories_external_context_written = True

    out.append(raw_line)

if in_features:
    append_managed_features()
if in_tui:
    append_managed_tui()

while out and out[-1] == "":
    out.pop()

if not features_table_seen:
    append_features_block()

if not tui_table_seen:
    append_tui_block()

add_blank()
out.extend([
    "[marketplaces.rldyour-codex]",
    'source_type = "local"',
    f"source = {json.dumps(repo_root)}",
])

add_blank()
out.extend([
    "[agents]",
    "max_threads = 6",
    "max_depth = 1",
])
for agent in managed_agents:
    add_blank()
    out.extend([
        f"[agents.{agent['name']}]",
        f"description = {toml_value(agent['description'])}",
        f"config_file = {toml_value(agent['config_file'])}",
    ])

add_blank()
out.extend([f'[projects."{repo_root}"]', 'trust_level = "trusted"'])
if trust_home:
    add_blank()
    out.extend([f'[projects."{home}"]', 'trust_level = "trusted"'])

for plugin, spec in preserved_inline_plugins.items():
    append_preserved_toml_table(["plugins", plugin], spec)

for plugin in curated_plugins:
    add_blank()
    out.extend([f'[plugins."{plugin}"]', "enabled = true"])

for plugin in disabled_codex_plugins:
    add_blank()
    out.extend([f'[plugins."{plugin}"]', "enabled = false"])

for plugin in rldyour_plugins:
    add_blank()
    out.extend([f'[plugins."{plugin}@rldyour-codex"]', "enabled = true"])

for server, spec in mcp_servers.items():
    add_blank()
    out.append(f"[mcp_servers.{server}]")
    for key in ("command", "url", "args", "env_vars", "startup_timeout_sec", "tool_timeout_sec"):
        if key in spec:
            out.append(f"{key} = {toml_value(spec[key])}")
    env = spec.get("env")
    if isinstance(env, dict):
        add_blank()
        out.append(f"[mcp_servers.{server}.env]")
        for key, value in env.items():
            out.append(f"{key} = {toml_value(value)}")

for server, spec in preserved_disabled_mcp_servers.items():
    append_preserved_toml_table(["mcp_servers", server], spec)

for server, tools in mcp_tool_approvals.items():
    for tool, approval_mode in tools.items():
        add_blank()
        out.append(f"[mcp_servers.{server}.tools.{tool}]")
        out.append(f"approval_mode = {toml_value(approval_mode)}")

compact_out: list[str] = []
for line in out:
    if line == "" and compact_out and compact_out[-1] == "":
        continue
    compact_out.append(line)
out = compact_out
new_text = "\n".join(out).rstrip() + "\n"

def profile_config_text(*, yolo: bool) -> str:
    lines = [
        SCHEMA_COMMENT,
        "",
        'approval_policy = "never"' if yolo else 'approval_policy = "on-request"',
        'sandbox_mode = "danger-full-access"' if yolo else 'sandbox_mode = "workspace-write"',
    ]
    lines.extend([
        f"model = {json.dumps(managed_model)}",
        f"model_reasoning_effort = {json.dumps(managed_reasoning_effort)}",
        "check_for_update_on_startup = false",
        "suppress_unstable_features_warning = true",
        "",
        "[tui]",
        *managed_tui_lines,
        "",
    ])
    return "\n".join(lines)

yolo_profile_text = profile_config_text(yolo=True)
safe_profile_text = profile_config_text(yolo=False)

if dry_run:
    print(f"dry-run: would patch {config_path}")
    print(f"dry-run: would patch {yolo_profile_path}")
    print(f"dry-run: would patch {safe_profile_path}")
    print(
        "dry-run: managed plugins: "
        f"{len(rldyour_plugins) + len(curated_plugins) + len(disabled_codex_plugins)}"
    )
    print(f"dry-run: managed subagents: {len(managed_agents)}")
    print(f"dry-run: managed MCP servers: {len(mcp_servers)}")
else:
    config_path.parent.mkdir(parents=True, exist_ok=True)
    config_path.write_text(new_text, encoding="utf-8")
    yolo_profile_path.write_text(yolo_profile_text, encoding="utf-8")
    safe_profile_path.write_text(safe_profile_text, encoding="utf-8")
    print(f"patched {config_path}")
    print(f"patched {yolo_profile_path}")
    print(f"patched {safe_profile_path}")
PY
}

sync_plugin_cache() {
  local plugin_name plugin_version plugin_dir cache_dir
  while IFS=$'\t' read -r plugin_name plugin_version plugin_dir cache_dir; do
    if [ "$plugin_name" = "rldyour-orchestrator" ] && [ "$(uname -s)" != "Darwin" ]; then
      printf 'skip macOS-only plugin cache on this OS: %s\n' "$plugin_name"
      continue
    fi
    if [ "$APPLY" -eq 1 ]; then
      mkdir -p "$cache_dir"
      rsync -a --delete "$plugin_dir/" "$cache_dir/"
      printf 'synced plugin cache %s@%s -> %s\n' "$plugin_name" "$plugin_version" "$cache_dir"
    else
      printf 'dry-run: sync %s -> %s\n' "$plugin_dir/" "$cache_dir/"
    fi
  done < <(python3 "$ROOT/scripts/plugin_cache_contract.py" --cache-root "$CACHE_ROOT" --include-local list --format tsv)
}

trust_plugin_hooks() {
  if [ "$APPLY" -ne 1 ]; then
    printf 'dry-run: refresh trusted hashes for installed rldyour plugin hooks\n'
    return 0
  fi
  if [ -z "$CODEX_CMD" ]; then
    printf 'warning: codex command not found; hook trust refresh skipped\n' >&2
    return 0
  fi

  export RLDYOUR_CODEX_CMD="$CODEX_CMD"
  export RLDYOUR_CODEX_HOME="$CODEX_HOME_DIR"
  export RLDYOUR_REPO_ROOT="$ROOT"
  python3 <<'PY'
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
repo_root = os.environ["RLDYOUR_REPO_ROOT"]


def timeout_seconds() -> float:
    raw = os.environ.get("CODEX_APP_SERVER_TIMEOUT_SECONDS", "10")
    try:
        return max(0.1, float(raw))
    except ValueError:
        return 10.0


app_server_timeout = timeout_seconds()

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


try:
    send(
        {
            "id": 1,
            "method": "initialize",
            "params": {
                "clientInfo": {
                    "name": "rldyour_codex_installer",
                    "title": "rldyour Codex installer",
                    "version": "0.0.0",
                },
                "capabilities": {"experimentalApi": True},
            },
        }
    )
    checked_response(1)

    send({"id": 2, "method": "hooks/list", "params": {"cwds": [repo_root]}})
    response = checked_response(2)
    data = response.get("result", {}).get("data", [])  # type: ignore[union-attr]
    hooks = data[0].get("hooks", []) if data else []
    state: dict[str, dict[str, object]] = {}
    for hook in hooks:
        if not isinstance(hook, dict):
            continue
        plugin_id = hook.get("pluginId")
        key = hook.get("key")
        current_hash = hook.get("currentHash")
        if not (
            isinstance(plugin_id, str)
            and plugin_id.startswith("rldyour-")
            and plugin_id.endswith("@rldyour-codex")
            and isinstance(key, str)
            and isinstance(current_hash, str)
        ):
            continue
        state[key] = {
            "trusted_hash": current_hash,
            "enabled": bool(hook.get("enabled", True)),
        }

    if not state:
        print("warning: codex hooks/list returned no rldyour plugin hooks; hook trust refresh skipped")
        raise SystemExit(0)

    send(
        {
            "id": 3,
            "method": "config/batchWrite",
            "params": {
                "edits": [
                    {
                        "keyPath": "hooks.state",
                        "value": state,
                        "mergeStrategy": "upsert",
                    }
                ],
                "reloadUserConfig": True,
            },
        }
    )
    checked_response(3)
    print(f"trusted rldyour plugin hooks: {len(state)}")
finally:
    proc.terminate()
    try:
        proc.wait(timeout=3)
    except subprocess.TimeoutExpired:
        proc.kill()
PY
}

sync_agent_configs() {
  local agent_file agent_name target
  for agent_file in "$SYSTEM_AGENT_DIR"/*.toml; do
    [ -f "$agent_file" ] || continue
    agent_name=$(basename "$agent_file")
    target="$CODEX_AGENT_DIR/$agent_name"
    if [ "$APPLY" -eq 1 ]; then
      mkdir -p "$CODEX_AGENT_DIR"
      install -m 0644 "$agent_file" "$target"
      printf 'installed subagent config %s\n' "$target"
    else
      printf 'dry-run: install %s -> %s\n' "$agent_file" "$target"
    fi
  done
}

sync_execpolicy_rules() {
  local rule_file rule_name target
  for rule_file in "$SYSTEM_RULE_DIR"/*.rules; do
    [ -f "$rule_file" ] || continue
    rule_name=$(basename "$rule_file")
    target="$CODEX_RULE_DIR/$rule_name"
    if [ "$APPLY" -eq 1 ]; then
      mkdir -p "$CODEX_RULE_DIR"
      install -m 0644 "$rule_file" "$target"
      printf 'installed execpolicy rule %s\n' "$target"
    else
      printf 'dry-run: install %s -> %s\n' "$rule_file" "$target"
    fi
  done
}

print_plan
validate_runtime_prereqs

if [ "$APPLY" -eq 1 ]; then
  mkdir -p "$CODEX_HOME_DIR"
fi

backup_file "$CODEX_HOME_DIR/AGENTS.md"
backup_file "$CONFIG_PATH"
backup_file "$YOLO_PROFILE_PATH"
backup_file "$SAFE_PROFILE_PATH"
for agent_file in "$SYSTEM_AGENT_DIR"/*.toml; do
  [ -f "$agent_file" ] || continue
  backup_agent_file "$CODEX_AGENT_DIR/$(basename "$agent_file")"
done
for rule_file in "$SYSTEM_RULE_DIR"/*.rules; do
  [ -f "$rule_file" ] || continue
  backup_rule_file "$CODEX_RULE_DIR/$(basename "$rule_file")"
done

validate_existing_config

if [ "$APPLY" -eq 1 ]; then
  install -m 0644 "$SYSTEM_AGENTS" "$CODEX_HOME_DIR/AGENTS.md"
  printf 'installed %s\n' "$CODEX_HOME_DIR/AGENTS.md"
else
  printf 'dry-run: install %s -> %s\n' "$SYSTEM_AGENTS" "$CODEX_HOME_DIR/AGENTS.md"
fi

if [ -n "$CODEX_CMD" ]; then
  run_or_print env CODEX_HOME="$CODEX_HOME_DIR" "$CODEX_CMD" plugin marketplace add "$ROOT"
else
  printf 'warning: codex command not found; marketplace add skipped\n' >&2
fi

patch_config
sync_agent_configs
sync_execpolicy_rules
sync_plugin_cache
trust_plugin_hooks

cat <<EOF

Next checks:
  scripts/doctor_system_codex.sh --codex-home "$CODEX_HOME_DIR"

Restart Codex after install so global AGENTS.md, subagent configs, plugins, hooks, and MCP settings are reloaded.
EOF
