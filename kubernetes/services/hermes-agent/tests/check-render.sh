#!/usr/bin/env bash
set -euo pipefail

chart_dir="$(cd "$(dirname "$0")/.." && pwd)"
rendered="$(mktemp)"
admin_rendered="$(mktemp)"
rina_rendered="$(mktemp)"
invalid="$(mktemp)"
disabled="$(mktemp)"
numeric_ids="$(mktemp)"
gateway_only="$(mktemp)"
dashboard_rendered="$(mktemp)"
oidc_dashboard_rendered="$(mktemp)"
rina_delegation_rendered="$(mktemp)"
# Distinct fixed digests verify value propagation without coupling this test to
# whichever release digests are currently pinned in values.yaml.
test_plugin_digest="sha256:1111111111111111111111111111111111111111111111111111111111111111"
test_gateway_digest="sha256:2222222222222222222222222222222222222222222222222222222222222222"
trap 'rm -f -- "$rendered" "$admin_rendered" "$rina_rendered" "$invalid" "$disabled" "$numeric_ids" "$gateway_only" "$dashboard_rendered" "$oidc_dashboard_rendered" "$rina_delegation_rendered"' EXIT INT TERM

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
  --set 'hermes.image.tag=v0.0.0' >"$invalid" 2>&1; then
  echo "Hermes rendered with an image tag different from Chart.appVersion" >&2
  exit 1
fi
grep -Fq 'hermes.image.tag must equal Chart.appVersion' "$invalid"

if helm template hermes "$chart_dir" \
  --set 'profile.enabled=true' \
  --set 'profile.name=admin' \
  --set 'profile.kubernetes.scope=cluster' \
  --set 'profile.runtimeSecretName=hermes-admin-runtime' \
  --set 'profile.telegram.allowedUserIds[0]=123456789' \
  --set 'profile.telegram.adminUserIds[0]=123456789' \
  --set 'hermes.image.digest=latest' >"$invalid" 2>&1; then
  echo "Hermes rendered without an immutable image digest" >&2
  exit 1
fi
grep -Fq 'hermes.image.digest must be an immutable sha256 digest' "$invalid"

if helm template hermes "$chart_dir" \
  --set 'profile.enabled=true' \
  --set 'profile.name=admin' \
  --set 'profile.kubernetes.scope=cluster' \
  --set 'profile.runtimeSecretName=hermes-admin-runtime' \
  --set 'profile.telegram.allowedUserIds[0]=123456789' \
  --set 'profile.telegram.adminUserIds[0]=123456789' \
  --set 'credentialGateway.enabled=true' \
  --set "approvalPlugin.image.digest=$test_plugin_digest" \
  --set "credentialGateway.image.digest=$test_gateway_digest" \
  --set 'credentialGateway.wikiSecretName=hermes-admin-knowledge' \
  --set 'credentialGateway.approvalSecretName=hermes-admin-approval' \
  --set 'credentialGateway.imagePullSecretName=hermes-admin-gateway-registry' \
  --set 'credentialGateway.wikiGraphqlUrl=http://wiki.internal/graphql' \
  --set 'credentialGateway.wikiAuthorization.memberId=sebe' \
  --set 'credentialGateway.wikiAuthorization.allowedOperations[0]=get' \
  --set 'codexDelegation.credentialsSecretName=hermes-admin-codex' \
  --set 'codexDelegation.enabled=true' >"$invalid" 2>&1; then
  echo "Codex delegation rendered without its lifecycle configuration" >&2
  exit 1
fi
grep -Fq 'codexDelegation.authorization.requester is required' "$invalid"

if helm template hermes "$chart_dir" \
  --set 'profile.enabled=true' \
  --set 'profile.name=admin' \
  --set 'profile.kubernetes.scope=cluster' \
  --set 'profile.runtimeSecretName=hermes-admin-runtime' \
  --set 'profile.telegram.allowedUserIds[0]=123456789' \
  --set 'profile.telegram.adminUserIds[0]=123456789' \
  --set 'dashboard.enabled=true' \
  --set 'dashboard.ingress.enabled=true' \
  --set 'dashboard.ingress.public=true' \
  --set 'dashboard.auth.provider=basic' \
  --set 'dashboard.auth.secretName=hermes-admin-dashboard-auth' \
  --set 'dashboard.publicUrl=https://hermes.example.com' >"$invalid" 2>&1; then
  echo "public dashboard rendered without an approved auth provider" >&2
  exit 1
