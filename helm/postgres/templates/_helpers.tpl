{{/*
Expand the name of the chart.
*/}}
{{- define "airgap-postgres.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
*/}}
{{- define "airgap-postgres.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- $name := default .Chart.Name .Values.nameOverride }}
{{- if contains $name .Release.Name }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}
{{- end }}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "airgap-postgres.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "airgap-postgres.labels" -}}
helm.sh/chart: {{ include "airgap-postgres.chart" . }}
{{ include "airgap-postgres.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "airgap-postgres.selectorLabels" -}}
app.kubernetes.io/name: {{ include "airgap-postgres.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Create the name of the service account to use
*/}}
{{- define "airgap-postgres.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "airgap-postgres.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
Return the proper PostgreSQL image name
*/}}
{{- define "airgap-postgres.postgresql.image" -}}
{{- $registry := .Values.global.imageRegistry -}}
{{- $repository := .Values.postgresql.image.repository -}}
{{- $tag := .Values.postgresql.image.tag | toString -}}
{{- printf "%s/%s:%s" $registry $repository $tag -}}
{{- end }}

{{/*
Return the proper HAProxy image name
*/}}
{{- define "airgap-postgres.haproxy.image" -}}
{{- $registry := .Values.global.imageRegistry -}}
{{- $repository := .Values.haproxy.image.repository -}}
{{- $tag := .Values.haproxy.image.tag | toString -}}
{{- printf "%s/%s:%s" $registry $repository $tag -}}
{{- end }}

{{/*
Return the proper backup image name
*/}}
{{- define "airgap-postgres.backup.image" -}}
{{- $registry := .Values.global.imageRegistry -}}
{{- $repository := .Values.backup.image.repository -}}
{{- $tag := .Values.backup.image.tag | toString -}}
{{- printf "%s/%s:%s" $registry $repository $tag -}}
{{- end }}

{{/*
Return the proper recovery image name
*/}}
{{- define "airgap-postgres.recovery.image" -}}
{{- $registry := .Values.global.imageRegistry -}}
{{- $repository := .Values.recovery.image.repository -}}
{{- $tag := .Values.recovery.image.tag | toString -}}
{{- printf "%s/%s:%s" $registry $repository $tag -}}
{{- end }}

{{/*
Return the PostgreSQL secret name
*/}}
{{- define "airgap-postgres.secretName" -}}
{{- printf "%s-credentials" (include "airgap-postgres.fullname" .) -}}
{{- end }}

{{/*
Return the PostgreSQL primary service name
*/}}
{{- define "airgap-postgres.primary.serviceName" -}}
{{- printf "%s-primary" (include "airgap-postgres.fullname" .) -}}
{{- end }}

{{/*
Return the PostgreSQL headless service name
*/}}
{{- define "airgap-postgres.headless.serviceName" -}}
{{- printf "%s-headless" (include "airgap-postgres.fullname" .) -}}
{{- end }}
