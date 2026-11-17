# GitHub Actions workflows

Automatic source CI runs on public hosted workers. The project owns Just
commands; the shared library prepares exact SDKs, caches, reports and merge
stops. Runtime configuration, installed vendor compatibility and publication
are separate scopes.

## Shared Workflow Pin

The caller declarations use engine version `v0.6.67` at commit
`a12acfc75fd7daee2fac9a246ee60683fe18955b`. `just ci-refresh` derives this section and the
existing coherence guard from the complete workflow input set. It never moves a caller pin.

## Required source gates

- ci.yml runs the original fast/unit/coverage suite, offline source/type/security
  checks, static materialization without an installed Codex runtime, release
  metadata/SBOM checks and Linux/Windows/macOS metadata compilation.
- The frozen MCP package-freshness report stays advisory; its actual command
  exit is retained beside the report. Missing or malformed reports fail.
- The aggregate requires every actual source/platform outcome and the shared
  merge stops on a pull request.
- security.yml preserves both CodeQL languages, Scorecard and dependency review.
- dependency-check.yml retains the source-pin-change/report trigger.

The desired branch context declaration is in branch-protection/main.json.
Repository settings must bind the actual emitted names, after real CI evidence;
this document does not apply settings or fabricate statuses.

## Explicit operator workflows

runtime-verification.yml preserves the existing installed-runtime and live MCP
jobs behind workflow_dispatch. It stays outside source admission.
release.yml only verifies/publishes an existing numeric tag; it cannot create
or push one. Source success proves neither installed runtime nor parent/release
acceptance.

## Dependency preparation and derived CI outputs

just setup installs the locked CI group without building this virtual package.
Source/test commands run offline/locked/no-sync after preparation. The MCP SDK
comes from the frozen config/mcp-runtime-versions.env; the CI lock must agree.
The same file supplies the Codex version of the isolated, locked operator NPM
fixture. Preparing metadata does not install or execute that fixture.

After a complete normal updater change, just ci-refresh regenerates only
uv.lock, the derived operator fixture manifests/lock, this pin section and the
existing coherence guard. It never edits a caller pin or frozen runtime setting.
The updater must qualify that producer in its isolated command contract.
