# ============================================================
# Showcase NUC Monitor - install.ps1
# Called remotely, variables injected via command line
# Usage: $nucId and $webhook must be set before calling this
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

# ---- Step 4c: Download reset.bat ----
$resetContent = (Invoke-WebRequest "$baseUrl/reset.bat" -UseBasicParsing).Content
[System.IO.File]::WriteAllText("$monitorDir\reset.bat", $resetContent)

# ---- Step 5: Write nuc-id.txt ----
[System.IO.File]::WriteAllText("$monitorDir\nuc-id.txt", $nucId)

# ---- Step 6: Create desktop shortcut ----
$desktopPath  = [System.Environment]::GetFolderPath("CommonDesktopDirectory")
$shortcutPath = "$desktopPath\Showcase Monitor.lnk"
$wshell       = New-Object -ComObject WScript.Shell
$shortcut     = $wshell.CreateShortcut($shortcutPath)
$shortcut.TargetPath  = $monitorDir
$shortcut.Description = "Showcase NUC Monitor Scripts"
$shortcut.Save()

# ---- Step 7: Create scheduled task via XML ----
Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue

$vbsPath = "$monitorDir\run-silent.vbs"
$xml = @"
<?xml version="1.0" encoding="UTF-16"?>
<Task version="1.2" xmlns="http://schemas.microsoft.com/windows/2004/02/mit/task">
  <Triggers>
    <CalendarTrigger>
      <StartBoundary>2026-01-01T08:30:00</StartBoundary>
      <Enabled>true</Enabled>
      <ScheduleByDay>
        <DaysInterval>1</DaysInterval>
      </ScheduleByDay>
      <Repetition>
        <Interval>PT1H</Interval>
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

# ---- Step 8: Add Defender exclusion ----
Add-MpPreference -ExclusionPath $monitorDir -ErrorAction SilentlyContinue

Write-Host "Showcase NUC Monitor installed successfully." -ForegroundColor Green
Write-Host "NUC ID: $nucId" -ForegroundColor Green
Write-Host "Folder: $monitorDir" -ForegroundColor Green
