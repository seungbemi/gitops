#!/usr/bin/env bash
set -euo pipefail

chart_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
rendered="$(mktemp)"
cutover_rendered="$(mktemp)"
trap 'rm -f "$rendered" "$cutover_rendered"' EXIT

helm lint "$chart_dir"
helm template postgresql "$chart_dir" --namespace persistence >"$rendered"

grep -Fq 'name: postgresql-v17' "$rendered"
grep -Fq 'name: postgresql-v17-hl' "$rendered"
grep -Fq 'name: postgresql-v17-metrics' "$rendered"
grep -Fq 'image: "ghcr.io/seungbemi/postgres-vectorchord:17.11-pgvector0.8.6-vchord1.1.1@sha256:f0f3b52a14563ee4e87e91a906b17ab70a35fcfdb01eaa7885abde3e9377f74a"' "$rendered"
grep -Fq 'storage: 16Gi' "$rendered"
grep -Fq 'shared_preload_libraries=vchord.so' "$rendered"
grep -Fq 'whenDeleted: Retain' "$rendered"

stable_services="$(awk '$0 == "kind: Service" { service = 1; next } service && $1 == "name:" { if ($2 == "postgresql") count++; service = 0 } END { print count + 0 }' "$rendered")"
test "$stable_services" -eq 1

if helm template postgresql "$chart_dir" --namespace persistence \
  --set postgresql17.cutover=true >/dev/null 2>&1; then
  echo 'unsafe cutover rendered while the PostgreSQL 14 dependency was enabled' >&2
  exit 1
fi

helm template postgresql "$chart_dir" --namespace persistence \
  --set postgresql.enabled=false \
  --set postgresql17.cutover=true >"$cutover_rendered"
stable_services="$(awk '$0 == "kind: Service" { service = 1; next } service && $1 == "name:" { if ($2 == "postgresql") count++; service = 0 } END { print count + 0 }' "$cutover_rendered")"
test "$stable_services" -eq 1
grep -Fq 'app.kubernetes.io/instance: postgresql-v17' "$cutover_rendered"

grep -Fq 'name: backup-postgres-cronjob' "$rendered"
grep -Fq 'pg_dumpall' "$rendered"
grep -Fq 'retentionDays' "$chart_dir/values.yaml"
