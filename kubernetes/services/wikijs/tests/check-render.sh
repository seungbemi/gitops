#!/usr/bin/env bash
set -euo pipefail

chart_dir="$(cd "$(dirname "$0")/.." && pwd)"
disabled="$(mktemp)"
enabled="$(mktemp)"
access_policy_enabled="$(mktemp)"
trap 'rm -f -- "$disabled" "$enabled" "$access_policy_enabled"' EXIT INT TERM

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

grep -Fq 'image: ghcr.io/requarks/wiki:2.5.316@sha256:68f0d1848261ae76492ba358e30a96a76fed5d97a3fff381656082bf90f70d7e' "$enabled"
grep -Fq 'name: wikijs-secrets' "$enabled"
grep -Fq 'value: postgresql.persistence.svc.cluster.local' "$enabled"
grep -Fq 'value: postgres' "$enabled"
grep -Fq 'path: /healthz' "$enabled"
grep -Fq 'claimName: wikijs-data' "$enabled"
grep -Fq 'name: wikijs-auth-oauth2-migration-v1' "$enabled"
grep -Fq "provider.\"strategyKey\" <> 'oidc'" "$enabled"
grep -Fq "'enableCSRFProtection', true" "$enabled"
grep -Fq 'name: wikijs-auth-internal-endpoints-v1' "$enabled"
if [[ "$(grep -Fc 'argocd.argoproj.io/sync-options: Force=true,Replace=true' "$enabled")" -ne 2 ]]; then
  echo "expected both default Wiki.js migration Jobs to use Argo CD replacement syncs" >&2
  exit 1
fi
grep -Fq "'tokenURL', 'http://authentik-server.services.svc.cluster.local/application/o/token/'" "$enabled"
grep -Fq 'app.kubernetes.io/component: server' "$enabled"
grep -Fq 'port: 9000' "$enabled"

if grep -Fq 'kind: Job' "$enabled" && grep -Fq 'wikijs-access-policy-' "$enabled"; then
  echo "identity-specific Wiki.js access policy rendered without private values" >&2
  exit 1
fi

helm template wikijs "$chart_dir" --namespace services \
  --set wikijs.enabled=true \
  --set accessPolicy.enabled=true \
  --set accessPolicy.revision=test >"$access_policy_enabled"
if [[ "$(grep -Fc 'argocd.argoproj.io/sync-options: Force=true,Replace=true' "$access_policy_enabled")" -ne 3 ]]; then
  echo "expected all three Wiki.js migration Jobs to use Argo CD replacement syncs" >&2
  exit 1
fi
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
