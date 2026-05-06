# ============================================================
# Showcase NUC Monitor - monitor.ps1 (v1.9)
# Webhook and NUC ID injected at install time.
# Writes webhook.txt and nuc-id.txt then calls NucMonitor.exe.
# run-silent.vbs calls NucMonitor.exe directly going forward.
# ============================================================

$ErrorActionPreference = "SilentlyContinue"

$webhookUrl = "WEBHOOK_URL_PLACEHOLDER"
$nucName    = "NUCID_PLACEHOLDER"
$monitorDir = "C:\ProgramData\showcase-monitor"

# Write config files so run-silent.vbs can read them directly
[System.IO.File]::WriteAllText("$monitorDir\webhook.txt", $webhookUrl)
[System.IO.File]::WriteAllText("$monitorDir\nuc-id.txt",  $nucName)

& "$monitorDir\NucMonitor.exe" $webhookUrl $nucName
