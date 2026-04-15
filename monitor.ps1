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

# Take screenshot
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$screen   = [System.Windows.Forms.Screen]::PrimaryScreen
$bitmap   = New-Object System.Drawing.Bitmap($screen.Bounds.Width, $screen.Bounds.Height)
$graphics = [System.Drawing.Graphics]::FromImage($bitmap)
$graphics.CopyFromScreen($screen.Bounds.Location, [System.Drawing.Point]::Empty, $screen.Bounds.Size)

# Save as JPEG 70% quality
$jpegEncoder   = [System.Drawing.Imaging.ImageCodecInfo]::GetImageEncoders() | Where-Object { $_.MimeType -eq 'image/jpeg' }
$encoderParams = New-Object System.Drawing.Imaging.EncoderParameters(1)
$encoderParams.Param[0] = New-Object System.Drawing.Imaging.EncoderParameter(
    [System.Drawing.Imaging.Encoder]::Quality, 70L
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
