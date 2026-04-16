# ============================================================
# Showcase NUC Monitor - monitor.ps1
# Webhook and NUC ID injected at install time
# ============================================================

$ErrorActionPreference = "SilentlyContinue"

$webhookUrl = "WEBHOOK_URL_PLACEHOLDER"
$nucName    = "NUCID_PLACEHOLDER"
$tempPath   = "$env:TEMP\nuc_shot.jpg"

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