fi
grep -Fq 'public dashboard ingress requires nous or oidc' "$invalid"

helm template hermes-dashboard-local "$chart_dir" --namespace services \
  --values "$chart_dir/profiles/admin.yaml" \
  --set 'profile.telegram.allowedUserIds[0]=123456789' \
  --set 'profile.telegram.adminUserIds[0]=123456789' \
  --set 'dashboard.enabled=true' \
  --set 'dashboard.auth.provider=basic' \
  --set 'dashboard.auth.secretName=hermes-admin-dashboard-auth' >"$dashboard_rendered"
grep -Fq 'name: HERMES_DASHBOARD_BASIC_AUTH_USERNAME' "$dashboard_rendered"
grep -A1 -F 'name: HERMES_HOME' "$dashboard_rendered" | grep -Fq 'value: /opt/data'
grep -A1 -F 'name: GATEWAY_HEALTH_URL' "$dashboard_rendered" | grep -Fq 'value: http://127.0.0.1:8642'
awk '
  /name: dashboard$/ { in_dashboard = 1 }
  in_dashboard && /mountPath: \/opt\/data$/ { mounted = 1 }
  in_dashboard && /name: bootstrap-config$/ { exit }
  END { exit !mounted }
' "$dashboard_rendered"
grep -Fq 'name: HERMES_DASHBOARD_BASIC_AUTH_PASSWORD' "$dashboard_rendered"
grep -Fq 'name: HERMES_DASHBOARD_BASIC_AUTH_SECRET' "$dashboard_rendered"
grep -Fq 'hermes.nousresearch.com/gateway-owner: hermes-container' "$dashboard_rendered"
grep -Fq 'hermes.nousresearch.com/dashboard-role: administration-observer' "$dashboard_rendered"
if [ "$(grep -Fc 'mountPath: /opt/data/config.yaml' "$dashboard_rendered")" -ne 1 ]; then
  echo "dashboard must receive exactly one GitOps-owned config.yaml mount" >&2
  exit 1
fi
grep -B3 -A3 -F 'mountPath: /opt/data/config.yaml' "$dashboard_rendered" | grep -Fq 'readOnly: true'
grep -B3 -A3 -F 'mountPath: /opt/data/SOUL.md' "$dashboard_rendered" | grep -Fq 'readOnly: true'
if grep -Fq 'kind: IngressRoute' "$dashboard_rendered"; then
  echo "local basic-auth dashboard rendered a public ingress" >&2
  exit 1
fi

helm template hermes-dashboard "$chart_dir" --namespace services \
  --values "$chart_dir/profiles/admin.yaml" \
  --set 'profile.telegram.allowedUserIds[0]=123456789' \
  --set 'profile.telegram.adminUserIds[0]=123456789' \
  --set 'dashboard.enabled=true' \
  --set 'dashboard.ingress.enabled=true' \
  --set 'dashboard.ingress.create=true' \
  --set 'dashboard.ingress.public=true' \
  --set 'dashboard.auth.provider=nous' \
  --set 'dashboard.auth.secretName=hermes-admin-dashboard-auth' \
  --set 'dashboard.publicUrl=https://hermes.example.com' >"$dashboard_rendered"
grep -Fq 'name: HERMES_DASHBOARD_OAUTH_CLIENT_ID' "$dashboard_rendered"
grep -Fq 'name: hermes-admin-dashboard-auth' "$dashboard_rendered"
grep -Fq 'match: Host(`hermes.example.com`)' "$dashboard_rendered"

helm template hermes-dashboard-oidc "$chart_dir" --namespace services \
  --values "$chart_dir/profiles/admin.yaml" \
  --set 'profile.telegram.allowedUserIds[0]=123456789' \
  --set 'profile.telegram.adminUserIds[0]=123456789' \
  --set 'dashboard.enabled=true' \
  --set 'dashboard.ingress.enabled=true' \
  --set 'dashboard.ingress.create=true' \
  --set 'dashboard.ingress.public=true' \
  --set 'dashboard.auth.provider=oidc' \
  --set 'dashboard.auth.secretName=hermes-admin-dashboard-oidc' \
  --set 'dashboard.publicUrl=https://hermes.example.com' >"$oidc_dashboard_rendered"
