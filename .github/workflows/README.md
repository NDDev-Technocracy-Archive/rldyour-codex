# GitHub Actions Workflows

Ten workflows provide the public/free CI surface for the Codex adapter. The
repository is public, so standard GitHub-hosted runners do not consume the
owner's private-repository Actions minutes. Keep every workflow on standard
runner labels and keep third-party actions pinned to full commit SHAs.

## Shared Workflow Pin

Every `NDDev-Technocracy-Standarts/std-0004-ci-cd-workflows` action caller is
pinned to engine version `nddev-cicd-v0.6.18` at commit
`9cc44a5043ddd266f3e73fefacc52f5cf5a7d70f`. The repository test
`tests/unit/test_shared_workflow_pin.py` rejects a mixed SHA or version comment.

## Required PR Gates

| Workflow | Purpose |
| --- | --- |
| `validate.yml` | Fast validation and optional runtime/release/MCP scopes on Ubuntu standard runners. |
| `cross-platform.yml` | Lightweight metadata/path smoke on standard Ubuntu, Windows, and macOS public runners. |
| `security-static.yml` | Action pin validation, actionlint, text security scan, ShellCheck, and Pyright. |
| `secret-scan.yml` | Gitleaks history scan for accidental secrets. |
| `codeql.yml` | CodeQL code scanning for the adapter source surface. |
| `dependency-review.yml` | Pull-request dependency diff review. |

## Supply-Chain And Drift Gates

| Workflow | Trigger | Purpose |
| --- | --- | --- |
| `scorecard.yml` | push, weekly, manual, branch-protection changes | OpenSSF Scorecard JSON artifact/check-mode supply-chain signal. |
| `dependency-check.yml` | daily, config changes, manual | MCP/runtime pin freshness and dependency report. |
| `labeler.yml` | pull requests | Unprivileged PR labels, skipped for forks. |

## Release Gate

| Workflow | Trigger | Purpose |
| --- | --- | --- |
| `release.yml` | numeric product tag or existing-tag manual dispatch | Verifies the exact remote tag and its ancestry from `origin/main`, then runs release validation, deterministic bundle, SBOM, attestations, and `gh release --verify-tag`; it never creates or pushes tags. |

## Cost Policy

- Public adapter CI must stay on standard GitHub-hosted runner labels only.
- No self-hosted, larger, runner-group, ARC, private organization, or paid-size
  runner labels.
- The public/free baseline includes one lightweight cross-platform workflow on
  standard Ubuntu, Windows, and macOS runners. Runtime-heavy and release jobs
  may stay Ubuntu-only when the local script is OS-independent or the required
  toolchain is Linux-only.
- Workflow artifacts must set explicit retention and stay at or below 30 days.
- Heavy or drift-oriented checks use schedules/manual dispatch where practical.
