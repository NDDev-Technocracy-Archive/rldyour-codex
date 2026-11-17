#!/usr/bin/env bash
set -euo pipefail
base="$1"
head="$2"
if [[ -n "$base$head" ]]; then
  [[ "$base" =~ ^[0-9a-f]{40}$ && "$head" =~ ^[0-9a-f]{40}$ ]] || { echo "Expected two exact Git commits" >&2; exit 1; }
  gitleaks git --no-banner --redact --log-opts="$base..$head" .
else
  gitleaks git --no-banner --redact .
fi