for name in HERMES_DASHBOARD_OIDC_ISSUER HERMES_DASHBOARD_OIDC_CLIENT_ID HERMES_DASHBOARD_OIDC_SCOPES HERMES_DASHBOARD_OIDC_CLIENT_SECRET; do
  grep -Fq "name: $name" "$oidc_dashboard_rendered"
done
if [ "$(grep -Fc 'optional: true' "$oidc_dashboard_rendered")" -lt 2 ]; then
  echo "optional OIDC scopes and client secret must not block public-client deployments" >&2
  exit 1
fi

if helm template hermes "$chart_dir" \
  --set 'profile.enabled=true' \
  --set 'profile.name=admin' \
  --set 'profile.kubernetes.scope=cluster' \
  --set 'profile.runtimeSecretName=hermes-admin-runtime' \
  --set 'profile.telegram.allowedUserIds[0]=123456789' \
  --set 'profile.telegram.adminUserIds[0]=123456789' \
  --set 'credentialGateway.enabled=true' \
  --set "approvalPlugin.image.digest=$test_plugin_digest" \
  --set "credentialGateway.image.digest=$test_gateway_digest" \
  --set 'credentialGateway.wikiSecretName=hermes-admin-knowledge' \
  --set 'credentialGateway.approvalSecretName=hermes-admin-approval' \
  --set 'credentialGateway.imagePullSecretName=hermes-admin-gateway-registry' \
  --set 'credentialGateway.wikiGraphqlUrl=http://wiki.internal/graphql' \
  --set 'credentialGateway.wikiAuthorization.memberId=sebe' \
  --set 'credentialGateway.wikiAuthorization.allowedOperations[0]=get' \
  --set 'configHelpers.enabled=true' \
  --set 'configHelpers.credentialsSecretName=hermes-admin-config-helpers' >"$invalid" 2>&1; then
  echo "configuration helpers rendered without target authorization" >&2
  exit 1
fi
grep -Fq 'configHelpers.configuration.targets must not be empty' "$invalid"

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

helm template hermes-gateway-only "$chart_dir" \
  --values "$chart_dir/profiles/admin.yaml" \
  --set 'profile.telegram.allowedUserIds[0]=123456789' \
  --set 'profile.telegram.adminUserIds[0]=123456789' \
  --set 'credentialGateway.enabled=true' \
  --set 'credentialGateway.wikiSecretName=hermes-admin-knowledge' \
  --set 'credentialGateway.approvalSecretName=hermes-admin-approval' \
  --set 'credentialGateway.imagePullSecretName=hermes-admin-gateway-registry' \
  --set 'credentialGateway.wikiGraphqlUrl=http://wiki.internal/graphql' \
  >"$gateway_only"
if grep -Fq 'codex-runner-credentials' "$gateway_only"; then
  echo 'disabled Codex credentials rendered into the gateway pod' >&2
  exit 1
fi
if grep -Fq 'config-helper-credentials' "$gateway_only"; then
  echo 'disabled configuration-helper credentials rendered into the gateway pod' >&2
  exit 1
fi
# This render intentionally keeps the chart defaults, independently checking
# that deployable production values remain immutable SHA-256 references.
if ! grep -Eq 'image: ghcr\.io/seungbemi/hermes-policy-gateway:sha-[0-9a-f]{40}@sha256:[0-9a-f]{64}$' "$gateway_only"; then
  echo 'default policy-gateway image must be pinned by a valid sha256 digest' >&2
  exit 1
