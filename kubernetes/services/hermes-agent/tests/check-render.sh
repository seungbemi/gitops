#!/usr/bin/env bash
set -euo pipefail

chart_dir="$(cd "$(dirname "$0")/.." && pwd)"
rendered="$(mktemp)"
admin_rendered="$(mktemp)"
rina_rendered="$(mktemp)"
invalid="$(mktemp)"
disabled="$(mktemp)"
numeric_ids="$(mktemp)"
trap 'rm -f -- "$rendered" "$admin_rendered" "$rina_rendered" "$invalid" "$disabled" "$numeric_ids"' EXIT INT TERM

helm lint "$chart_dir"

if grep -Fq 'app.kubernetes.io/name:' "$chart_dir/templates/common.yaml"; then
  echo "common controller values must not override selector-owned name labels" >&2
  exit 1
fi

helm template hermes-disabled "$chart_dir" >"$disabled"
if grep -Eq '^kind: (Deployment|ServiceAccount|PersistentVolumeClaim)$' "$disabled"; then
  echo "disabled chart rendered a workload" >&2
  exit 1
fi

if helm template hermes "$chart_dir" \
  --set 'profile.enabled=true' \
  --set 'profile.name=admin' >"$invalid" 2>&1; then
  echo "enabled profile rendered without Telegram IDs" >&2
  exit 1
fi

if helm template hermes "$chart_dir" \
  --set 'profile.enabled=true' \
  --set 'profile.name=admin' \
  --set 'profile.kubernetes.scope=cluster' \
  --set 'profile.runtimeSecretName=hermes-admin-runtime' \
  --set 'profile.telegram.allowedUserIds[0]=123456789' \
  --set 'profile.telegram.adminUserIds[0]=123456789' \
  --set 'knowledgeBase.enabled=true' >"$invalid" 2>&1; then
  echo "knowledge base rendered without the policy gateway" >&2
  exit 1
fi

helm template hermes-admin "$chart_dir" --namespace services \
  --values "$chart_dir/profiles/admin.yaml" \
  --set 'profile.enabled=true' \
  --set 'profile.telegram.allowedUserIds[0]=123456789' \
  --set 'profile.telegram.adminUserIds[0]=123456789' \
  --set 'browser.enabled=true' \
  --set 'browser.allowedHosts=browser.internal' \
  --set 'browser.mcpUrl=http://browser.internal/mcp' \
  --set 'browser.proxyUrl=http://proxy.internal' \
  --set 'knowledgeBase.enabled=true' \
  --set 'knowledgeBase.mcpUrl=http://gateway.internal/knowledge/mcp' \
  --set 'credentialGateway.enabled=true' \
  --set 'credentialGateway.image.digest=sha256:0000000000000000000000000000000000000000000000000000000000000000' \
  --set 'credentialGateway.wikiSecretName=hermes-admin-knowledge' \
  --set 'credentialGateway.approvalSecretName=hermes-admin-approval' \
  --set 'credentialGateway.imagePullSecretName=hermes-admin-gateway-registry' \
  --set 'credentialGateway.wikiAllowedPrefixes[0]=sebe' \
  --set 'credentialGateway.wikiAllowedPrefixes[1]=shared' \
  --set 'credentialGateway.wikiGraphqlUrl=http://wiki.internal/graphql' \
  >"$admin_rendered"

# YAML parsers can load an unquoted Telegram ID as a float64. The chart must
# preserve its integer representation instead of rendering scientific notation.
helm template hermes-admin "$chart_dir" --namespace services \
  --values "$chart_dir/profiles/admin.yaml" \
  --set-json 'profile.telegram.allowedUserIds=[1234567890.0]' \
  --set-json 'profile.telegram.adminUserIds=[1234567890.0]' \
  >"$numeric_ids"
grep -Fq -- '- "1234567890"' "$numeric_ids"

