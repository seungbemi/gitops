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
{{- if not (has .Values.profile.name (list "admin" "rina")) -}}
{{- fail "profile.name must be admin or rina when enabled" -}}
{{- end -}}
{{- if and (eq .Values.profile.name "admin") (ne .Values.profile.kubernetes.scope "cluster") -}}
{{- fail "the admin profile requires profile.kubernetes.scope=cluster" -}}
{{- end -}}
{{- if and (eq .Values.profile.name "rina") (ne .Values.profile.kubernetes.scope "rina-company") -}}
{{- fail "the rina profile requires profile.kubernetes.scope=rina-company" -}}
{{- end -}}
{{- if not .Values.profile.runtimeSecretName -}}
{{- fail "profile.runtimeSecretName is required when enabled" -}}
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
{{- if and .Values.browser.enabled (not .Values.browser.allowedHosts) -}}
{{- fail "browser.allowedHosts is required when browser is enabled" -}}
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