fi
if ! grep -Eq 'image: ghcr\.io/seungbemi/hermes-approval-plugin:sha-[0-9a-f]{40}@sha256:[0-9a-f]{64}$' "$gateway_only"; then
  echo 'default approval-plugin image must be pinned by a valid sha256 digest' >&2
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
  --set "approvalPlugin.image.digest=$test_plugin_digest" \
  --set "credentialGateway.image.digest=$test_gateway_digest" \
  --set 'credentialGateway.wikiSecretName=hermes-admin-knowledge' \
  --set 'credentialGateway.approvalSecretName=hermes-admin-approval' \
  --set 'credentialGateway.imagePullSecretName=hermes-admin-gateway-registry' \
  --set 'credentialGateway.wikiGraphqlUrl=http://wiki.internal/graphql' \
  --set 'codexDelegation.enabled=true' \
  --set 'codexDelegation.credentialsSecretName=hermes-admin-codex' \
  --set 'codexDelegation.authorization.requester=telegram:123456789' \
  --set 'codexDelegation.authorization.coder.url=https://coder.internal' \
  --set 'codexDelegation.authorization.coder.user=admin' \
  --set 'codexDelegation.coderEndpointCidrs[0]=10.20.30.40/32' \
  --set 'kubernetes.apiEndpointCidrs[0]=172.20.0.108/32' \
  --set 'kubernetes.apiEndpointPort=6443' \
  --set 'codexDelegation.authorization.targets[0].name=analysis' \
  --set 'codexDelegation.authorization.targets[0].template=hermes-codex-runner' \
  --set 'codexDelegation.authorization.targets[0].workspace=hermes' \
  --set 'codexDelegation.authorization.targets[0].runnerTokenFile=/var/run/hermes-codex/runner-token' \
  --set 'codexDelegation.authorization.targets[0].runnerCaFile=/var/run/hermes-codex/runner-ca.crt' \
  --set 'codexDelegation.authorization.targets[0].modes[0]=analysis' \
  --set 'configHelpers.enabled=true' \
  --set 'configHelpers.credentialsSecretName=hermes-admin-config-helpers' \
  --set 'configHelpers.endpointCidrs[0]=10.20.30.50/32' \
  --set 'configHelpers.configuration.targets[0].name=home-assistant' \
  --set 'configHelpers.configuration.targets[0].service=home-assistant' \
  --set 'configHelpers.configuration.targets[0].url=https://home-assistant-config-helper.services.svc:8444' \
  --set 'configHelpers.configuration.targets[0].tokenFile=/var/run/hermes-config-helpers/home-assistant-token' \
  --set 'configHelpers.configuration.targets[0].caFile=/var/run/hermes-config-helpers/home-assistant-ca.crt' \
  --set 'configHelpers.configuration.targets[0].allowedPaths[0]=configuration.yaml' \
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
  --set "approvalPlugin.image.digest=$test_plugin_digest" \
  --set "credentialGateway.image.digest=$test_gateway_digest" \
  --set 'credentialGateway.wikiSecretName=hermes-rina-knowledge' \
  --set 'credentialGateway.approvalSecretName=hermes-rina-approval' \
  --set 'credentialGateway.imagePullSecretName=hermes-rina-gateway-registry' \
  --set 'credentialGateway.wikiGraphqlUrl=http://wiki.internal/graphql' \
  >"$rina_rendered"

helm template hermes-rina-delegation "$chart_dir" --namespace services \
  --values "$chart_dir/profiles/rina.yaml" \
  --values "$chart_dir/tests/rina-delegation-values.yaml" \
  --set "approvalPlugin.image.digest=$test_plugin_digest" \
  --set "credentialGateway.image.digest=$test_gateway_digest" \
  >"$rina_delegation_rendered"
grep -Fq '"name":"rina-company"' "$rina_delegation_rendered"
grep -Fq '"name":"rina-company-deploy"' "$rina_delegation_rendered"
grep -Fq '"allowedPaths":["kubernetes/services/rina-company/release-version.txt"]' "$rina_delegation_rendered"
grep -Fq '"requester":"telegram:222222222"' "$rina_delegation_rendered"
grep -Fq 'members/rina/assistant/inbox/' "$rina_delegation_rendered"
if grep -Fq 'members/sebe/assistant/inbox/' "$rina_delegation_rendered"; then
  echo 'Rina profile rendered Sebe private inbox policy' >&2
  exit 1
fi

if helm template hermes-rina-delegation "$chart_dir" --namespace services \
  --values "$chart_dir/profiles/rina.yaml" \
  --values "$chart_dir/tests/rina-delegation-values.yaml" \
  --set "approvalPlugin.image.digest=$test_plugin_digest" \
  --set "credentialGateway.image.digest=$test_gateway_digest" \
  --set 'codexDelegation.authorization.targets[1].allowedPaths[0]=kubernetes' \
  >"$invalid" 2>&1; then
  echo 'Rina delegation rendered with broad GitOps access' >&2
  exit 1
fi
grep -Fq 'Rina deploy target must be restricted to the Rina Company release version file' "$invalid"

