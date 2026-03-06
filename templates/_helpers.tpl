{{/*
Nome base do chart (usado como prefixo de recursos)
*/}}
{{- define "observability.name" -}}
{{- .Chart.Name | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Nome completo: <release>-<chart> ou override via fullnameOverride
*/}}
{{- define "observability.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name .Chart.Name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}

{{/*
Labels padrão aplicados em todos os recursos deste chart
*/}}
{{- define "observability.labels" -}}
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 }}
app.kubernetes.io/name: {{ include "observability.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Nome do serviço do Loki (derivado do release name)
Chart grafana/loki 6.x em SingleBinary mode.
O serviço gerado é: <release>-loki:3100
Porta 3100 = HTTP API (incluindo /loki/api/v1/index/volume, Loki 3.x+)
*/}}
{{- define "observability.lokiUrl" -}}
http://{{ .Release.Name }}-loki:3100
{{- end }}

{{/*
Nome do serviço do Prometheus (derivado do release name)
O subchart prometheus gera o servidor como: <release>-prometheus-server
*/}}
{{- define "observability.prometheusUrl" -}}
http://{{ .Release.Name }}-prometheus-server:80
{{- end }}

{{/*
Nome do serviço do Tempo (derivado do release name)
O subchart tempo gera o serviço como: <release>-tempo
*/}}
{{- define "observability.tempoUrl" -}}
http://{{ .Release.Name }}-tempo:3200
{{- end }}

{{/*
Nome do secret de admin do Grafana
*/}}
{{- define "observability.grafanaAdminSecret" -}}
{{- printf "%s-grafana-admin" .Release.Name }}
{{- end }}
