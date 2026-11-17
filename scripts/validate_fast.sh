#!/usr/bin/env bash
set -euo pipefail

ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
cd "$ROOT"

UV_BIN=${UV_BIN:-$(command -v uv 2>/dev/null || true)}
if [ -z "$UV_BIN" ]; then
  printf 'uv command not found\n' >&2
  exit 1
fi

step() {
  printf '\n== %s ==\n' "$1"
}

step "JSON metadata"
jq empty .agents/plugins/marketplace.json config/skill-routing-policy.json plugins/*/.codex-plugin/plugin.json plugins/rldyour-mcps/.mcp.json plugins/rldyour-serena-mcp/hooks.json plugins/rldyour-flow/hooks.json pyrightconfig.json

step "Release metadata"
python3 scripts/validate_plugin_versions.py
python3 scripts/validate_contract.py
python3 scripts/release_manifest.py >/dev/null
python3 scripts/release_sbom.py >/dev/null

step "Routing and agent surfaces"
python3 scripts/validate_skill_routing.py
python3 scripts/validate_browser_provider_policy.py --strict
if [ -f AGENTS.md ] || [ -f .claude/CLAUDE.md ]; then
  python3 scripts/validate_instruction_docs.py --require-agent-docs
else
  python3 scripts/validate_instruction_docs.py
fi
"$UV_BIN" run --offline --locked --no-sync --group ci python scripts/validate_agent_tools.py
python3 scripts/validate_codex_mcp_env_forwarding.py

step "Supply-chain and text security"
python3 scripts/validate_action_pins.py
python3 scripts/scan_text_security.py

step "Python syntax"
python3 -m compileall -q scripts plugins tests

step "Pytest entrypoints"
"$UV_BIN" run --offline --locked --no-sync --group ci pytest --collect-only --no-cov -q >/dev/null
"$UV_BIN" run --offline --locked --no-sync --group ci python -m pytest

printf '\nFast validation passed.\n'