if helm template hermes-rina-delegation "$chart_dir" --namespace services \
  --values "$chart_dir/profiles/rina.yaml" \
  --values "$chart_dir/tests/rina-delegation-values.yaml" \
  --set "approvalPlugin.image.digest=$test_plugin_digest" \
  --set "credentialGateway.image.digest=$test_gateway_digest" \
  --set 'codexDelegation.authorization.requester=telegram:999999999' \
  >"$invalid" 2>&1; then
  echo 'Rina delegation rendered for an unrelated Telegram identity' >&2
  exit 1
fi
grep -Fq 'Rina Codex requester must match an allowed Telegram user ID' "$invalid"

cat "$admin_rendered" "$rina_rendered" >"$rendered"

for forbidden in 'resources: \["secrets"\]' 'verbs: \["create"' 'verbs: \["update"' 'verbs: \["patch"' 'verbs: \["delete"'; do
  if grep -Eq "$forbidden" "$rendered"; then
    echo "forbidden RBAC capability found: $forbidden" >&2
    exit 1
  fi
done

if [ "$(grep -Fc 'resources: ["pods/log"]' "$admin_rendered")" -ne 1 ] || grep -Fq 'resources: ["pods/log"]' "$rina_rendered"; then
  echo "pod log access must be granted only to the admin profile" >&2
  exit 1
fi
grep -Fq 'name: hermes-codex-runner-hermes' "$admin_rendered"
grep -Fq 'name: hermes-codex-runner-hermes-kubeconfig' "$admin_rendered"
grep -Fq 'name: hermes-admin-codex-runner-kubernetes-api' "$admin_rendered"
grep -Fq 'app.kubernetes.io/name: codex-runner' "$admin_rendered"
grep -Fq 'app.kubernetes.io/part-of: hermes-delegation' "$admin_rendered"
grep -Fq 'cidr: "172.20.0.108/32"' "$admin_rendered"
grep -Fq 'port: 6443' "$admin_rendered"
if grep -Fq 'name: hermes-rina-codex-runner-kubernetes-api' "$rina_rendered"; then
  echo 'Codex runner API policy must render only when delegation is enabled' >&2
  exit 1
fi
grep -Fq 'automountServiceAccountToken: false' "$admin_rendered"
grep -Fq 'tokenFile: /var/run/secrets/kubernetes.io/serviceaccount/token' "$admin_rendered"
grep -Fq 'alert: HermesCoderTokenExpiring' "$admin_rendered"
grep -Fq 'expr: vector(time()) > 1794831400' "$admin_rendered"
grep -Fq 'alert: HermesRetentionCleanupMissedSchedule' "$admin_rendered"
grep -Fq 'cronjob="hermes-admin-retention"' "$admin_rendered"
grep -Fq 'kube_cronjob_next_schedule_time{namespace="services"' "$admin_rendered"
grep -Fq 'kube_cronjob_spec_suspend{namespace="services"' "$admin_rendered"
grep -Fq ') > 3600 and on (namespace, cronjob)' "$admin_rendered"
grep -Fq 'for: 15m' "$admin_rendered"
if grep -Fq 'alert: HermesCoderTokenExpiring' "$rina_rendered"; then
  echo 'Coder token expiry alert must be rendered only for a configured delegation profile' >&2
  exit 1
fi
if grep -Fq 'alert: HermesRetentionCleanupMissedSchedule' "$rina_rendered"; then
  echo 'retention missed-schedule alert must render only with delegation retention' >&2
  exit 1
fi

grep -Fq 'namespace: rina-company' "$rendered"
grep -Fq 'trust: full' "$rendered"
grep -Fq '_config_version: 51' "$rendered"
grep -Fq 'checksum/hermes-config:' "$rendered"
grep -Fq 'checksum/hermes-agent-profile:' "$rendered"
grep -Fq 'The Wiki.js knowledge base is the canonical durable knowledge store.' "$rendered"
grep -Fq 'url: "http://gateway.internal/knowledge/mcp"' "$rendered"
grep -Fq '`members/sebe` and its descendants' "$admin_rendered"
grep -Fq '`members/rina` and its descendants' "$rina_rendered"
grep -Fq 'name: WIKI_AUTHORIZATION' "$admin_rendered"
grep -Fq 'allowedOperations' "$admin_rendered"
grep -Fq 'group_allow_from: []' "$rendered"
grep -Fq 'rich_messages: true' "$rendered"
if grep -Fq 'HERMES_GATEWAY_NO_SUPERVISE' "$rendered"; then
  echo 'Hermes must use the image-supported s6 gateway supervision path' >&2
  exit 1
