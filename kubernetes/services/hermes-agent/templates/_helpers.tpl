{{- define "hermes.name" -}}
hermes
{{- end -}}

{{- define "hermes.profileName" -}}
{{ printf "hermes-%s" .Values.profile.name | trunc 63 | trimSuffix "-" }}
{{- end -}}

{{- define "hermes.labels" -}}
app.kubernetes.io/name: hermes-agent
app.kubernetes.io/instance: {{ include "hermes.profileName" . }}
app.kubernetes.io/component: agent
hermes-profile: {{ .Values.profile.name | quote }}
{{- end -}}

{{- define "hermes.telegramId" -}}
{{- if kindIs "float64" . -}}
{{- printf "%.0f" . -}}
{{- else -}}
{{- toString . -}}
{{- end -}}
{{- end -}}

{{- define "hermes.validateProfile" -}}
{{- if ne .Values.hermes.image.tag .Chart.AppVersion -}}
{{- fail "hermes.image.tag must equal Chart.appVersion so bootstrap, gateway, and dashboard report one release" -}}
{{- end -}}
{{- if not (regexMatch "^sha256:[a-f0-9]{64}$" .Values.hermes.image.digest) -}}
{{- fail "hermes.image.digest must be an immutable sha256 digest" -}}
{{- end -}}
{{- if lt (int .Values.hermes.configVersion) 12 -}}
{{- fail "hermes.configVersion must be within Hermes' supported automatic-migration floor" -}}
{{- end -}}
{{- if not (has .Values.profile.name (list "admin" "rina")) -}}
{{- fail "profile.name must be admin or rina when enabled" -}}
{{- end -}}
{{- if and (eq .Values.profile.name "admin") (ne .Values.profile.kubernetes.scope "cluster") -}}
{{- fail "the admin profile requires profile.kubernetes.scope=cluster" -}}
{{- end -}}
{{- if and (eq .Values.profile.name "rina") (ne .Values.profile.kubernetes.scope "rina-company") -}}
{{- fail "the rina profile requires profile.kubernetes.scope=rina-company" -}}
{{- end -}}
{{- if and .Values.scheduling.enabled (ne .Values.profile.name "admin") -}}
{{- fail "scheduling may be enabled only for the admin profile during rollout" -}}
{{- end -}}
{{- if not .Values.profile.runtimeSecretName -}}
{{- fail "profile.runtimeSecretName is required when enabled" -}}
{{- end -}}
{{- if .Values.dashboard.enabled -}}
{{- if ne .Values.profile.name "admin" -}}{{- fail "dashboard may be enabled only for the admin profile" -}}{{- end -}}
{{- if not (has .Values.dashboard.auth.provider (list "basic" "nous" "oidc")) -}}{{- fail "dashboard.auth.provider must be basic, nous, or oidc" -}}{{- end -}}
{{- if not .Values.dashboard.auth.secretName -}}{{- fail "dashboard.auth.secretName is required when the dashboard is enabled" -}}{{- end -}}
{{- if and .Values.dashboard.ingress.enabled .Values.dashboard.ingress.public (eq .Values.dashboard.auth.provider "basic") -}}{{- fail "public dashboard ingress requires nous or oidc; basic auth is local/VPN-only" -}}{{- end -}}
{{- if and .Values.dashboard.ingress.enabled (not (regexMatch "^https://[^/]+/?$" .Values.dashboard.publicUrl)) -}}{{- fail "dashboard.publicUrl must be an origin-only https URL when dashboard ingress is enabled" -}}{{- end -}}
{{- if not .Values.dashboard.ingress.entryPoint -}}{{- fail "dashboard.ingress.entryPoint is required when the dashboard is enabled" -}}{{- end -}}
{{- if not .Values.dashboard.ingress.clusterIssuer -}}{{- fail "dashboard.ingress.clusterIssuer is required when the dashboard is enabled" -}}{{- end -}}
{{- if and .Values.dashboard.observer.enabled (not .Values.credentialGateway.enabled) -}}{{- fail "dashboard observer mode requires the policy gateway" -}}{{- end -}}
{{- if and .Values.dashboard.observer.enabled (eq (int .Values.dashboard.observer.port) (int .Values.dashboard.port)) -}}{{- fail "dashboard observer port must differ from the upstream dashboard port" -}}{{- end -}}
{{- end -}}
{{- if eq (len .Values.profile.telegram.allowedUserIds) 0 -}}
{{- fail "profile.telegram.allowedUserIds must contain numeric Telegram user IDs" -}}
{{- end -}}
{{- if eq (len .Values.profile.telegram.adminUserIds) 0 -}}
{{- fail "profile.telegram.adminUserIds must contain at least one administrator ID" -}}
{{- end -}}
{{- if and .Values.knowledgeBase.enabled (not .Values.credentialGateway.enabled) -}}
{{- fail "knowledgeBase.enabled requires credentialGateway.enabled" -}}
{{- end -}}
{{- if and .Values.knowledgeBase.enabled (not .Values.knowledgeBase.mcpUrl) -}}
{{- fail "knowledgeBase.mcpUrl is required when the knowledge base is enabled" -}}
{{- end -}}
{{- if and .Values.homeAssistant.enabled (not .Values.credentialGateway.enabled) -}}{{- fail "homeAssistant.enabled requires credentialGateway.enabled" -}}{{- end -}}
{{- if and .Values.homeAssistant.enabled (not .Values.homeAssistant.mcpUrl) -}}{{- fail "homeAssistant.mcpUrl is required when enabled" -}}{{- end -}}
{{- if and .Values.homeAssistant.enabled (not .Values.credentialGateway.homeAssistantUrl) -}}{{- fail "credentialGateway.homeAssistantUrl is required when enabled" -}}{{- end -}}
{{- if and .Values.homeAssistant.enabled (not .Values.credentialGateway.homeAssistantSecretName) -}}{{- fail "credentialGateway.homeAssistantSecretName is required when enabled" -}}{{- end -}}
{{- if and .Values.paperless.enabled (not .Values.credentialGateway.enabled) -}}{{- fail "paperless.enabled requires credentialGateway.enabled" -}}{{- end -}}
{{- if and .Values.paperless.enabled (not .Values.paperless.mcpUrl) -}}{{- fail "paperless.mcpUrl is required when enabled" -}}{{- end -}}
{{- if and .Values.paperless.enabled (not .Values.credentialGateway.paperlessUrl) -}}{{- fail "credentialGateway.paperlessUrl is required when enabled" -}}{{- end -}}
{{- if and .Values.paperless.enabled (not .Values.credentialGateway.paperlessPublicUrl) -}}{{- fail "credentialGateway.paperlessPublicUrl is required when enabled" -}}{{- end -}}
{{- if and .Values.paperless.enabled (not .Values.credentialGateway.paperlessSecretName) -}}{{- fail "credentialGateway.paperlessSecretName is required when enabled" -}}{{- end -}}
{{- if .Values.codexDelegation.enabled -}}
{{- if not .Values.credentialGateway.enabled -}}{{- fail "codexDelegation.enabled requires credentialGateway.enabled" -}}{{- end -}}
{{- if not .Values.codexDelegation.mcpUrl -}}{{- fail "codexDelegation.mcpUrl is required when enabled" -}}{{- end -}}
{{- if not .Values.codexDelegation.credentialsSecretName -}}{{- fail "codexDelegation.credentialsSecretName is required when enabled" -}}{{- end -}}
{{- if not .Values.codexDelegation.authorization.requester -}}{{- fail "codexDelegation.authorization.requester is required when enabled" -}}{{- end -}}
{{- if not .Values.codexDelegation.authorization.coder.url -}}{{- fail "codexDelegation.authorization.coder.url is required when enabled" -}}{{- end -}}
{{- if not .Values.codexDelegation.authorization.coder.sessionTokenFile -}}{{- fail "codexDelegation.authorization.coder.sessionTokenFile is required when enabled" -}}{{- end -}}
{{- if not .Values.codexDelegation.authorization.coder.organization -}}{{- fail "codexDelegation.authorization.coder.organization is required when enabled" -}}{{- end -}}
{{- if not .Values.codexDelegation.authorization.coder.user -}}{{- fail "codexDelegation.authorization.coder.user is required when enabled" -}}{{- end -}}
{{- if not .Values.codexDelegation.authorization.coder.runnerNamespace -}}{{- fail "codexDelegation.authorization.coder.runnerNamespace is required when enabled" -}}{{- end -}}
{{- if eq (len .Values.codexDelegation.authorization.targets) 0 -}}{{- fail "codexDelegation.authorization.targets must not be empty when enabled" -}}{{- end -}}
{{- if eq .Values.profile.name "rina" -}}
{{- $requesterAllowed := false -}}
{{- range $userID := .Values.profile.telegram.allowedUserIds -}}
{{- if eq $.Values.codexDelegation.authorization.requester (printf "telegram:%s" (include "hermes.telegramId" $userID)) -}}{{- $requesterAllowed = true -}}{{- end -}}
{{- end -}}
{{- if not $requesterAllowed -}}{{- fail "Rina Codex requester must match an allowed Telegram user ID" -}}{{- end -}}
{{- end -}}
{{- range $target := .Values.codexDelegation.authorization.targets -}}
{{- if has "implementation" $target.modes -}}
{{- if not $.Values.credentialGateway.github.enabled -}}{{- fail "implementation Codex targets require credentialGateway.github.enabled" -}}{{- end -}}
{{- if not $target.repository -}}{{- fail "implementation Codex targets require repository" -}}{{- end -}}
{{- if eq (len $target.allowedPaths) 0 -}}{{- fail "implementation Codex targets require allowedPaths" -}}{{- end -}}
{{- if eq $.Values.profile.name "rina" -}}
{{- if ne $target.approvalPolicy "always" -}}{{- fail "Rina Codex targets require approvalPolicy=always" -}}{{- end -}}
{{- if eq $target.name "rina-company" -}}
{{- if ne $target.repository "seungbemi/rina-company" -}}{{- fail "Rina source target must use seungbemi/rina-company" -}}{{- end -}}
{{- range $path := $target.allowedPaths -}}
{{- if not (has $path (list ".github" ".gitignore" "Dockerfile" "README.md" "cmd" "go.mod" "go.sum" "internal")) -}}{{- fail "Rina source target contains an unauthorized path" -}}{{- end -}}
{{- end -}}
{{- range $operation := $target.allowedOperations -}}
{{- if not (has $operation (list "edit" "test" "create_pr" "auto_merge" "install_tool")) -}}{{- fail "Rina source target contains an unauthorized operation" -}}{{- end -}}
{{- end -}}
{{- else if eq $target.name "rina-company-deploy" -}}
{{- if ne $target.repository "seungbemi/gitops" -}}{{- fail "Rina deploy target must use seungbemi/gitops" -}}{{- end -}}
{{- if or (ne (len $target.allowedPaths) 1) (ne (index $target.allowedPaths 0) "kubernetes/services/rina-company/release-version.txt") -}}{{- fail "Rina deploy target must be restricted to the Rina Company release version file" -}}{{- end -}}
{{- range $operation := $target.allowedOperations -}}
{{- if not (has $operation (list "edit" "test" "create_pr" "auto_merge" "verify_deployment")) -}}{{- fail "Rina deploy target contains an unauthorized operation" -}}{{- end -}}
{{- end -}}
{{- else -}}
{{- fail "Rina Codex implementation targets must be rina-company or rina-company-deploy" -}}
{{- end -}}
{{- end -}}
{{- end -}}
{{- end -}}
{{- end -}}
{{- if .Values.credentialGateway.github.enabled -}}
{{- if not .Values.credentialGateway.enabled -}}{{- fail "credentialGateway.github.enabled requires credentialGateway.enabled" -}}{{- end -}}
{{- if not .Values.credentialGateway.github.secretName -}}{{- fail "credentialGateway.github.secretName is required when direct Codex GitHub access is enabled" -}}{{- end -}}
{{- end -}}
{{- if .Values.configHelpers.enabled -}}
{{- if ne .Values.profile.name "admin" -}}{{- fail "configHelpers may be enabled only for the admin profile during rollout" -}}{{- end -}}
{{- if not .Values.credentialGateway.enabled -}}{{- fail "configHelpers.enabled requires credentialGateway.enabled" -}}{{- end -}}
{{- if not .Values.configHelpers.mcpUrl -}}{{- fail "configHelpers.mcpUrl is required when enabled" -}}{{- end -}}
{{- if not .Values.configHelpers.credentialsSecretName -}}{{- fail "configHelpers.credentialsSecretName is required when enabled" -}}{{- end -}}
{{- if eq (len .Values.configHelpers.configuration.targets) 0 -}}{{- fail "configHelpers.configuration.targets must not be empty when enabled" -}}{{- end -}}
{{- range $target := .Values.configHelpers.configuration.targets -}}
{{- if not $target.name -}}{{- fail "each configHelpers target requires name" -}}{{- end -}}
{{- if not (has $target.service (list "home-assistant" "frigate")) -}}{{- fail "each configHelpers target service must be home-assistant or frigate" -}}{{- end -}}
{{- if not (regexMatch "^https://" $target.url) -}}{{- fail "each configHelpers target requires an https url" -}}{{- end -}}
{{- if not (regexMatch "^/" $target.tokenFile) -}}{{- fail "each configHelpers target requires an absolute tokenFile" -}}{{- end -}}
{{- if not (regexMatch "^/" $target.caFile) -}}{{- fail "each configHelpers target requires an absolute caFile" -}}{{- end -}}
{{- if eq (len $target.allowedPaths) 0 -}}{{- fail "each configHelpers target requires allowedPaths" -}}{{- end -}}
{{- end -}}
{{- end -}}
{{- if and .Values.browser.enabled (not .Values.credentialGateway.enabled) -}}
{{- fail "browser.enabled requires credentialGateway.enabled" -}}
{{- end -}}
{{- if .Values.credentialGateway.enabled -}}
{{- if not (regexMatch "^sha256:[a-f0-9]{64}$" .Values.approvalPlugin.image.digest) -}}
{{- fail "approvalPlugin.image.digest must be an immutable sha256 digest when the gateway is enabled" -}}
{{- end -}}
{{- if not (regexMatch "^sha256:[a-f0-9]{64}$" .Values.credentialGateway.image.digest) -}}
{{- fail "credentialGateway.image.digest must be an immutable sha256 digest when the gateway is enabled" -}}
{{- end -}}
{{- if not .Values.credentialGateway.wikiSecretName -}}
{{- fail "credentialGateway.wikiSecretName is required when the gateway is enabled" -}}
{{- end -}}
{{- if not .Values.credentialGateway.approvalSecretName -}}
{{- fail "credentialGateway.approvalSecretName is required when the gateway is enabled" -}}
{{- end -}}
{{- if not .Values.credentialGateway.imagePullSecretName -}}
{{- fail "credentialGateway.imagePullSecretName is required when the gateway is enabled" -}}
{{- end -}}
{{- if not .Values.credentialGateway.wikiGraphqlUrl -}}
{{- fail "credentialGateway.wikiGraphqlUrl is required when the gateway is enabled" -}}
{{- end -}}
{{- if not (regexMatch "^[a-z0-9][a-z0-9_-]*$" .Values.credentialGateway.wikiAuthorization.memberId) -}}
{{- fail "credentialGateway.wikiAuthorization.memberId must be one canonical member path segment" -}}
{{- end -}}
{{- if eq (len .Values.credentialGateway.wikiAuthorization.allowedOperations) 0 -}}
{{- fail "credentialGateway.wikiAuthorization.allowedOperations must not be empty when the gateway is enabled" -}}
{{- end -}}
{{- range .Values.credentialGateway.wikiAuthorization.allowedOperations -}}
{{- if not (has . (list "list" "search" "get" "create" "update" "delete" "move")) -}}
{{- fail "credentialGateway.wikiAuthorization.allowedOperations contains an unknown operation" -}}
{{- end -}}
{{- end -}}
{{- end -}}
{{- if and .Values.browser.enabled (not .Values.browser.allowedHosts) -}}
{{- fail "browser.allowedHosts is required when browser is enabled" -}}
{{- end -}}
{{- if and .Values.browser.enabled (not .Values.browser.mcpUrl) -}}
{{- fail "browser.mcpUrl is required when browser is enabled" -}}
{{- end -}}
{{- if and .Values.browser.enabled (not .Values.browser.proxyUrl) -}}
{{- fail "browser.proxyUrl is required when browser is enabled" -}}
{{- end -}}
{{- range .Values.profile.telegram.allowedUserIds -}}
{{- if not (regexMatch "^[0-9]+$" (include "hermes.telegramId" .)) -}}
{{- fail "profile.telegram.allowedUserIds contains a non-numeric ID" -}}
{{- end -}}
{{- end -}}
{{- range .Values.profile.telegram.adminUserIds -}}
{{- if not (regexMatch "^[0-9]+$" (include "hermes.telegramId" .)) -}}
{{- fail "profile.telegram.adminUserIds contains a non-numeric ID" -}}
{{- end -}}
{{- $adminId := include "hermes.telegramId" . -}}
{{- $present := false -}}
{{- range $.Values.profile.telegram.allowedUserIds -}}
{{- if eq (include "hermes.telegramId" .) $adminId -}}{{- $present = true -}}{{- end -}}
{{- end -}}
{{- if not $present -}}
{{- fail (printf "administrator %s must also appear in allowedUserIds" $adminId) -}}
{{- end -}}
{{- end -}}
{{- end -}}
