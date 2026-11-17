#!/usr/bin/env python3
from __future__ import annotations

import json
import re
import sys
import tomllib
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[1]
CONTRACT_PATH = ROOT / "config/rldyour-contract.json"
EXPECTED_AUTHOR = "Danil Silantyev (github:rldyourmnd), CEO NDDev"


def source_command_directories(root: Path) -> list[Path]:
    """Find authored command surfaces without counting the ignored tool environment."""
    return [
        path.relative_to(root)
        for path in sorted(root.glob("**/commands"))
        if path.is_dir() and ".git" not in path.parts
        and path.relative_to(root).parts[0] != ".venv"
    ]


def load_json(path: Path) -> Any:
    return json.loads(path.read_text(encoding="utf-8"))


def skill_name(path: Path) -> str | None:
    text = path.read_text(encoding="utf-8")
    match = re.match(r"^---\n(.*?)\n---\n", text, re.S)
    if not match:
        return None
    name = re.search(r"^name:\s*(.+)$", match.group(1), re.M)
    if not name:
        return None
    return name.group(1).strip().strip("\"'")


def iter_hook_handlers(hooks_json: dict[str, Any]) -> list[tuple[str, dict[str, Any]]]:
    handlers: list[tuple[str, dict[str, Any]]] = []
    events = hooks_json.get("hooks")
    if not isinstance(events, dict):
        return handlers
    for event, groups in events.items():
        if not isinstance(groups, list):
            continue
        for group in groups:
            if not isinstance(group, dict):
                continue
            group_handlers = group.get("hooks")
            if not isinstance(group_handlers, list):
                continue
            for handler in group_handlers:
                if isinstance(handler, dict):
                    handlers.append((event, handler))
    return handlers


def hook_manifest(plugin: str) -> dict[str, Any]:
    path = ROOT / "plugins" / plugin / "hooks.json"
    if not path.is_file():
        return {}
    data = load_json(path)
    return data if isinstance(data, dict) else {}


def command_for_event(plugin: str, event: str, needle: str) -> bool:
    for handler_event, handler in iter_hook_handlers(hook_manifest(plugin)):
        if handler_event != event:
            continue
        command = handler.get("command")
        if isinstance(command, str) and needle in command:
            return True
    return False