fi
if [ "$(grep -Fc 'hermes_cli\.main.*gateway run --replace$' "$admin_rendered")" -ne 2 ]; then
  echo 'Hermes liveness and readiness probes must match the v0.22.5 s6/Python shim' >&2
  exit 1
fi
grep -Fq 'name: hermes-admin-environment' "$rendered"
grep -Fq 'url: ${BROWSER_MCP_URL}' "$rendered"
grep -Fq 'name: hermes-admin-runtime' "$admin_rendered"
grep -Fq 'name: hermes-rina-runtime' "$rina_rendered"
grep -Fq 'name: hermes-admin-knowledge' "$admin_rendered"
grep -Fq 'name: hermes-admin-approval' "$admin_rendered"
grep -Fq 'key: DATABASE_URL' "$admin_rendered"
grep -Fq 'name: CODEX_DELEGATION' "$admin_rendered"
grep -Fq 'runnerTokenFile' "$admin_rendered"
grep -Fq 'sessionTokenFile' "$admin_rendered"
grep -Fq 'workspaceStartTimeoutSeconds' "$admin_rendered"
grep -Fq 'workspaceTtlSeconds' "$admin_rendered"
grep -Fq 'secretName: hermes-admin-codex' "$admin_rendered"
grep -Fq 'mountPath: /var/run/hermes-codex' "$admin_rendered"
grep -Fq 'url: "http://127.0.0.1:8090/delegation/mcp"' "$admin_rendered"
grep -Fq -- '- mcp-codex-delegation' "$admin_rendered"
grep -Fq 'kubernetes.io/metadata.name: "coder"' "$admin_rendered"
grep -Fq 'cidr: "10.20.30.40/32"' "$admin_rendered"
grep -Fq 'app.kubernetes.io/name: codex-runner' "$admin_rendered"
grep -Fq 'kubernetes.io/metadata.name: ingress' "$admin_rendered"
grep -Fq 'app.kubernetes.io/name: traefik' "$admin_rendered"
grep -Fq 'port: 8443' "$admin_rendered"
grep -Fq 'name: CONFIG_HELPERS' "$admin_rendered"
grep -Fq 'home-assistant-config-helper.services.svc:8444' "$admin_rendered"
grep -Fq 'tokenFile' "$admin_rendered"
grep -Fq 'secretName: hermes-admin-config-helpers' "$admin_rendered"
grep -Fq 'mountPath: /var/run/hermes-config-helpers' "$admin_rendered"
grep -Fq 'url: "http://127.0.0.1:8090/config-helper/mcp"' "$admin_rendered"
grep -Fq -- '- mcp-config-helpers' "$admin_rendered"
grep -Fq 'values: [home-assistant, frigate]' "$admin_rendered"
grep -Fq 'cidr: "10.20.30.50/32"' "$admin_rendered"
grep -Fq 'Configuration evidence policy:' "$admin_rendered"
grep -Fq 'path: /livez' "$admin_rendered"
grep -Fq 'path: /readyz' "$admin_rendered"
grep -Fq 'port: 8090' "$admin_rendered"
grep -Fq 'containerPort: 9090' "$admin_rendered"
grep -Fq -- '- containerPort: 9090' "$admin_rendered"
grep -Fq 'kind: PodMonitor' "$admin_rendered"
grep -Fq 'app.kubernetes.io/name: prometheus' "$admin_rendered"
grep -Fq 'HermesTelemetryDrops' "$admin_rendered"
grep -Fq 'HermesCoderAuthenticationRequired' "$admin_rendered"
grep -Fq 'state="needs_login"' "$admin_rendered"
grep -Fq 'HermesCoderQuotaWaitProlonged' "$admin_rendered"
grep -Fq 'state="waiting_for_quota"' "$admin_rendered"
grep -Fq 'HermesTelegramOutboxStalled' "$admin_rendered"
grep -Fq 'HermesTelegramDeliveryFailure' "$admin_rendered"
grep -Fq 'HermesTelegramDeliverySLOBreach' "$admin_rendered"
grep -Fq 'HermesLLMDailyBudgetExceeded' "$admin_rendered"
grep -Fq 'HermesLLMMonthlyBudgetExceeded' "$admin_rendered"
grep -Fq 'hermes_llm_cost_usd_total{profile="admin"}[24h])) > 2' "$admin_rendered"
grep -Fq 'hermes_llm_cost_usd_total{profile="admin"}[30d])) > 15' "$admin_rendered"
if grep -Fq 'model_drift_guard:' "$admin_rendered"; then
  echo 'removed Hermes cron.model_drift_guard key must not be rendered' >&2
  exit 1
