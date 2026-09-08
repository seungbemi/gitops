#!/usr/bin/env bash
set -euo pipefail

chart_dir="$(cd "$(dirname "$0")/.." && pwd)"
rendered="$(mktemp)"
trap 'rm -f -- "$rendered"' EXIT INT TERM

helm lint "$chart_dir"
helm template paperless "$chart_dir" --namespace services >"$rendered"

grep -Fq 'name: verify-nfs-write' "$rendered"
grep -Fq 'runAsUser: 1000' "$rendered"
grep -Fq 'periodSeconds: 5' "$rendered"
grep -Fq 'failureThreshold: 60' "$rendered"
grep -Fq 'periodSeconds: 10' "$rendered"
grep -Fq 'periodSeconds: 30' "$rendered"
grep -Fq 'timeoutSeconds: 3' "$rendered"
if [ "$(grep -c 'value: localhost' "$rendered")" -ne 3 ]; then
  echo "all Paperless probes must use an allowed localhost Host header" >&2
  exit 1
fi

echo "Paperless chart probe checks passed"
