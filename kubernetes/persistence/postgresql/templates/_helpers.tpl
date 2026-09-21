{{- define "postgresql17.labels" -}}
app.kubernetes.io/name: postgresql
app.kubernetes.io/instance: postgresql-v17
app.kubernetes.io/component: primary
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/version: "17.11"
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version | quote }}
{{- end }}

{{- define "postgresql17.selectorLabels" -}}
app.kubernetes.io/name: postgresql
app.kubernetes.io/instance: postgresql-v17
app.kubernetes.io/component: primary
{{- end }}

{{- define "postgresql17.image" -}}
{{- if .Values.postgresql17.image.digest -}}
{{ printf "%s:%s@%s" .Values.postgresql17.image.repository .Values.postgresql17.image.tag .Values.postgresql17.image.digest }}
{{- else -}}
{{ printf "%s:%s" .Values.postgresql17.image.repository .Values.postgresql17.image.tag }}
{{- end -}}
{{- end }}

{{- define "postgresql17.metricsImage" -}}
{{- if .Values.postgresql17.metrics.image.digest -}}
{{ printf "%s:%s@%s" .Values.postgresql17.metrics.image.repository .Values.postgresql17.metrics.image.tag .Values.postgresql17.metrics.image.digest }}
{{- else -}}
{{ printf "%s:%s" .Values.postgresql17.metrics.image.repository .Values.postgresql17.metrics.image.tag }}
{{- end -}}
{{- end }}
