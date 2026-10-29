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


{{- define "custom.servingParams" -}}
{{- $resources := .resources }}
{{- $serving := .params.serving }}

{{- $cpuLimit := $resources.limits.cpu | default $resources.requests.cpu | default "1000m" }}

{{- $cpuLimitAsInt := 1 }}
{{- $cpuLimitType := printf "%T" $cpuLimit }}
{{- if and (eq "string" $cpuLimitType ) }}
  {{- if not (hasSuffix "m" $cpuLimit) }}
  {{ fail "cpu limit and requests must be a number or in <number>m format" }}
  {{- end }}
  {{- $cpuLimitIntCast := int (trimSuffix "m" $cpuLimit) }}
  {{- $cpuLimitAsInt = div $cpuLimitIntCast 1000 | ceil }}
{{- else }}
  {{- $cpuLimitAsInt = ceil $cpuLimit | int }}
{{- end }}

{{- /* Initialize variables with default values */ -}}
{{- $intraOpConcurrency := $serving.intraOpConcurrency }}
{{- $interOpConcurrency := $serving.interOpConcurrency }}
{{- $maxGrpcThreads := $serving.maxGrpcThreads }}

{{- /* Override if values are zero */ -}}
{{- if eq (int $serving.intraOpConcurrency) 0 }}
  {{- $intraOpConcurrency = $cpuLimitAsInt }}
{{- end }}
{{- if eq (int $serving.interOpConcurrency) 0 }}
  {{- $interOpConcurrency = div (mul $cpuLimitAsInt 3) 2 | int }}
{{- end }}
{{- if eq (int $serving.maxGrpcThreads) 0 }}
  {{- $maxGrpcThreads = mul $cpuLimitAsInt 4 }}
{{- end }}
intraOpConcurrency: {{ $intraOpConcurrency }}
interOpConcurrency: {{ $interOpConcurrency }}
maxGrpcThreads: {{ $maxGrpcThreads }}
{{- end -}}

{{- /*
Build gke-concurrency-proxy context from a merged deployment ($dep) and root context ($root).
Usage: include "tensorflow-serving.proxyCtx" (dict "dep" $dep "root" $)
*/ -}}
{{- define "tensorflow-serving.proxyCtx" -}}
{{- $dep := .dep -}}
{{- $root := .root -}}
{{- $sanitizedName := include "tensorflow-serving.sanitizeModelName" $dep.name -}}
{{- $labels := dict
  "app.kubernetes.io/name" "tensorflow-serving"
  "app.kubernetes.io/instance" (include "tensorflow-serving.name" $root)
  "deploymentName" $dep.name
-}}
{{- $selectorLabels := dict
  "app.kubernetes.io/name" "tensorflow-serving"
  "deploymentName" $dep.name
-}}
{{- $envoy := dig "envoy" (dict) $dep -}}
{{- $hpa := dig "hpa" (dict) $dep -}}
{{- $customMetric := dig "customMetric" (dict) $hpa -}}
{{- $autoscalingEnabled := and (dig "enabled" false $hpa) (dig "enabled" false $customMetric) -}}
{{- $proxyValues := dict
  "enabled" (dig "enabled" false $envoy)
  "mode" "grpc"
  "image" (dig "image" (dict) $envoy)
  "listenPort" (dig "listenPort" 8080 $envoy)
  "adminPort" (dig "adminPort" 9901 $envoy)
  "resources" (dig "resources" (dict) $envoy)
  "upstream" (dict "host" "127.0.0.1" "port" 8500)
  "concurrencyRoutes" (dig "concurrencyRoutes" (dict) $envoy)
  "autoscaling" (dict
    "enabled" $autoscalingEnabled
    "minReplicas" (dig "minReplicas" 1 $hpa)
    "maxReplicas" (dig "maxReplicas" 10 $hpa)
    "gaugeName" (dig "name" "active-requests" $customMetric)
    "prometheusMetricName" (dig "prometheusMetricName" "envoy_http_downstream_rq_active" $customMetric)
    "averageValue" (dig "averageValue" "4" $customMetric)
    "scaleDownStabilizationWindowSeconds" (dig "scaleDownStabilizationWindowSeconds" 600 $customMetric)
  )
-}}
{{- dict
  "name" $dep.name
  "namespace" (include "tensorflow-serving.namespace" $root)
  "labels" $labels
  "selectorLabels" $selectorLabels
  "scaleTargetRef" (dict "apiVersion" "apps/v1" "kind" "Deployment" "name" (printf "d-%s" $sanitizedName))
  "values" $proxyValues
| toYaml -}}
{{- end -}}
