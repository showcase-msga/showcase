# ============================================================
# Showcase NUC Monitor - update.ps1
# Runs daily at 2am via scheduled task
# Checks GitHub version, updates files if newer version found
# Fully silent - no windows, no popups
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

    # Save new version
    [System.IO.File]::WriteAllText($versionFile, $remoteVersion)

    Write-Log "Version $localVersion -> $remoteVersion | Updated successfully | NUC: $nucId"

} catch {
    Write-Log "Version $localVersion -> $remoteVersion | Update failed: $($_.Exception.Message)"
}
