<!-- Memory Metadata
Last updated: 2026-07-10
Last verified: 2026-07-10
Last commit: 693a00640832d3af8355066c0fd2fda4e84ad78e chore(release): codex adapter 1.8.6
Scope: validation gates and test suites
Area: TESTS
-->

# Validation Gates

## Scope
validation gates and test suites

## Current source of truth
- `path:scripts`
- `path:tests/unit/test_validate_browser_provider_policy.py`
- `path:tests/unit/test_install_system_codex_mcp_inventory.py`
- `path:tests/fixtures/codex_app_managed_browser_config.toml`
- `path:tests/unit/test_release_workflow_estate.py`
- `path:.github/workflows`
- `path:README.md`

## Last verified
- date: 2026-07-10
- commit: `693a00640832d3af8355066c0fd2fda4e84ad78e`
- checked by: Codex app-managed browser bypass regression suite

## Facts
- Test memories record which suites and smoke tests prove the touched behavior.
- `scripts/validate_browser_provider_policy.py --strict` and
  `tests/unit/test_validate_browser_provider_policy.py` reject stale direct
  Chrome package launch docs, missing managed wrapper paths, and unmanaged
  browser fallback language.
- Installer/doctor tests cover table, dotted-key, inline-table, and parent-table
  parsing; realistic app metadata preservation; semantic reinstall idempotency;
  explicit plugin disablement; active-surface reinjection; remediation text;
  curated plugin retention; and exact Chrome transport parity.
- Release workflow regression rejects tag-creation/push commands and requires
  numeric input, exact remote-tag lookup, peeled commit ancestry for tag-push
  and manual paths, and centralized `gh release --verify-tag` publication.

- Automatic CI separates source/unit/static-materialization checks from explicit installed-runtime and live MCP operators. The source profile refuses an ambient Codex runtime. Source/tool inputs are locked before use; just ci-refresh owns only derived CI lock, fixture and coherence/document outputs. Source success does not establish installed-runtime or parent acceptance. Issue36.

## Evidence
- `commit:693a00640832d3af8355066c0fd2fda4e84ad78e`
- `path:scripts`
- `path:tests/unit/test_validate_browser_provider_policy.py`
- `path:tests/unit/test_install_system_codex_mcp_inventory.py`
- `path:tests/fixtures/codex_app_managed_browser_config.toml`
- `path:tests/unit/test_release_workflow_estate.py`
- `path:.github/workflows`
- `path:README.md`

## Known pitfalls
- Treat this memory as derived context. Current code, configuration, runtime output, and GitHub state override stale memory text.

## Update policy
Update after verified changes to the referenced source-of-truth files.

## Delete / merge policy
- Delete or merge only when the referenced source-of-truth files no longer support this memory and the replacement memory preserves the durable facts.

## Applies to

- The scope and source-of-truth paths declared in this memory.

## Source of truth

- The `Current source of truth` entries above, plus current code, configuration, tests, git state, and live GitHub state where this memory references live release or repository surfaces.

## Invariants

- Current code, configuration, tests, validators, git state, and live GitHub state override this memory whenever they disagree.

## Current State

- Treat the `Facts` section as the current durable state. Do not treat historical evidence, superseded notes, or previous release entries as current.

## Do Not Infer

- Do not infer runtime versions, product versions, commits, permissions, release state, security posture, or tool behavior from this memory without checking the source of truth.

## Update Triggers

- Update after verified changes to the source-of-truth files, runtime baselines, release tuple, validation gates, live release state, or durable agent-workflow contracts.

## Validation Commands

- Run the rldyour control-plane Serena memory validators in strict mode: `validate_serena_memory_schema` (`--strict-mode strict-all`) and `validate_serena_memory_semantics` (`--strict-current-facts --strict-metadata-dates --strict-evidence-commits`).

## Repair Procedure

1. Re-read the source-of-truth files listed above.
2. Update only verified current facts; move stale facts into historical evidence.
3. Rerun the validation commands until green.
