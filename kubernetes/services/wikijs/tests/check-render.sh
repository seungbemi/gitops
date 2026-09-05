#!/usr/bin/env bash
set -euo pipefail

chart_dir="$(cd "$(dirname "$0")/.." && pwd)"
disabled="$(mktemp)"
enabled="$(mktemp)"
trap 'rm -f -- "$disabled" "$enabled"' EXIT INT TERM

helm lint "$chart_dir"
helm lint "$chart_dir" --set wikijs.enabled=true

helm template wikijs "$chart_dir" --namespace services \
  --set wikijs.enabled=false >"$disabled"
if grep -Eq '^kind: (Deployment|Service|PersistentVolumeClaim|NetworkPolicy)$' "$disabled"; then
  echo "disabled Wiki.js chart rendered a workload" >&2
  exit 1
fi

helm template wikijs "$chart_dir" --namespace services \
  --set wikijs.enabled=true >"$enabled"

grep -Fq 'image: ghcr.io/requarks/wiki:2.5.314@sha256:68f0d1848261ae76492ba358e30a96a76fed5d97a3fff381656082bf90f70d7e' "$enabled"
grep -Fq 'name: wikijs-secrets' "$enabled"
grep -Fq 'value: postgresql.persistence.svc.cluster.local' "$enabled"
grep -Fq 'value: postgres' "$enabled"
grep -Fq 'path: /healthz' "$enabled"
grep -Fq 'claimName: wikijs-data' "$enabled"
grep -Fq 'kubernetes.io/metadata.name: persistence' "$enabled"

if grep -Eq 'diskstation|volume1|^[[:space:]]+nfs:' "$enabled"; then
  echo "Wiki.js NFS endpoint leaked into the public chart" >&2
  exit 1
fi

if grep -Fiq 'outline' "$enabled"; then
  echo "stale Outline reference found in rendered Wiki.js chart" >&2
  exit 1
fi

echo "Wiki.js chart policy checks passed"