helm template hermes-rina "$chart_dir" --namespace services \
  --values "$chart_dir/profiles/rina.yaml" \
  --set 'profile.enabled=true' \
  --set 'profile.telegram.allowedUserIds[0]=222222222' \
  --set 'profile.telegram.allowedUserIds[1]=123456789' \
  --set 'profile.telegram.adminUserIds[0]=123456789' \
  --set 'browser.enabled=true' \
  --set 'browser.allowedHosts=browser.internal' \
  --set 'browser.mcpUrl=http://browser.internal/mcp' \
  --set 'browser.proxyUrl=http://proxy.internal' \
  --set 'knowledgeBase.enabled=true' \
  --set 'knowledgeBase.mcpUrl=http://gateway.internal/knowledge/mcp' \
  --set 'credentialGateway.enabled=true' \
  --set 'credentialGateway.image.digest=sha256:0000000000000000000000000000000000000000000000000000000000000000' \
  --set 'credentialGateway.wikiSecretName=hermes-rina-knowledge' \
  --set 'credentialGateway.approvalSecretName=hermes-rina-approval' \
  --set 'credentialGateway.imagePullSecretName=hermes-rina-gateway-registry' \
  --set 'credentialGateway.wikiAllowedPrefixes[0]=rina' \
  --set 'credentialGateway.wikiAllowedPrefixes[1]=shared' \
  --set 'credentialGateway.wikiGraphqlUrl=http://wiki.internal/graphql' \
  >"$rina_rendered"

cat "$admin_rendered" "$rina_rendered" >"$rendered"

for forbidden in 'resources: \["secrets"\]' 'pods/log' 'verbs: \["create"' 'verbs: \["update"' 'verbs: \["patch"' 'verbs: \["delete"'; do
  if grep -Eq "$forbidden" "$rendered"; then
    echo "forbidden RBAC capability found: $forbidden" >&2
    exit 1
  fi
done

grep -Fq 'namespace: rina-company' "$rendered"
grep -Fq 'trust: full' "$rendered"
grep -Fq '_config_version: 39' "$rendered"
grep -Fq 'checksum/hermes-config:' "$rendered"
grep -Fq 'checksum/hermes-agent-profile:' "$rendered"
grep -Fq 'The Wiki.js knowledge base is the canonical durable knowledge store.' "$rendered"
grep -Fq 'url: "http://gateway.internal/knowledge/mcp"' "$rendered"
grep -Fq 'only `sebe/**` and `shared/**`' "$admin_rendered"
grep -Fq 'only `rina/**` and `shared/**`' "$rina_rendered"
grep -Fq 'group_allow_from: []' "$rendered"
grep -Fq 'name: hermes-admin-environment' "$rendered"
grep -Fq 'url: ${BROWSER_MCP_URL}' "$rendered"
grep -Fq 'name: hermes-admin-runtime' "$admin_rendered"
grep -Fq 'name: hermes-rina-runtime' "$rina_rendered"
grep -Fq 'name: hermes-admin-knowledge' "$admin_rendered"
grep -Fq 'name: hermes-admin-approval' "$admin_rendered"
grep -Fq 'name: hermes-admin-gateway-registry' "$admin_rendered"
grep -Fq 'ghcr.io/seungbemi/hermes-approval-plugin' "$admin_rendered"
grep -Fq 'sha256:37d887d798dbffda2a44ab32779aacc1afdd0378e064cacae12815c94bd10eef' "$admin_rendered"
if grep -Fq 'kind: ConfigMap' "$admin_rendered" && grep -Fq 'name: hermes-admin-approval-plugin' "$admin_rendered"; then
  echo "approval plugin must be installed from its pinned image, not duplicated in a ConfigMap" >&2
  exit 1
fi
grep -Fq -- '--proxy-server=http://proxy.internal' "$admin_rendered"
grep -Fq 'port: 8081' "$admin_rendered"
if grep -Fq 'MEMORY_REPOSITORY' "$rendered"; then
  echo "legacy Git memory configuration found" >&2
  exit 1
fi
grep -Fq -- '--allowed-hosts=browser.internal' "$admin_rendered"
grep -Fq 'cidr: "10.96.0.1/32"' "$admin_rendered"
grep -Fq 'hermes-profile: admin' "$admin_rendered"
grep -Fq 'hermes-profile: rina' "$rina_rendered"

if [ "$(grep -c '^kind: ServiceAccount$' "$admin_rendered")" -ne 1 ]; then
  echo "admin release must render exactly one ServiceAccount" >&2
  exit 1
fi

if grep -Eq '^[[:space:]]+cidr: (10\.0\.0\.0/8|172\.16\.0\.0/12|192\.168\.0\.0/16)$' "$rendered"; then
  echo "broad private-network egress found in public chart rendering" >&2
  exit 1
fi

for browser_action in browser_click browser_fill_form browser_file_upload browser_type browser_run_code_unsafe; do
  if grep -Fq -- "- $browser_action" "$rendered"; then
    echo "direct browser action tool found: $browser_action" >&2
    exit 1
  fi
done

echo "Hermes chart policy checks passed"
