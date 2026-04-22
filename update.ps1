# ============================================================
# Showcase NUC Monitor - update.ps1 (v1.6)
# Runs daily at 2am via scheduled task
# v1.6: Replaced broken Set-ScheduledTask reconciliation with
#       full task re-registration via XML. Guarantees the
#       random delay is applied on every NUC, fleet-wide.
# ============================================================

$ErrorActionPreference = "SilentlyContinue"

$monitorDir  = "C:\ProgramData\showcase-monitor"
$logFile     = "$monitorDir\update.log"
$versionFile = "$monitorDir\version.txt"
$baseUrl     = "https://raw.githubusercontent.com/showcase-msga/showcase/main"
$timestamp   = Get-Date -Format "yyyy-MM-dd HH:mm:ss"

function Write-Log($message) {
    $entry = "$timestamp | $message"
    Add-Content -Path $logFile -Value $entry -ErrorAction SilentlyContinue
}

# ---- v1.6: Re-register screenshot task with random delay baked in ----
# Idempotent: only re-registers if the delay isn't already PT10M.
# Uses the same XML pattern as install.ps1, guaranteed to apply.
$taskName = "Showcase NUC Monitor"
$vbsPath  = "$monitorDir\run-silent.vbs"

try {
    $existingTask = Get-ScheduledTask -TaskName $taskName -ErrorAction Stop
    $currentDelay = $existingTask.Triggers[0].RandomDelay

    if ($currentDelay -ne "PT10M") {
        $screenshotXml = @"
<?xml version="1.0" encoding="UTF-16"?>
<Task version="1.2" xmlns="http://schemas.microsoft.com/windows/2004/02/mit/task">
  <Triggers>
    <CalendarTrigger>
      <StartBoundary>2026-01-01T08:30:00</StartBoundary>
      <Enabled>true</Enabled>
      <RandomDelay>PT10M</RandomDelay>
      <ScheduleByDay>
        <DaysInterval>1</DaysInterval>
      </ScheduleByDay>
      <Repetition>
        <Interval>PT30M</Interval>
        <Duration>PT8H30M</Duration>
        <StopAtDurationEnd>false</StopAtDurationEnd>
      </Repetition>
    </CalendarTrigger>
  </Triggers>
  <Principals>
    <Principal id="Author">
      <LogonType>InteractiveToken</LogonType>
      <RunLevel>LeastPrivilege</RunLevel>
    </Principal>
  </Principals>
  <Settings>
    <Hidden>true</Hidden>
    <MultipleInstancesPolicy>IgnoreNew</MultipleInstancesPolicy>
    <ExecutionTimeLimit>PT5M</ExecutionTimeLimit>
    <StartWhenAvailable>true</StartWhenAvailable>
    <Enabled>true</Enabled>
  </Settings>
  <Actions>
    <Exec>
      <Command>wscript.exe</Command>
      <Arguments>"$vbsPath"</Arguments>
    </Exec>
  </Actions>
</Task>
"@

        Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction Stop
        Register-ScheduledTask -TaskName $taskName -Xml $screenshotXml -Force -ErrorAction Stop | Out-Null

        # Verify the delay actually applied
        $verifyTask = Get-ScheduledTask -TaskName $taskName -ErrorAction Stop
        $verifyDelay = $verifyTask.Triggers[0].RandomDelay
        if ($verifyDelay -eq "PT10M") {
            Write-Log "Re-registered screenshot task with RandomDelay PT10M (was: '$currentDelay')"
        } else {
            Write-Log "WARNING: Re-registered task but verification shows RandomDelay = '$verifyDelay' (expected PT10M)"
        }
    }
} catch {
    Write-Log "Failed to reconcile screenshot task: $($_.Exception.Message)"
}

# ---- Check internet connectivity ----
try {
    $null = Invoke-WebRequest "https://raw.githubusercontent.com" -UseBasicParsing -TimeoutSec 10
} catch {
    Write-Log "No internet connection - skipping update check"
    exit
}

# ---- Get remote version ----
try {
    $remoteVersion = (Invoke-WebRequest "$baseUrl/version.txt" -UseBasicParsing).Content.Trim()
} catch {
    Write-Log "Failed to fetch remote version - skipping update check"
    exit
}

# ---- Get local version ----
$localVersion = "0.0"
if (Test-Path $versionFile) {
    $localVersion = (Get-Content $versionFile -Raw).Trim()
}

# ---- Compare versions ----
if ($remoteVersion -eq $localVersion) {
    Write-Log "Version $localVersion | No update required"
    exit
}

# ---- Read existing webhook URL and NUC ID from current monitor.ps1 ----
$existingMonitor = Get-Content "$monitorDir\monitor.ps1" -Raw -ErrorAction SilentlyContinue
$webhookMatch    = [regex]::Match($existingMonitor, '\$webhookUrl\s*=\s*"([^"]+)"')
$nucMatch        = [regex]::Match($existingMonitor, '\$nucName\s*=\s*"([^"]+)"')

if (-not $webhookMatch.Success -or -not $nucMatch.Success) {
    Write-Log "Version $localVersion -> $remoteVersion | Failed to read webhook/NUC ID from existing monitor.ps1 - aborting update"
    exit
}

$webhook = $webhookMatch.Groups[1].Value
$nucId   = $nucMatch.Groups[1].Value

# ---- Download and update all files ----
try {
    # monitor.ps1 - inject webhook and NUC ID
    $monitorScript = (Invoke-WebRequest "$baseUrl/monitor.ps1" -UseBasicParsing).Content
    $monitorScript = $monitorScript -replace 'WEBHOOK_URL_PLACEHOLDER', $webhook
    $monitorScript = $monitorScript -replace 'NUCID_PLACEHOLDER', $nucId
    [System.IO.File]::WriteAllText("$monitorDir\monitor.ps1", $monitorScript)

    # run-silent.vbs
    $vbsContent = (Invoke-WebRequest "$baseUrl/run-silent.vbs" -UseBasicParsing).Content
    [System.IO.File]::WriteAllText("$monitorDir\run-silent.vbs", $vbsContent)

    # test-screenshot.bat
    $batContent = (Invoke-WebRequest "$baseUrl/test-screenshot.bat" -UseBasicParsing).Content
    [System.IO.File]::WriteAllText("$monitorDir\test-screenshot.bat", $batContent)

    # uninstall.bat
    $uninstallContent = (Invoke-WebRequest "$baseUrl/uninstall.bat" -UseBasicParsing).Content
    [System.IO.File]::WriteAllText("$monitorDir\uninstall.bat", $uninstallContent)

    # v1.6: update.ps1 - self-refresh so future updates to the updater itself can deploy
    $updateScriptContent = (Invoke-WebRequest "$baseUrl/update.ps1" -UseBasicParsing).Content
    [System.IO.File]::WriteAllText("$monitorDir\update.ps1", $updateScriptContent)

    # Save new version
    [System.IO.File]::WriteAllText($versionFile, $remoteVersion)

    Write-Log "Version $localVersion -> $remoteVersion | Updated successfully | NUC: $nucId"

} catch {
    Write-Log "Version $localVersion -> $remoteVersion | Update failed: $($_.Exception.Message)"
}
