# Contributing

This repository is a rldyour AI CLI configuration for Codex: plugin marketplace, system install, MCP servers, hooks, managed agents, runtime validation, and Serena memory. It is maintained by [@rldyourmnd](https://github.com/rldyourmnd). Contributions are welcome under the project's AGPL-3.0-or-later license, but the maintainer keeps final authority on direction, plugin boundaries, runtime pins, validation gates, and the agent-context tracking model.

By submitting a pull request, you certify that you have the right to license the contribution under AGPL-3.0-or-later.

Participants must follow the [Code of Conduct](CODE_OF_CONDUCT.md).

## License

This project is licensed under the GNU Affero General Public License v3.0 or later. See [LICENSE](LICENSE). Contributions are accepted under the same license; downstream operators that run modified versions over a network must comply with AGPL-3.0 Section 13.

## Local Setup

Required tools: Git, Python 3.13, uv, Node.js (major 24), Bun (pinned in `config/mcp-runtime-versions.env`), Dart (pinned), jq, ripgrep, shellcheck, and Codex CLI.

```bash
uv run --with pytest --with pytest-cov --with pyyaml python -m pytest
python3 scripts/validate_action_pins.py
python3 scripts/scan_text_security.py
scripts/validate_fast.sh
scripts/validate_marketplace.sh
```

Use the devcontainer in `.devcontainer/` when you need a clean, production-like local validation environment.

## Branches

- `main`: primary integration branch. It carries product source and agent context (`.serena/`, `AGENTS.md`, `.claude/`) as ordinary tracked files. Auto-running CI gates fast/runtime/release/MCP smoke on every push and pull request.
- `feat/<topic>`, `fix/<topic>`, `chore/<topic>`: feature/fix/chore branches. Open a pull request targeting `main`.

## Pull Requests

- Open a pull request against `main` with a clear, scope-limited change.
- Title format: Conventional Commits (`type(scope): description`). Types: `feat`, `fix`, `refactor`, `docs`, `test`, `chore`, `perf`, `style`, `ci`, `build`. Scope is the plugin or area, lowercase.
- Description must include intent, surface touched, evidence (validation logs, screenshots when relevant), and risks.
- Keep commits atomic. Split unrelated implementation, tests/validators,
  docs/instructions, license/metadata, generated artifacts, and Serena knowledge
  sync when they are independently reviewable. Squash trivial fixups before
  review.
- Do not rewrite already-pushed history without explicit maintainer approval;
  use a follow-up commit for published branches.
- Reference any related ADR under `docs/adr/` or open one when the change is architectural.
- Sign-off is not required.

## CI Expectations

All pull requests run the following workflows automatically:

- `validate`: Ubuntu-hosted fast/runtime/release/MCP scopes, MCP runtime pin freshness (advisory only on pull requests), and MCP safe-call smoke.
- `cross-platform`: lightweight metadata/path smoke on standard Ubuntu, Windows, and macOS public runners.
- `security-static`: action pins, actionlint, text security scan, ShellCheck, and Pyright. Also runs on a weekly schedule.
- `codeql`: GitHub CodeQL analysis for Python and GitHub Actions with `security-and-quality` queries. Also runs on a weekly schedule.
- `dependency-review`: blocks merges that introduce dependencies with high-severity vulnerabilities or licenses outside the AGPL-3.0-or-later compatible allow-list.
- `labeler`: applies area labels based on changed paths.

In addition, on push to `main` and on a weekly schedule:

- `scorecard`: OpenSSF Scorecard analysis in JSON artifact/check mode with the badge result published to `scorecard.dev`.
- `dependency-check` (`MCP runtime pin freshness (scheduled)`): runs on push to MCP pin sources and on manual dispatch; reports stale pins in its summary and artifact without failing, because the frozen repository keeps its final runtime pins.

A pull request is mergeable only when these checks complete and pass. Maintainers may dispatch additional scoped runs through `workflow_dispatch`.

## Change Rules

- Keep repository artifacts in English. Maintainer-facing conversation in issues/PRs may be in Russian or English.
- Do not commit credentials, tokens, cookies, private keys, browser artifacts, diagnostics, or runtime caches. `scripts/scan_text_security.py` enforces this.
- Keep `rldyour-mcps` transport-only. Do not move behavior policy or skills into it.
- Keep external GitHub Actions pinned to full commit SHAs. `scripts/validate_action_pins.py` enforces this.
- Add or update an ADR under `docs/adr/` for non-trivial architecture, release, CI, hook, MCP, or governance decisions.
- Update `VERSION` and `CHANGELOG.md` for release behavior changes. Use Keep a Changelog format.
- Update Serena memories under `.serena/memories/` and instruction docs (`AGENTS.md`, `.claude/CLAUDE.md`) from verified code/config facts after durable workflow changes. These files are tracked normally on `main` as ordinary source.
- Conventional Commit messages are required: `type(scope): description`, imperative mood, lowercase, no trailing period, 72-char max.

## Releases

Releases use numeric Semantic Versioning (`X.Y.Z`). To prepare a release:

1. Bump `VERSION`.
2. Add a new `## [X.Y.Z] - YYYY-MM-DD` section to `CHANGELOG.md` with `Added`, `Changed`, `Fixed`, `Security` subsections as needed.
3. Run `scripts/validate_release.sh` locally.
4. Open a pull request, merge to `main` after CI passes.
5. After the exact release commit is on `main` and branch CI is stably green,
   create and push the signed numeric tag matching `X.Y.Z`. The `release.yml`
   workflow verifies the exact remote tag and its ancestry from `origin/main`,
   builds the deterministic bundle, generates the SPDX SBOM, attaches artifact
   attestations, and publishes through `gh release --verify-tag`.

`workflow_dispatch` of `release.yml` only verifies or retries an existing
numeric tag. It never creates or pushes a tag.

## Validation Quick Reference

```bash
scripts/validate_fast.sh
scripts/validate_runtime.sh --strict-runtime
scripts/validate_release.sh
scripts/validate_marketplace.sh
python3 scripts/scan_text_security.py
python3 scripts/validate_action_pins.py
python3 scripts/validate_plugin_versions.py
python3 scripts/validate_skill_routing.py
python3 scripts/validate_instruction_docs.py --require-agent-docs
uv run --with pyyaml python scripts/validate_agent_tools.py
uv run --with pytest --with pytest-cov --with pyyaml python -m pytest
```

## Reporting Issues

Open a GitHub issue using one of the provided templates under `.github/ISSUE_TEMPLATE/`. For private vulnerability reports, see [SECURITY.md](SECURITY.md).