fi
if [ "$(grep -Fc 'image: nousresearch/hermes-agent:v0.22.5@sha256:9c5561579f3ffdf333401797094ac3a743738d6c25d40f4331c7bf77b694238d' "$admin_rendered")" -ne 3 ]; then
  echo 'version check, bootstrap, and gateway must use the same pinned Hermes image' >&2
  exit 1
fi
if [ "$(grep -Fc 'image: nousresearch/hermes-agent:v0.22.5@sha256:9c5561579f3ffdf333401797094ac3a743738d6c25d40f4331c7bf77b694238d' "$dashboard_rendered")" -ne 4 ]; then
  echo 'enabled dashboard must use the same pinned Hermes image as all runtime containers' >&2
  exit 1
fi
grep -Fq 'name: EXPECTED_HERMES_VERSION' "$admin_rendered"
grep -Fq 'value: v0.22.5' "$admin_rendered"
grep -Fq '/opt/hermes/.venv/bin/hermes --version' "$admin_rendered"
grep -Fq 'default: "openrouter/auto"' "$admin_rendered"
grep -A2 -F 'fallback_model:' "$admin_rendered" | grep -Fq 'model: "openai/gpt-5.6-luna"'
if grep -Fq 'sort: price' "$admin_rendered"; then
  echo 'explicit price sorting disables reliability-aware provider routing' >&2
  exit 1
fi
grep -Fq 'name: HERMES_AUTO_ROUTING_POLICY_ENABLED' "$admin_rendered"
grep -A1 -F 'name: HERMES_AUTO_ROUTING_POLICY_ENABLED' "$admin_rendered" | grep -Fq 'value: "true"'
grep -A1 -F 'name: HERMES_ROUTING_COST_TIER' "$admin_rendered" | grep -Fq 'value: low'
grep -A1 -F 'name: HERMES_ROUTING_ALLOWED_MODELS' "$admin_rendered" | grep -Fq 'openai/gpt-5.6-luna'
if grep -A1 -F 'name: HERMES_ROUTING_ALLOWED_MODELS' "$admin_rendered" | grep -Fq 'openai/gpt-5.6-luna-pro'; then
  echo 'Luna Pro must require explicit model selection' >&2
  exit 1
fi
grep -A1 -F 'name: HERMES_ROUTING_MAX_PROMPT_USD_PER_MILLION' "$admin_rendered" | grep -Fq 'value: "3"'
grep -A1 -F 'name: HERMES_ROUTING_MAX_COMPLETION_USD_PER_MILLION' "$admin_rendered" | grep -Fq 'value: "15"'
if sed -n '/disabled_toolsets:/,/platform_toolsets:/p' "$admin_rendered" | grep -Fq -- '- cronjob'; then
  echo 'admin rollout must enable the cronjob toolset' >&2
  exit 1
fi
sed -n '/platform_toolsets:/,/approvals:/p' "$admin_rendered" | grep -Fq -- '- cronjob'
sed -n '/platform_toolsets:/,/approvals:/p' "$admin_rendered" | grep -Fq -- '- web'
if sed -n '/disabled_toolsets:/,/platform_toolsets:/p' "$admin_rendered" | grep -Fq -- '- web'; then
  echo 'admin rollout must enable the web toolset' >&2
  exit 1
fi
grep -Fq 'keyless_fallback: true' "$admin_rendered"
grep -Fq 'cache_enabled: true' "$admin_rendered"
grep -Fq 'cache_ttl_minutes: 20' "$admin_rendered"
scheduled_rendered="$(helm template hermes-admin "$chart_dir" --namespace services \
  --values "$chart_dir/profiles/admin.yaml" \
  --set 'profile.telegram.allowedUserIds[0]=123456789' \
  --set 'profile.telegram.adminUserIds[0]=123456789' \
  --set 'scheduling.enabled=true' \
  --set 'model.routing.enabled=true')"
