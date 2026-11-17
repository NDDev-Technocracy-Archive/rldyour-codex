# rldyour-codex

`rldyour-codex` is the rldyour AI CLI configuration for Codex: plugin marketplace, system install, MCP servers, hooks, managed agents, runtime validation, and Serena memory.

[![validate](https://github.com/rldyourmnd/rldyour-codex/actions/workflows/validate.yml/badge.svg?branch=main)](https://github.com/rldyourmnd/rldyour-codex/actions/workflows/validate.yml)
[![security-static](https://github.com/rldyourmnd/rldyour-codex/actions/workflows/security-static.yml/badge.svg?branch=main)](https://github.com/rldyourmnd/rldyour-codex/actions/workflows/security-static.yml)
[![CodeQL](https://github.com/rldyourmnd/rldyour-codex/actions/workflows/codeql.yml/badge.svg?branch=main)](https://github.com/rldyourmnd/rldyour-codex/actions/workflows/codeql.yml)
[![OpenSSF Scorecard](https://api.scorecard.dev/projects/github.com/rldyourmnd/rldyour-codex/badge)](https://scorecard.dev/viewer/?uri=github.com/rldyourmnd/rldyour-codex)
[![License: AGPL-3.0-or-later](https://img.shields.io/badge/License-AGPL--3.0--or--later-blue.svg)](https://www.gnu.org/licenses/agpl-3.0)
[![Latest Release](https://img.shields.io/github/v/release/rldyourmnd/rldyour-codex)](https://github.com/rldyourmnd/rldyour-codex/releases/latest)

`rldyour-codex` is a rldyour AI CLI configuration package for Codex: plugin marketplace, system install, MCP servers, hooks, managed agents, runtime validation, and Serena memory. It is authored by Danil Silantyev (github:rldyourmnd), CEO NDDev and owns rldyour plugins, MCP server runtime definitions, skills, Codex lifecycle hooks, managed subagent role configs, execpolicy rules, validation scripts, installer/rollback tooling, CI checks, and Serena project knowledge.

It is not a generic preset, not an automatic configuration takeover, and not a bundle of unrelated third-party opinions. It is a controlled catalog where nothing is treated as enabled or correct unless explicitly decided by the maintainer.

## Current Baseline

| Field | Value |
|---|---|
| Adapter version | `1.8.19` |
| Runtime baseline | Codex CLI 0.144.1 (`@openai/codex`) |
| Browser wrapper baseline | CloakBrowser 0.4.10 (`cloakbrowser`; bootstrap-owned) |
| GitHub release tag | `1.8.19` |

The runtime baseline reference is `references/codex-baseline.json`, verified 2026-07-10. The npm package is `@openai/codex`; the upstream release artifact is at `https://github.com/openai/codex/releases/tag/rust-v0.144.1`.

## What This Repository Provides

`rldyour-codex` is a configuration package for the Codex CLI - it is not a fork of the upstream Codex runtime and does not modify Codex internals. It owns the plugin marketplace definition, system installer and rollback tooling, managed subagent role configs, execpolicy rules, MCP server runtime definitions, lifecycle hooks, skills, runtime validation lanes, CI workflows, and Serena project memory for the Codex adapter. The active catalog currently includes 11 plugins and 45 skills. Slash commands are intentionally absent; Codex uses skills and managed subagents as the public invocation surface.

## Native Boundaries

Codex reads configuration from TOML files rooted at `$CODEX_HOME` (default `~/.codex`):

- `~/.codex/config.toml`: main config - model defaults, `[tui]` status line, global permissions posture, centrally managed update policy, and `[mcp_servers.*]` runtime MCP server entries.
- `~/.codex/rldyour-yolo.config.toml`: `--profile rldyour-yolo` overlay - `approval_policy = "never"`, `sandbox_mode = "danger-full-access"`, owner-standard full-auto defaults.
- `~/.codex/rldyour-safe.config.toml`: `--profile rldyour-safe` overlay - `approval_policy = "on-request"`, `sandbox_mode = "workspace-write"`.
- `~/.codex/agents/*.toml`: managed subagent role configs, installed from `system/agents/*.toml`.
- `~/.codex/rules/`: managed execpolicy rules, installed from `system/rules/*.rules`.

The installer sets `check_for_update_on_startup = false` in all three managed
config files. Codex upgrades are transactional bootstrap operations against the
exact runtime pin, rather than self-updates into whichever global npm prefix is
visible to a session.

The repository's `plugins/rldyour-mcps/.mcp.json` is the portable source of truth for MCP server definitions. The installer resolves portable commands (`uvx`, `bunx`, `dart`) to local executable paths and writes the resolved entries to `[mcp_servers.*]` in `~/.codex/config.toml`; `.mcp.json` is plugin metadata, not a Codex-native runtime format. The Codex plugin format is `plugins/<plugin>/.codex-plugin/plugin.json` with manifest-linked skills, hooks, and assets. The marketplace catalog is `.agents/plugins/marketplace.json`.

MCP launcher packages are pinned in `.mcp.json` and mirrored in `config/mcp-runtime-versions.env`; marketplace validation fails if these sources drift. Host runtime pins for Node major, Bun, Dart SDK, and GitHub MCP also live in `config/mcp-runtime-versions.env` so local setup, GitHub Actions, and the devcontainer share one source of truth.

## Install / Update / ry-repair

**Runtime install or update** - on machines that need a Codex CLI install or update:

```bash
bun add -g @openai/codex@0.144.1
codex --version
codex doctor
```

The repository bootstrap owns verified system installation. This adapter does
not recommend piping a mutable network response into a shell.

**System config install** - dry-run first, then apply:

```bash
scripts/install_system_codex.sh --dry-run
scripts/install_system_codex.sh --apply
scripts/doctor_system_codex.sh
```

Apply the owner-standard full-access profile explicitly:

```bash
scripts/install_system_codex.sh --apply --owner-mode
```

Conservative override (safe mode):

```bash
scripts/install_system_codex.sh --apply --safe-mode
scripts/doctor_system_codex.sh --safe-mode
```

Strict runtime mode (fully reproducible environment):

```bash
scripts/install_system_codex.sh --apply --strict-runtime
scripts/doctor_system_codex.sh --strict-runtime
python3 scripts/validate_runtime_prereqs.py --strict --require-codex
```

Full bootstrap smoke on a new or resynced machine:

```bash
scripts/bootstrap_check.sh --apply
```

**ry-repair convergence** - plan and apply installed-runtime diagnostics:

```bash
scripts/ry_repair_sync.py --plan --apply-system --latest-from-github --json
```

Reports `NOT PROVEN` when `codex` is not available locally.

**Plugin marketplace local install:**

```bash
codex plugin marketplace add .
codex plugin list --json
```

The installer writes `~/.codex/AGENTS.md`, managed subagent role configs, execpolicy rules, registered marketplace, enabled plugins, approved MCP servers, Codex lifecycle hooks, the official Codex config schema hint, owner-standard full-auto permission defaults (unless `--safe-mode`), both profile layers, maintainer-selected model defaults, approved MCP tool overrides, the owner `[tui]` status line, and the versioned local plugin cache at `~/.codex/plugins/cache/rldyour-codex/<plugin>/<version>`. Existing managed files are backed up before write operations. Credentials and OAuth tokens are never written.

The same install pass explicitly disables `browser@openai-bundled`. Existing
app-managed `node_repl` and `computer-use` MCP tables keep their transport
metadata but are forced to `enabled = false`. Doctor rejects an active or
reinjected raw/in-app/computer-use surface and instructs the operator to rerun
the installer and restart Codex.

## Active Catalog

The active marketplace contains 11 plugins and 45 skills:

**Plugins:**

- `rldyour-mcps`: the maintainer's approved MCP server set for Codex.
- `rldyour-explore`: research skills for technical MCP research and authoritative web research.
- `rldyour-serena-mcp`: Serena-first semantic code workflow, fact-only `.serena` memory sync, plans, research archive, and lifecycle hooks.
- `rldyour-security`: non-blocking OWASP Top 10 2025 secure-implementation guidance and `ry-sec-review` security review skill.
- `rldyour-browser`: fail-closed CloakBrowser workflows through managed Playwright CLI and Chrome DevTools MCP.
- `rldyour-design`: Figma → code, centralized i18n, dynamic/static content classification, token-based design system, reusable UI kit, strict FSD frontend architecture, shadcn/ui, ReactBits, and browser validation workflows.
- `rldyour-lsps`: language-server routing, health checks, brew-first setup profiles, and Serena LSP integration guidance.
- `rldyour-flow`: autonomous SDLC workflows for `ry-init`, `ry-start`, `ry-newp`, `ry-review`, `ry-repair`, `ry-deploy`, scoped context packs, context sufficiency gates, instruction docs sync, fast offline SessionStart worktree bootstrap/context dispatcher hooks, cwd-safe PreToolUse guardrails, advisory commit hooks, reviewer tracks, and post-task synchronization.
- `rldyour-rules`: quality-first engineering rules, architecture boundaries, implementation discipline, dependency compatibility, verification gates, Codex and Claude Code project instructions, ADR policy, and `ry-rules-review`.
- `rldyour-orchestrator`: cmux orchestrator and worker skills for macOS multi-pane orchestration.

**MCP servers** (11): `chrome-devtools`, `context7`, `dart-flutter`, `deepwiki`, `figma`, `grep`, `github`, `openaiDeveloperDocs`, `sequential-thinking`, `serena`, `shadcn`.

**Managed subagents** (8 roles): `research-explorer`, `architecture-reviewer`, `browser-tester`, `consistency-reviewer`, `quality-reviewer`, `security-audit`, `test-reviewer`, `serena-sync`.

**Hooks** (9 lifecycles): `UserPromptSubmit` sync-required check, `SessionStart` context dispatcher, `Stop` memory-sync and lifecycle dispatcher, `PostToolUse` commit advice and sync marker, `PreToolUse` cwd guard and git policy.

**Execpolicy rules** (`system/rules/*.rules`): hard rails for root deletion, direct forced Git pushes, secret-key disclosure, and release/deploy side effects.

The Codex adapter contract lives in `config/rldyour-contract.json` and is documented in `docs/contract-matrix.md`. Validate it with `python3 scripts/validate_contract.py`.

Architecture decisions:

- No separate `rldyour-hooks` plugin - hooks live inside the plugin that owns the lifecycle behavior.
- No separate `rldyour-memories` plugin - project memory behavior belongs to `rldyour-serena-mcp`.
- No `rldyour-sec` alias plugin - security behavior belongs to `rldyour-security`.

## Browser / Design / DevTools Routing

Browser automation uses two active providers, routed by task type per the root
control-plane `config/browser-automation-policy.json`:

- **Playwright CLI** (`rldyour-browser`): exact
  `$HOME/.local/bin/playwright-cli` for browser-driven validation and
  decomposed long-horizon workflows; `run-code` and `--filename` are forbidden.
- **Chrome DevTools MCP** (`plugins/rldyour-mcps`): MCP provider for DevTools protocol access - screenshots, network inspection, console, performance traces, and heap snapshots - via the `chrome-devtools` MCP server.

Before every browser action, the skill contract executes exactly
`$HOME/.local/bin/cloakbrowser-cdp-health`; missing or nonzero health fails
closed as `NOT_PROVEN`. Chrome DevTools MCP is allowed only through the exact
managed `/bin/sh -c` wrapper transport. The required browser engine is the
bootstrap-managed CloakBrowser wrapper. Its
adapter policy pin is `CLOAKBROWSER_VERSION=0.4.10`; the adapter rejects a
stock-Chromium fallback and keeps Chrome DevTools MCP on the exact
`~/.local/bin/chrome-devtools-mcp` transport. Installation and browser-binary
ownership remain with `rldyour-new-mac-or-ubuntu`. Upstream `v0.4.10` is a
wrapper-only release that fixes iframe humanization and the JavaScript CLI
entry point without changing the browser binaries; see the
[`v0.4.10` tag](https://github.com/CloakHQ/CloakBrowser/tree/v0.4.10)
and [PyPI package](https://pypi.org/project/cloakbrowser/0.4.10/).

The historical `webwright-task` skill name is compatibility-only and routes to
managed Playwright CLI/Chrome DevTools MCP; Webwright runtime, Python
Webwright, stock/raw/in-app Browser, `browser_agent`, `node_repl`,
`computer-use`, Playwright MCP/raw Playwright, direct `bunx`/`npx` packages,
alternate CDP/config/executables, and all browser fallbacks are forbidden.

The `rldyour-design` plugin provides Figma → code workflows, FSD frontend architecture, token-based design system implementation, shadcn/ui integration, ReactBits, and browser validation workflows layered on top of these browser providers.

Managed subagents (`browser-tester`) handle browser-tester review tracks. Specialist MCP servers (`figma`, `chrome-devtools`, `dart-flutter`, `shadcn`) are disabled inside managed subagents and remain parent-session tools for explicit design, browser, Flutter, or shadcn work.

## Repository Context / Serena Memory

**Agent context is tracked normally on `main`.** `.serena/memories/`, `.serena/project.yml`, `.serena/plans/`, `.serena/research/`, `.serena/newproj/`, `.serena/deploy/`, `AGENTS.md`, and `.claude/` are ordinary source files committed to `main` alongside plugins, scripts, config, CI, docs, and generated skill bridges. There is no separate agent-context branch and no agent-only overlay; tooling and CI read the checked-out tree directly.

Only runtime-local state stays gitignored: `.serena/cache/`, `.serena/reviews/`, `.serena/diagnostics/`, `.serena/project.local.yml`, and the `.serena/.*` markers/state/locks.

```bash
scripts/worktree_add.sh <branch> [path]
```

A new worktree of a branch already carries that branch's tracked agent context; no restore or bootstrap step is required.

**Serena memory** is managed by `rldyour-serena-mcp`. Memory is fact-only: verified code, git diffs, and test results - no speculation, plans, chat history, or secrets. The `serena-sync` managed subagent handles memory synchronization on the `Stop` hook advisory.

**Local pre-push guard:**

```bash
scripts/install_local_git_hooks.sh --dry-run
scripts/install_local_git_hooks.sh --apply
```

By default the guard allows agent context and AI markers (they are tracked source) while always blocking credentials, runtime markers, browser artifacts, and local env files. A project may opt into strict agent-file protection through `.rldyour/project-policy.json`.

In external or colleague-owned repositories, `.rldyour/project-policy.json` is the executable source of truth and may set strict agent-file protection, disable instruction-docs sync, and disable branch-cleanup blockers.

## Security Boundary

The owner full-auto standard posture is the `rldyour-yolo` profile:

- `approval_policy = "never"`
- `sandbox_mode = "danger-full-access"` (legacy sandbox dialect)
- No active `default_permissions` permission-profile field while `sandbox_mode` is present

Launch with the owner-standard full-auto profile:

```bash
codex --profile rldyour-yolo --dangerously-bypass-approvals-and-sandbox
```

This posture grants unrestricted shell access on the owner workstation. It is not a sandbox. Permissions are not a security boundary in this mode - they are an ergonomic preference. The conservative override is `--safe-mode` (`approval_policy = "on-request"`, `sandbox_mode = "workspace-write"`).

**Execpolicy rules** (`system/rules/*.rules`) add hard behavioral rails independent of the permission model: they block root deletion, direct forced Git pushes, secret-key disclosure, and release/deploy side effects. Validate with `codex execpolicy check`.

**Secrets policy:** credentials, OAuth tokens, cookies, and private keys are never stored in this repository. MCP server credentials are environment-variable-injected at runtime. GitHub Actions workflows pin external actions to full commit SHAs with the human-readable tag as an inline comment; pin enforcement is checked by `scripts/validate_action_pins.py` and gated in CI.

**MCP trust boundary:** only the servers listed in `plugins/rldyour-mcps/.mcp.json` are approved. Local MCP launcher packages are pinned in `.mcp.json` and `config/mcp-runtime-versions.env`; validation fails on drift. OAuth-gated MCP endpoints are skipped in capability smoke unless `--include-auth` is explicitly passed.

See [SECURITY.md](SECURITY.md) for private disclosure procedure and supported surface. Report vulnerabilities through GitHub Security Advisories.

## Validation

**Fast / static:**

```bash
scripts/validate_fast.sh
python3 scripts/validate_contract.py
python3 scripts/validate_action_pins.py
python3 scripts/validate_runtime_prereqs.py
plugins/rldyour-flow/scripts/instruction_docs_state.py --json | python3 -m json.tool
python3 scripts/validate_instruction_docs.py --require-agent-docs
```

**Adapter-deep:**

```bash
scripts/validate_release.sh
scripts/validate_execpolicy_rules.sh
python3 scripts/validate_agent_tools.py
```

**Installed-runtime:**

```bash
scripts/validate_runtime.sh --strict-runtime
scripts/doctor_system_codex.sh
scripts/doctor_system_codex.sh --quick --strict-runtime
scripts/smoke_hooks.sh
scripts/smoke_local_git_guard.sh
scripts/smoke_flow_branch_cleanup.sh
scripts/smoke_serena_memory_freshness.sh
scripts/smoke_serena_memory_taxonomy.sh
```

**Live-network / MCP:**

```bash
scripts/smoke_mcp_runtime.sh
scripts/smoke_mcp_capabilities.sh
```

`scripts/smoke_mcp_runtime.sh` validates remote MCP endpoints with a Streamable HTTP `initialize` POST preflight. OAuth-gated endpoints may pass with `401`/`403`; `405` is not accepted as a POST initialize result. `scripts/smoke_mcp_capabilities.sh` runs `initialize`, `list_tools`, and safe `call_tool` probes, retrying each server five times to absorb transient failures. Figma is skipped by default; pass `--include-auth` only after authorizing that runtime.

**NOT_PROVEN policy:** any smoke lane that requires a live runtime (`codex`, installed MCP, network endpoints) reports `NOT PROVEN` when the dependency is unavailable locally; it does not fail the static gate.

## Release / Rollback

Adapter version is stored in `VERSION`. Plugin behavior versions stay in `plugins/<plugin>/.codex-plugin/plugin.json`. Release notes live in `CHANGELOG.md`. A numeric GitHub Release is required for every public adapter product version; a `VERSION` file alone is not sufficient.

The `release.yml` GitHub Actions workflow triggers on a numeric SemVer tag
matching `X.Y.Z`. It fetches `origin/main`, verifies the exact remote tag object
and peeled commit, and rejects any tag outside `origin/main` before validating
`VERSION` and `CHANGELOG.md`, building the deterministic bundle, generating the
release manifest and SPDX 2.3 SBOM, exporting the GitHub dependency-graph SBOM
when available, attaching artifact attestations, and publishing through
`gh release --verify-tag`. Manual dispatch only verifies an existing numeric
tag; the workflow never creates or pushes tags.

Operational commands:

```bash
python3 scripts/release_manifest.py
python3 scripts/check_mcp_runtime_versions.py
scripts/rollback_system_codex.sh --list
scripts/collect_diagnostics.sh
```

Reference docs:

- [docs/release-process.md](docs/release-process.md): versioning, changelog, release evidence, and tag flow.
- [docs/rollback-restore.md](docs/rollback-restore.md): safe restore from installer backups or older Git tags.
- [docs/dependency-updates.md](docs/dependency-updates.md): pinned MCP runtime update policy.
- [docs/observability.md](docs/observability.md): diagnostics, CI artifacts, and failure triage.
- [docs/github-branch-protection.md](docs/github-branch-protection.md): desired branch protection state.

## Support / License

**License:** AGPL-3.0-or-later. See [LICENSE](LICENSE) for the full text. The AGPL-3.0 Remote Network Interaction clause (Section 13) applies: if you run a modified version and make it available to others over a network, you must offer the corresponding source under the same license. Operating the unmodified upstream release does not trigger additional obligations.

**Author:** Danil Silantyev (github:rldyourmnd), CEO NDDev.

**Security contact:** report vulnerabilities privately through GitHub Security Advisories at `https://github.com/rldyourmnd/rldyour-codex/security/advisories`. See [SECURITY.md](SECURITY.md) for the supported surface and private disclosure procedure.

**Contributing:** see [CONTRIBUTING.md](CONTRIBUTING.md) for local setup, validation, change rules, and pull request expectations. Participants are expected to follow [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md).

Copyright (C) 2026 Danil Silantyev (github:rldyourmnd), CEO NDDev. This program is free software: you can redistribute it and/or modify it under the terms of the GNU Affero General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version.

## Source-only CI maintenance

The shared source workflow runs `just check`, the existing unit/coverage
suite and isolated static materialization. `just setup` prepares the locked
CI group first; `just ci-refresh` derives CI lock/guard/document outputs after
complete normal updater input changes. The frozen runtime pins remain in their
existing configuration source. Installed-runtime/live MCP verification and
publication remain explicit operator workflows, outside source admission.
