set shell := ["bash", "-euo", "pipefail", "-c"]

# Lists source, CI and declared-output maintenance commands.
default:
    @just --list

# Prepares the locked source-validation group without building the package.
setup:
    uv sync --locked --group ci --no-install-project --no-build

# Checks source, types, metadata, workflows and the original secret scope offline.
check base="" head="":
    just --fmt --check
    uv run --offline --locked --no-sync --group ci python scripts/check_ci_environment.py
    python scripts/check_ci_sources.py
    uv run --offline --locked --no-sync --group ci python scripts/validate_plugin_versions.py
    uv run --offline --locked --no-sync --group ci python scripts/validate_contract.py
    uv run --offline --locked --no-sync --group ci python scripts/validate_skill_routing.py
    uv run --offline --locked --no-sync --group ci python scripts/validate_browser_provider_policy.py --strict
    uv run --offline --locked --no-sync --group ci python scripts/validate_instruction_docs.py --require-agent-docs
    uv run --offline --locked --no-sync --group ci python scripts/validate_agent_tools.py
    uv run --offline --locked --no-sync --group ci python scripts/validate_codex_mcp_env_forwarding.py
    uv run --offline --locked --no-sync --group ci python scripts/validate_action_pins.py
    uv run --offline --locked --no-sync --group ci python scripts/scan_text_security.py
    shellcheck plugins/rldyour-serena-mcp/hooks/*.sh plugins/rldyour-serena-mcp/scripts/*.sh plugins/rldyour-flow/hooks/*.sh plugins/rldyour-flow/scripts/*.sh plugins/rldyour-lsps/scripts/*.sh scripts/*.sh
    node --version
    env -u PYRIGHT_PYTHON_FORCE_VERSION PYRIGHT_PYTHON_IGNORE_WARNINGS=1 PYRIGHT_PYTHON_USE_BUNDLED_PYRIGHT=1 PYRIGHT_PYTHON_GLOBAL_NODE=1 uv run --offline --locked --no-sync --group ci pyright --project pyrightconfig.json
    actionlint
    uv run --offline --locked --no-sync --group ci zizmor --offline --no-progress .github
    bash scripts/check_ci_secrets.sh {{ quote(base) }} {{ quote(head) }}

# Formats the command declarations.
fix:
    just --fmt

# Retains the full existing fast/unit/coverage and stderr-classification suite on CI.
test:
    python scripts/require_source_profile.py
    mkdir -p ci-reports
    uv run --offline --locked --no-sync --group ci bash scripts/validate_fast.sh 2>ci-reports/pytest.stderr.log
    uv run --offline --locked --no-sync --group ci python scripts/classify_ci_noise.py --strict ci-reports/pytest.stderr.log

# Verifies source and the isolated source-unit profile; runtime operators are separate.
verify: check test ci-release

# Exercises the existing static materialization mode without an installed runtime.
[group("ci")]
ci-materialize:
    python scripts/require_source_profile.py
    uv run --offline --locked --no-sync --group ci bash scripts/validate_runtime.sh --mode static

# Retains release metadata and SBOM generation without publishing anything.
[group("ci")]
ci-release:
    uv run --offline --locked --no-sync --group ci bash scripts/validate_release.sh

# Retains the metadata and Python compile smoke on each actual supported OS.
[group("ci")]
ci-platform:
    python scripts/check_ci_platform.py

# Retains advisory frozen-runtime package freshness as an explicit report.
[group("ci")]
ci-freshness:
    uv run --offline --locked --no-sync --group ci python scripts/report_ci_freshness.py

# Regenerates only existing CI lock/guard/document outputs after normal input updates.
[group("ci")]
ci-refresh:
    python scripts/refresh_ci_dependencies.py
    python scripts/refresh_ci_library.py