if sed -n '/disabled_toolsets:/,/platform_toolsets:/p' <<<"$scheduled_rendered" | grep -Fq -- '- cronjob'; then
  echo 'enabled scheduler must remove cronjob from disabled toolsets' >&2
  exit 1
fi
grep -Fq 'default: "openrouter/auto"' <<<"$scheduled_rendered"
grep -Fq 'model: "openrouter/auto"' <<<"$scheduled_rendered"
grep -A2 -F 'fallback_model:' <<<"$scheduled_rendered" | grep -Fq 'model: "openai/gpt-5.6-luna"'
sed -n '/platform_toolsets:/,/approvals:/p' <<<"$scheduled_rendered" | grep -Fq -- '- cronjob'
if grep -A1 -F 'name: HERMES_ROUTING_ALLOWED_MODELS' "$admin_rendered" | grep -Fq 'anthropic/claude-sonnet-5'; then
  echo 'premium Sonnet must require explicit model selection' >&2
  exit 1
fi
if helm template hermes-rina "$chart_dir" --namespace services \
  --values "$chart_dir/profiles/rina.yaml" \
  --set 'profile.enabled=true' \
  --set 'profile.telegram.allowedUserIds[0]=222222222' \
  --set 'profile.telegram.adminUserIds[0]=222222222' \
  --set 'scheduling.enabled=true' >/dev/null 2>&1; then
  echo 'scheduler rollout must remain admin-only' >&2
  exit 1
fi
grep -Fq 'name: hermes-admin-gateway-registry' "$admin_rendered"
grep -Fq "image: ghcr.io/seungbemi/hermes-approval-plugin:sha-c8ea719e2d3a9ccb52a9719a7aad7287bd510493@$test_plugin_digest" "$admin_rendered"
grep -Eq "image: ghcr\\.io/seungbemi/hermes-policy-gateway:sha-[0-9a-f]{40}@$test_gateway_digest$" "$admin_rendered"
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
grep -Fq 'kubernetes.io/metadata.name: persistence' "$admin_rendered"
grep -Fq 'app.kubernetes.io/name: postgresql' "$admin_rendered"
grep -Fq 'port: 5432' "$admin_rendered"
grep -Fq 'kind: CronJob' "$admin_rendered"
grep -Fq 'name: hermes-admin-retention' "$admin_rendered"
grep -Fq 'args: ["retention-cleanup"]' "$admin_rendered"
grep -Fq 'concurrencyPolicy: Forbid' "$admin_rendered"
grep -Fq 'startingDeadlineSeconds: 3600' "$admin_rendered"
grep -Fq '"retention":{"deliveredOutboxDays":7,"dryRun":false,"jobDays":30,"proposalDays":7}' "$admin_rendered"
grep -Fq '"queueDomain":"codex-account"' "$admin_rendered"
grep -Fq '"queueMaxActiveJobs":10' "$admin_rendered"
grep -Fq 'name: RUNNER_JOB_ROOT' "$admin_rendered"
grep -Fq 'value: "/workspace/jobs"' "$admin_rendered"
grep -Fq 'server: "diskstation.local"' "$admin_rendered"
grep -Fq 'path: "/volume1/LTS/coder/caffeine/.hermes-codex-runner/hermes/jobs"' "$admin_rendered"
grep -Fq 'mountPath: "/workspace/jobs"' "$admin_rendered"
grep -Fq 'runAsUser: 10000' "$admin_rendered"
grep -Fq 'runAsGroup: 10000' "$admin_rendered"
grep -Fq 'fsGroup: 10000' "$admin_rendered"
if grep -A90 'name: hermes-admin-retention' "$admin_rendered" | grep -Eq '/home/coder|hermes-tools|/runner-state|/workspace/mirrors|/usr/local/go'; then
  echo 'retention CronJob must mount only the isolated jobs export' >&2
  exit 1
fi
if grep -Fq 'name: hermes-rina-retention' "$rina_rendered"; then
  echo 'retention CronJob must render only when delegation is enabled' >&2
  exit 1
fi
grep -Fq 'hermes-profile: admin' "$admin_rendered"
grep -Fq 'hermes-profile: rina' "$rina_rendered"

if [ "$(grep -c '^kind: ServiceAccount$' "$admin_rendered")" -ne 2 ]; then
  echo "admin release must render the Hermes and Codex runner ServiceAccounts" >&2
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
