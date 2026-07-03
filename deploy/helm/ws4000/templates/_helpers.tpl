{{- define "ws4000.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "ws4000.fullname" -}}
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

{{- define "ws4000.labels" -}}
app.kubernetes.io/name: {{ include "ws4000.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" }}
{{- end }}

{{- define "ws4000.selectorLabels" -}}
app.kubernetes.io/name: {{ include "ws4000.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{- define "ws4000.nfsExport" -}}
{{- .Values.nfs.export | default "/exports/shared" -}}
{{- end }}

{{- define "ws4000.musicNfsSubPath" -}}
{{- .Values.nfs.subPath | default (trimPrefix (printf "%s/" (include "ws4000.nfsExport" .)) .Values.nfs.path.music) -}}
{{- end }}

{{- define "ws4000.configNfsSubPath" -}}
{{- .Values.config.nfs.subPath | default "apps/ws4000-config" -}}
{{- end }}

{{- define "ws4000.configFileSubPath" -}}
{{- $file := .file -}}
{{- $ctx := .context -}}
{{- if eq $ctx.Values.config.type "nfs" -}}
{{- printf "%s/%s" (include "ws4000.configNfsSubPath" $ctx) $file -}}
{{- else -}}
{{- $file -}}
{{- end -}}
{{- end }}

{{- define "ws4000.configDirSubPath" -}}
{{- if eq .Values.config.type "nfs" -}}
{{- include "ws4000.configNfsSubPath" . -}}
{{- end -}}
{{- end }}

{{- define "ws4000.configNfsServer" -}}
{{- .Values.config.nfs.server | default .Values.nfs.server -}}
{{- end }}

{{- define "ws4000.configNfsExport" -}}
{{- .Values.config.nfs.export | default (include "ws4000.nfsExport" .) -}}
{{- end }}

{{- define "ws4000.configPvcName" -}}
{{- .Values.config.pvc.existingClaim | default (printf "%s-config" (include "ws4000.fullname" .)) -}}
{{- end }}

{{- define "ws4000.streamLogoPath" -}}
{{- if .Values.config.enabled -}}
/config/{{ .Values.branding.streamLogo }}
{{- else -}}
{{- .Values.stream.logo -}}
{{- end -}}
{{- end }}
