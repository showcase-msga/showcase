# ============================================================
# Showcase NUC Monitor - monitor.ps1 (v1.6)
# Webhook and NUC ID injected at install time
# ============================================================

$ErrorActionPreference = "SilentlyContinue"

$webhookUrl = "WEBHOOK_URL_PLACEHOLDER"
$nucName    = "NUCID_PLACEHOLDER"
$tempPath   = "$env:TEMP\nuc_shot.jpg"

# ---- v1.6 BOOTSTRAP: One-time refresh of update.ps1 ----
# v1.5 update.ps1 doesn't download a new update.ps1, which means v1.6's
# proper random-delay reconciliation block can't deploy via the normal
# auto-update path. This bootstrap fires from monitor.ps1 (which IS
# auto-deployed) to download v1.6 update.ps1 once, then marks itself done.
# Safe to remove in v1.7 or later once the fleet is on v1.6.
$monitorDir       = "C:\ProgramData\showcase-monitor"
$bootstrapMarker  = "$monitorDir\v16-bootstrap-done.txt"
if (-not (Test-Path $bootstrapMarker)) {
    try {
        $newUpdate = (Invoke-WebRequest "https://raw.githubusercontent.com/showcase-msga/showcase/main/update.ps1" -UseBasicParsing -TimeoutSec 15).Content
        if ($newUpdate -and $newUpdate.Length -gt 500 -and $newUpdate -match "Showcase NUC Monitor") {
            [System.IO.File]::WriteAllText("$monitorDir\update.ps1", $newUpdate)
            New-Item $bootstrapMarker -ItemType File -Force | Out-Null
            Add-Content -Path "$monitorDir\update.log" -Value "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') | Bootstrap: refreshed update.ps1 to v1.6 from monitor.ps1"
        }
    } catch {
        # Silent fail - bootstrap will retry on next monitor.ps1 run (every 30 min)
    }
}

# Timestamp for filename
$timestamp = Get-Date -Format "yyyy-MM-dd HH-mm"

# Take screenshot - DPI aware, captures full screen regardless of scaling
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type @"
using System;
using System.Runtime.InteropServices;
public class DpiHelper {
    [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
    [DllImport("gdi32.dll")] public static extern int GetDeviceCaps(IntPtr hdc, int nIndex);
    [DllImport("user32.dll")] public static extern IntPtr GetDC(IntPtr hwnd);
    [DllImport("user32.dll")] public static extern int ReleaseDC(IntPtr hwnd, IntPtr hdc);
}
"@

[DpiHelper]::SetProcessDPIAware() | Out-Null

$hdc        = [DpiHelper]::GetDC([IntPtr]::Zero)
$width      = [DpiHelper]::GetDeviceCaps($hdc, 118)  # DESKTOPHORZRES
$height     = [DpiHelper]::GetDeviceCaps($hdc, 117)  # DESKTOPVERTRES
[DpiHelper]::ReleaseDC([IntPtr]::Zero, $hdc) | Out-Null

$bitmap   = New-Object System.Drawing.Bitmap($width, $height)
$graphics = [System.Drawing.Graphics]::FromImage($bitmap)
$graphics.CopyFromScreen(0, 0, 0, 0, (New-Object System.Drawing.Size($width, $height)))

# Resize to max 1080px tall to reduce file size while preserving wide aspect ratios
$maxHeight = 1080
if ($height -gt $maxHeight) {
  $ratio    = $maxHeight / $height
  $newW     = [int]($width * $ratio)
  $newH     = $maxHeight
  $resized  = New-Object System.Drawing.Bitmap($newW, $newH)
  $g        = [System.Drawing.Graphics]::FromImage($resized)
  $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
  $g.DrawImage($bitmap, 0, 0, $newW, $newH)
  $g.Dispose()
  $bitmap.Dispose()
  $bitmap = $resized
}

# Save as JPEG 50% quality
$jpegEncoder   = [System.Drawing.Imaging.ImageCodecInfo]::GetImageEncoders() | Where-Object { $_.MimeType -eq 'image/jpeg' }
$encoderParams = New-Object System.Drawing.Imaging.EncoderParameters(1)
$encoderParams.Param[0] = New-Object System.Drawing.Imaging.EncoderParameter(
    [System.Drawing.Imaging.Encoder]::Quality, 50L
)
$bitmap.Save($tempPath, $jpegEncoder, $encoderParams)
$graphics.Dispose()
$bitmap.Dispose()

# Convert to base64
$imageBytes  = [System.IO.File]::ReadAllBytes($tempPath)
$imageBase64 = [System.Convert]::ToBase64String($imageBytes)

# Build payload
$payload = [PSCustomObject]@{
    nuc_name   = $nucName
    screenshot = $imageBase64
    timestamp  = $timestamp
} | ConvertTo-Json -Compress

# Send to Google Apps Script
Invoke-RestMethod `
    -Uri         $webhookUrl `
    -Method      Post `
    -Body        $payload `
    -ContentType "application/json" `
    -ErrorAction SilentlyContinue | Out-Null

# Cleanup
Remove-Item $tempPath -Force -ErrorAction SilentlyContinue
