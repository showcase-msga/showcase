# ============================================================
# Showcase NUC Monitor - install.ps1 (v1.5)
# Called remotely, variables injected via command line
# Usage: $nucId and $webhook must be set before calling this
# v1.5: 10-minute random delay on screenshot trigger to prevent
#       Apps Script concurrency saturation across the fleet
# ============================================================

$monitorDir  = "C:\ProgramData\showcase-monitor"
$taskName    = "Showcase NUC Monitor"
$baseUrl     = "https://raw.githubusercontent.com/showcase-msga/showcase/main"

# ---- Step 1: Set execution policy ----
Set-ExecutionPolicy Bypass -Scope LocalMachine -Force

# ---- Step 2: Create folder ----
if (-not (Test-Path $monitorDir)) {
    New-Item -ItemType Directory -Path $monitorDir -Force | Out-Null
}

# ---- Step 3: Download monitor.ps1 and inject webhook URL ----
$monitorScript = (Invoke-WebRequest "$baseUrl/monitor.ps1" -UseBasicParsing).Content
$monitorScript = $monitorScript -replace 'WEBHOOK_URL_PLACEHOLDER', $webhook
$monitorScript = $monitorScript -replace 'NUCID_PLACEHOLDER', $nucId
[System.IO.File]::WriteAllText("$monitorDir\monitor.ps1", $monitorScript)

# ---- Step 4: Download run-silent.vbs ----
$vbsContent = (Invoke-WebRequest "$baseUrl/run-silent.vbs" -UseBasicParsing).Content
[System.IO.File]::WriteAllText("$monitorDir\run-silent.vbs", $vbsContent)

# ---- Step 4b: Download test-screenshot.bat ----
$batContent = (Invoke-WebRequest "$baseUrl/test-screenshot.bat" -UseBasicParsing).Content
[System.IO.File]::WriteAllText("$monitorDir\test-screenshot.bat", $batContent)

# ---- Step 4c: Download uninstall.bat ----
$uninstallContent = (Invoke-WebRequest "$baseUrl/uninstall.bat" -UseBasicParsing).Content
[System.IO.File]::WriteAllText("$monitorDir\uninstall.bat", $uninstallContent)

# ---- Step 4d: Download update.ps1 ----
$updateContent = (Invoke-WebRequest "$baseUrl/update.ps1" -UseBasicParsing).Content
[System.IO.File]::WriteAllText("$monitorDir\update.ps1", $updateContent)

# ---- Step 5: Write nuc-id.txt ----
[System.IO.File]::WriteAllText("$monitorDir\nuc-id.txt", $nucId)

# ---- Step 5b: Write version.txt ----
$currentVersion = (Invoke-WebRequest "$baseUrl/version.txt" -UseBasicParsing).Content.Trim()
[System.IO.File]::WriteAllText("$monitorDir\version.txt", $currentVersion)

# ---- Step 6: Create desktop shortcut ----
$desktopPath  = [System.Environment]::GetFolderPath("CommonDesktopDirectory")
$shortcutPath = "$desktopPath\Showcase Monitor.lnk"
$wshell       = New-Object -ComObject WScript.Shell
$shortcut     = $wshell.CreateShortcut($shortcutPath)
$shortcut.TargetPath  = $monitorDir
$shortcut.Description = "Showcase NUC Monitor Scripts"
$shortcut.Save()

# ---- Step 7: Create scheduled task via XML ----
# v1.5: Added <RandomDelay>PT10M</RandomDelay> to spread fleet load
Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue

$vbsPath = "$monitorDir\run-silent.vbs"
$xml = @"
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

Register-ScheduledTask -TaskName $taskName -Xml $xml -Force | Out-Null

# ---- Step 8: Register auto-updater scheduled task ----
$updateTaskName = "Showcase NUC Monitor Updater"
Unregister-ScheduledTask -TaskName $updateTaskName -Confirm:$false -ErrorAction SilentlyContinue

$updateXml = @"
<?xml version="1.0" encoding="UTF-16"?>
<Task version="1.2" xmlns="http://schemas.microsoft.com/windows/2004/02/mit/task">
  <Triggers>
    <CalendarTrigger>
      <StartBoundary>2026-01-01T02:00:00</StartBoundary>
      <Enabled>true</Enabled>
      <ScheduleByDay>
        <DaysInterval>1</DaysInterval>
      </ScheduleByDay>
    </CalendarTrigger>
  </Triggers>
  <Principals>
    <Principal id="Author">
      <UserId>S-1-5-18</UserId>
      <RunLevel>HighestAvailable</RunLevel>
    </Principal>
  </Principals>
  <Settings>
    <Hidden>true</Hidden>
    <MultipleInstancesPolicy>IgnoreNew</MultipleInstancesPolicy>
    <ExecutionTimeLimit>PT10M</ExecutionTimeLimit>
    <StartWhenAvailable>true</StartWhenAvailable>
    <Enabled>true</Enabled>
  </Settings>
  <Actions>
    <Exec>
      <Command>powershell.exe</Command>
      <Arguments>-ExecutionPolicy Bypass -WindowStyle Hidden -NonInteractive -NoProfile -File "$monitorDir\update.ps1"</Arguments>
    </Exec>
  </Actions>
</Task>
"@

Register-ScheduledTask -TaskName $updateTaskName -Xml $updateXml -Force | Out-Null

# ---- Step 9: Add Defender exclusion ----
Add-MpPreference -ExclusionPath $monitorDir -ErrorAction SilentlyContinue

Write-Host "Showcase NUC Monitor installed successfully." -ForegroundColor Green
Write-Host "NUC ID: $nucId" -ForegroundColor Green
Write-Host "Folder: $monitorDir" -ForegroundColor Green
