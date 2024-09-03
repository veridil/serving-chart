{{- define "tensorflow-serving.labels" -}}
helm.sh/chart: {{ include "tensorflow-serving.chart" . }}
app.kubernetes.io/name: tensorflow-serving
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{- define "tensorflow-serving.selectorLabels" -}}
app.kubernetes.io/name: tensorflow-serving
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{- define "tensorflow-serving.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "tensorflow-serving.name" -}}
{{- printf "%s-%s" .Release.Name .Chart.Name | trunc 63 | trimSuffix "-" | replace "+" "_" | replace "." "_" | lower -}}
{{- end }}

{{- define "tensorflow-serving.namespace" -}}
{{- if .Values.namespaceOverride }}
{{- .Values.namespaceOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- .Release.Namespace | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}

{{- define "tensorflow-serving.sanitizeModelName" -}}
{{- printf "%s" . | trunc 63 | trimSuffix "-" | replace "_" "-" | replace "+" "-" | replace "." "-" | lower -}}
{{- end }}


{{- define "tensorflow-serving.modelConfig" -}}
model_config_list: {
  {{- range $index, $modelId := . }}
  config: {
    name: "{{ $modelId }}",
    base_path: "/models/{{ $modelId }}",
    model_platform: "tensorflow"
  }{{- if not (eq (add1 $index) (len .)) }},{{ end }}
  {{- end }}
}
{{- end }}