def main() -> int:
    errors: list[str] = []
    contract = load_json(CONTRACT_PATH)
    if not isinstance(contract, dict):
        print(f"{CONTRACT_PATH.relative_to(ROOT)}: expected JSON object", file=sys.stderr)
        return 1

    if contract.get("adapter") != "codex":
        errors.append("config/rldyour-contract.json: adapter must be codex")
    if contract.get("schema_version") != 1:
        errors.append("config/rldyour-contract.json: schema_version must be 1")

    marketplace = load_json(ROOT / ".agents/plugins/marketplace.json")
    marketplace_plugins_raw = marketplace.get("plugins") if isinstance(marketplace, dict) else []
    marketplace_plugins = marketplace_plugins_raw if isinstance(marketplace_plugins_raw, list) else []
    actual_plugins: list[str] = []
    for entry in marketplace_plugins:
        if not isinstance(entry, dict):
            continue
        name = entry.get("name")
        if isinstance(name, str):
            actual_plugins.append(name)
    actual_plugins.sort()
    expected_plugins_raw = contract.get("plugins")
    expected_plugins = sorted(item for item in expected_plugins_raw if isinstance(item, str)) if isinstance(expected_plugins_raw, list) else []
    if actual_plugins != expected_plugins:
        errors.append(f"plugins: expected {expected_plugins}, got {actual_plugins}")

    expected_license = contract.get("license")
    expected_repo = contract.get("public_repository")
    for plugin in actual_plugins:
        manifest = load_json(ROOT / "plugins" / plugin / ".codex-plugin/plugin.json")
        if not isinstance(manifest, dict):
            errors.append(f"{plugin}: manifest must be an object")
            continue
        if manifest.get("license") != expected_license:
            errors.append(f"{plugin}: manifest license must be {expected_license}")
        author = manifest.get("author")
        if not isinstance(author, dict) or author.get("name") != EXPECTED_AUTHOR:
            errors.append(f"{plugin}: manifest author.name must be {EXPECTED_AUTHOR}")
        for key in ("homepage", "repository"):
            if manifest.get(key) != expected_repo:
                errors.append(f"{plugin}: manifest {key} must be {expected_repo}")

    actual_skills = sorted(
        name
        for name in (skill_name(path) for path in sorted((ROOT / "plugins").glob("rldyour-*/skills/*/SKILL.md")))
        if name
    )
    skills_contract = contract.get("skills")
    if not isinstance(skills_contract, dict):
        errors.append("skills: expected object")
        expected_skills: list[str] = []
    else:
        expected_skills = sorted(skills_contract.get("names") or [])
        if skills_contract.get("count") != len(actual_skills):
            errors.append(f"skills.count: expected {len(actual_skills)}, got {skills_contract.get('count')!r}")
    if actual_skills != expected_skills:
        errors.append("skills.names: contract does not match discovered SKILL.md names")

    slash_contract = contract.get("slash_commands")
    if isinstance(slash_contract, dict) and slash_contract.get("count") == 0:
        command_dirs = source_command_directories(ROOT)
        if command_dirs:
            errors.append(f"slash_commands: expected none, found {command_dirs}")
    else:
        errors.append("slash_commands.count must be 0 for Codex adapter")

    actual_agents: set[str] = set()
    for path in sorted((ROOT / "system/agents").glob("*.toml")):
        data = tomllib.loads(path.read_text(encoding="utf-8"))
        name = data.get("name")
        actual_agents.add(name if isinstance(name, str) else path.stem)
    agents = contract.get("agents")
    role_values = []
    if isinstance(agents, dict) and isinstance(agents.get("roles"), dict):
        role_values = list(agents["roles"].values())
    else:
        errors.append("agents.roles: expected object")
    missing_agents = sorted(set(role_values) - actual_agents)
    extra_agents = sorted(actual_agents - set(role_values))
    if missing_agents:
        errors.append(f"agents.roles: missing managed agents {missing_agents}")
    if extra_agents:
        errors.append(f"agents.roles: unmanaged agents not in contract {extra_agents}")

    hooks = contract.get("hooks")
    if not isinstance(hooks, dict):
        errors.append("hooks: expected object")
    else:
        if hooks.get("removed_plugin_hooks_feature_required") is not False:
            errors.append("hooks.removed_plugin_hooks_feature_required must be false for current Codex")
        for key in (
            "hooks_feature_default_enabled",
            "plugin_bundled_hooks_discoverable",
            "plugin_hook_trust_required",
            "trusted_hook_hashes_refreshed_by_installer",
        ):
            if hooks.get(key) is not True:
                errors.append(f"hooks.{key} must be true for current Codex")
        for script in ("scripts/install_system_codex.sh", "scripts/doctor_system_codex.sh"):
            script_text = (ROOT / script).read_text(encoding="utf-8")
            if 'plugin_hooks = true' in script_text or 'features.get("plugin_hooks") is True' in script_text:
                errors.append(f"{script}: must not write or require removed features.plugin_hooks")
        expected_handler_type = hooks.get("handler_type")
        for plugin in ("rldyour-flow", "rldyour-serena-mcp"):
            for event, handler in iter_hook_handlers(hook_manifest(plugin)):
                if handler.get("type") != expected_handler_type:
                    errors.append(f"{plugin} {event}: hook handler type must be {expected_handler_type}")
                command = handler.get("command")
                if not isinstance(command, str) or "PLUGIN_ROOT" not in command:
                    errors.append(f"{plugin} {event}: command must resolve via PLUGIN_ROOT")
        lifecycles = hooks.get("lifecycles")
        if not isinstance(lifecycles, dict):
            errors.append("hooks.lifecycles: expected object")
        else:
            for lifecycle_id, mapping in lifecycles.items():
                if not isinstance(mapping, dict):
                    errors.append(f"hooks.lifecycles.{lifecycle_id}: expected object")
                    continue
                dispatched_by = mapping.get("dispatched_by")
                if dispatched_by:
                    dispatcher = lifecycles.get(dispatched_by)
                    if not isinstance(dispatcher, dict):
                        errors.append(f"hooks.lifecycles.{lifecycle_id}: unknown dispatcher {dispatched_by!r}")
                    continue
                plugin_raw = mapping.get("plugin")
                event_raw = mapping.get("event")
                needle_raw = mapping.get("command_contains")
                if not isinstance(plugin_raw, str) or not isinstance(event_raw, str) or not isinstance(needle_raw, str):
                    errors.append(f"hooks.lifecycles.{lifecycle_id}: plugin/event/command_contains must be strings")
                    continue
                plugin = plugin_raw
                event = event_raw
                needle = needle_raw
                if not command_for_event(plugin, event, needle):
                    errors.append(f"hooks.lifecycles.{lifecycle_id}: {plugin} {event} missing command {needle}")

    mcp_contract = contract.get("mcp")
    expected_servers_raw = mcp_contract.get("servers") if isinstance(mcp_contract, dict) else []
    expected_servers = sorted(item for item in expected_servers_raw if isinstance(item, str)) if isinstance(expected_servers_raw, list) else []
    mcp_data = load_json(ROOT / "plugins/rldyour-mcps/.mcp.json")
    actual_servers = sorted((mcp_data.get("mcpServers") or {}).keys()) if isinstance(mcp_data, dict) else []
    if actual_servers != expected_servers:
        errors.append(f"mcp.servers: expected {expected_servers}, got {actual_servers}")

    security = contract.get("security")
    if isinstance(security, dict):
        if security.get("default_profile") != "rldyour-yolo":
            errors.append("security.default_profile must be rldyour-yolo")
        if security.get("permission_model") != "legacy_sandbox":
            errors.append("security.permission_model must be legacy_sandbox")
        if security.get("permission_profiles_active") is not False:
            errors.append("security.permission_profiles_active must be false")
        if security.get("default_sandbox_mode") != "danger-full-access":
            errors.append("security.default_sandbox_mode must be danger-full-access")
        if security.get("default_approval_policy") != "never":
            errors.append("security.default_approval_policy must be never")
        if security.get("check_for_update_on_startup") is not False:
            errors.append("security.check_for_update_on_startup must be false for the managed runtime")
        if "default_permissions" in security:
            errors.append("security.default_permissions must be absent while legacy_sandbox is active")
        if security.get("full_auto_standard") is not True:
            errors.append("security.full_auto_standard must be true")
        if security.get("safe_profile") != "rldyour-safe":
            errors.append("security.safe_profile must be rldyour-safe")
        if security.get("safe_profile_flag") != "--safe-mode":
            errors.append("security.safe_profile_flag must be --safe-mode")
        install_text = (ROOT / "scripts/install_system_codex.sh").read_text(encoding="utf-8")
        doctor_text = (ROOT / "scripts/doctor_system_codex.sh").read_text(encoding="utf-8")
        if 'OWNER_MODE=1' not in install_text or "rldyour-yolo.config.toml" not in install_text:
            errors.append("scripts/install_system_codex.sh must default to the rldyour-yolo profile file")
        if '[profiles.rldyour-yolo]' in install_text or 'profile = "rldyour-yolo"' in install_text:
            errors.append("scripts/install_system_codex.sh must not write legacy profile selectors or tables")
        if "--safe-mode" not in install_text:
            errors.append("scripts/install_system_codex.sh must keep --safe-mode as an explicit override")
        if 'OWNER_MODE=1' not in doctor_text or "profile file rldyour-yolo exists" not in doctor_text:
            errors.append("scripts/doctor_system_codex.sh must validate full-auto mode by default")
        if "owner mode yolo profile selected" in doctor_text:
            errors.append("scripts/doctor_system_codex.sh must not validate the legacy profile selector")

        baseline = load_json(ROOT / "references/codex-baseline.json")
        owner_runtime_policy = ((baseline.get("baseline") or {}).get("owner_runtime_policy") or {})
        if owner_runtime_policy.get("check_for_update_on_startup") is not False:
            errors.append("references/codex-baseline.json must disable the managed startup update check")

    if errors:
        print("\n".join(errors), file=sys.stderr)
        return 1

    print(
        "validated Codex contract: "
        f"{len(actual_plugins)} plugins, {len(actual_skills)} skills, {len(actual_agents)} agents, "
        f"{len(actual_servers)} MCP servers"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
