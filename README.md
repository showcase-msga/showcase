# Showcase NUC Monitor v1.9

A lightweight, silent monitoring system for the AD Group Showcase NUC fleet. Each NUC automatically captures a screenshot every 30 minutes between 8:30am and 5:00pm and uploads it to a shared Google Drive folder for remote visual verification.

---

## Table of Contents

- [Overview](#overview)
- [How It Works](#how-it-works)
- [File Breakdown](#file-breakdown)
- [Architecture](#architecture)
- [Apps Script Setup](#apps-script-setup)
- [Installation](#installation)
- [Testing](#testing)
- [Auto-Update System](#auto-update-system)
- [Adding New NUCs](#adding-new-nucs)
- [Resetting a NUC](#resetting-a-nuc)
- [Google Drive Structure](#google-drive-structure)
- [Troubleshooting](#troubleshooting)
- [Changelog](#changelog)

---

## Overview

The Showcase NUC fleet runs Chrome kiosk displays across display suites nationally. The NUC Monitor solves remote visibility by:

- Running silently in the background on each NUC with zero user-facing popups or notifications
- Taking a screenshot every 30 minutes from 8:30am to 5:00pm automatically
- Uploading each screenshot to a central Google Drive folder named by NUC and timestamp
- Self-updating nightly so the fleet stays current without manual intervention
- Logging every run locally so failures are always diagnosable

---

## How It Works

```
Scheduled Task (InteractiveToken — logged-in user session)
    └── Triggers run-silent.vbs every 30 min (8:30am–5:00pm, +random 10min delay)
            └── Reads webhook.txt and nuc-id.txt
            └── Calls NucMonitor.exe directly (no PowerShell)
                    └── Takes full screenshot at native resolution
                    └── Resizes to max 1920x1080
                    └── Encodes as JPEG (50% quality)
                    └── POSTs payload to Google Apps Script webhook
                    └── Logs result to monitor.log
                            └── Apps Script decodes image
                            └── Deletes screenshots older than 7 days for this NUC
                            └── Saves new screenshot to Google Drive
```

### Why NucMonitor.exe

From v1.9, all screenshot and upload logic runs inside a compiled .NET 4 executable rather than a PowerShell script. Windows Defender AMSI (Antimalware Scan Interface) scans PowerShell scripts in memory and flags the combination of screen capture + base64 + HTTP POST as malware — regardless of intent. Compiled binaries are not subject to AMSI script scanning, so the exe runs cleanly on all NUCs without requiring exclusions or policy changes.

### Why InteractiveToken Matters

The scheduled task runs using `InteractiveToken` which means it executes in the same desktop session as the logged-in user. Running as `SYSTEM` has no desktop session — screenshots come out black. `InteractiveToken` sees exactly what is on screen.

### Schedule

| Time | Screenshot |
|------|-----------|
| 8:30am (+0-10min) | ✓ |
| 9:00am (+0-10min) | ✓ |
| 9:30am (+0-10min) | ✓ |
| ... every 30 min ... | ✓ |
| 4:30pm (+0-10min) | ✓ |

The random 10-minute delay prevents all NUCs firing simultaneously and saturating the Apps Script webhook.

---

## File Breakdown

### `NucMonitor.exe`
Compiled .NET 4 binary. Does all the actual work: takes screenshot, resizes, encodes as JPEG, POSTs to webhook, logs result to `monitor.log`. Called by both `run-silent.vbs` (scheduled) and directly for testing. Not subject to AMSI scanning.

---

### `monitor.ps1`
Thin wrapper. Writes `webhook.txt` and `nuc-id.txt` from the injected placeholders, then calls `NucMonitor.exe`. The webhook URL and NUC ID are injected at install time — GitHub version uses `WEBHOOK_URL_PLACEHOLDER` and `NUCID_PLACEHOLDER`.

---

### `run-silent.vbs`
Reads `webhook.txt` and `nuc-id.txt`, then calls `NucMonitor.exe` silently with no visible window. No PowerShell involved. This is what the scheduled task triggers.

---

### `update.ps1`
Daily auto-updater (2am, SYSTEM context). Compares local `version.txt` against GitHub. If newer, downloads all files including `NucMonitor.exe`, re-injects webhook URL and NUC ID into `monitor.ps1`, writes `webhook.txt` and `nuc-id.txt`, and logs the result to `update.log`.

---

### `install.ps1`
One-time installer. Downloads all files from GitHub, injects webhook URL and NUC ID, writes config files, registers both scheduled tasks, adds Defender exclusion, creates desktop shortcut.

---

### `test-screenshot.bat`
Manually triggers a screenshot via `monitor.ps1`. Double-click on the NUC to test. Check `monitor.log` or the dashboard after running.

---

### `uninstall.bat`
Completely removes all monitor configuration from a NUC. Run as Administrator. Removes scheduled tasks, monitor folder, desktop shortcut, and Defender exclusion.

---

### `webhook.txt`
Plain text file containing the Google Apps Script webhook URL. Written by `install.ps1` and `monitor.ps1`. Read by `run-silent.vbs` to pass to `NucMonitor.exe`.

---

### `nuc-id.txt`
Plain text file containing the NUC's display name. Written at install time. Read by `run-silent.vbs`.

Example:
```
2/ALAND/THE-WALDEN/55
```

---

### `monitor.log`
Per-run log. Every screenshot attempt is logged with result. Auto-rotates to `monitor-archive.log` at 500KB.

Example successful run:
```
2026-05-06 10:33:47 | INFO | Run started | NUC: 2/ALAND/THE-WALDEN/55
2026-05-06 10:33:47 | INFO | Screen bounds: 1920x1080
2026-05-06 10:33:47 | INFO | Screenshot captured
2026-05-06 10:33:47 | INFO | Resized to: 1920x1080
2026-05-06 10:33:47 | INFO | Encoded JPEG | Size: 236 KB | Base64: 322300 chars
2026-05-06 10:33:47 | INFO | Posting to webhook | Payload: 314 KB
2026-05-06 10:33:55 | INFO | Webhook response: 200 OK
2026-05-06 10:33:55 | INFO | Run completed successfully
```

---

## Architecture

```
GitHub (showcase-msga/showcase)
├── NucMonitor.exe       ← Compiled binary (AMSI-safe, does all the work)
├── monitor.ps1          ← Thin wrapper (placeholders only)
├── run-silent.vbs       ← Silent launcher (reads txt files, calls exe)
├── update.ps1           ← Nightly auto-updater
├── install.ps1          ← One-time installer
├── test-screenshot.bat  ← Manual test trigger
├── uninstall.bat        ← Full removal
└── version.txt          ← Current version string

Each NUC (C:\ProgramData\showcase-monitor\)
├── NucMonitor.exe       ← Downloaded and updated automatically
├── monitor.ps1          ← Webhook URL + NUC ID baked in
├── run-silent.vbs
├── update.ps1
├── test-screenshot.bat
├── uninstall.bat
├── webhook.txt          ← Webhook URL (read by run-silent.vbs)
├── nuc-id.txt           ← NUC name (read by run-silent.vbs)
├── monitor.log          ← Per-run log (auto-rotates at 500KB)
├── update.log           ← Nightly update log
└── version.txt          ← Installed version

Google Apps Script (Web App — public access)
└── Receives POST from NucMonitor.exe
└── Decodes base64 screenshot
└── Deletes screenshots >7 days old for same NUC
└── Saves new screenshot to Google Drive

Google Drive ([03] NUC Dashboard)
└── Flat folder, all screenshots in one place
└── Named: NUC-NAME - YYYY-MM-DD HH-MM.jpg
└── Rolling 7 day retention per NUC
```

---

## Apps Script Setup

### Initial Setup

1. Go to [script.google.com](https://script.google.com)
2. Create a new project named **NUC Monitor**
3. Paste the contents of `apps-script.js` (stored separately, not in this repo)
4. Run `testDriveAccess` to verify Google Drive permissions
5. Deploy as a **Web App**:
   - Execute as: **Me**
   - Who has access: **Anyone**
6. Copy the deployment URL — this is the webhook URL used during NUC installation

> ⚠️ Use the public URL format: `https://script.google.com/macros/s/SCRIPT_ID/exec`
> Not the domain-restricted format: `https://script.google.com/a/macros/ad-group.com.au/...`

### Redeploying After Changes

1. Click **Deploy > Manage Deployments**
2. Click the pencil icon
3. Select **New version**
4. Click **Deploy**

The webhook URL stays the same. NUCs do not need updating when the Apps Script is redeployed.

---

## Installation

### Prerequisites

| Requirement | Details |
|-------------|---------|
| Admin PowerShell on the NUC | Right-click > Run as Administrator |
| NUC install commands file | `nuc-install-commands.md` |
| Internet connection on NUC | Required to pull files from GitHub |
| .NET Framework 4 | Pre-installed on Windows 7+, all NUCs have it |

### Steps

1. Open Admin PowerShell on the NUC (Windows Search > PowerShell > Right-click > Run as Administrator)
2. Find the install command in `nuc-install-commands.md` (Ctrl+F for the NUC name)
3. Copy and paste the full command block into PowerShell
4. Press Enter and wait for: `Showcase NUC Monitor installed successfully`
5. Run a test screenshot to verify (see Testing section)

### Install Command Template

```powershell
$webhook = "https://script.google.com/macros/s/SCRIPT_ID/exec"
$nucId   = "STATE/CLIENT/PROJECT/SCREEN"
iex (iwr "https://raw.githubusercontent.com/showcase-msga/showcase/main/install.ps1" -UseBasicParsing).Content
```

---

## Testing

### Manual exe test (quickest)

```powershell
& "C:\ProgramData\showcase-monitor\NucMonitor.exe" `
  "https://script.google.com/macros/s/SCRIPT_ID/exec" `
  "NUC-ID-HERE"
```

### Via VBS chain (same as scheduled task)

```powershell
cscript "C:\ProgramData\showcase-monitor\run-silent.vbs"
```

### Simulate scheduled task trigger

```powershell
Start-ScheduledTask -TaskName "Showcase NUC Monitor"
```

### Check the log

```powershell
Get-Content "C:\ProgramData\showcase-monitor\monitor.log" -Tail 20
```

---

## Auto-Update System

Every NUC runs `update.ps1` daily at 2am as SYSTEM. It checks `version.txt` on GitHub and downloads all updated files if the version has changed.

### Deploying an update to the fleet

1. Push all updated files to GitHub
2. Push `version.txt` with the new version number **last**
3. Fleet picks up the update at 2am

> ⚠️ Always push `version.txt` last. Pushing it first causes NUCs to try downloading files before they exist.

### Check update log

```powershell
Get-Content "C:\ProgramData\showcase-monitor\update.log" -Tail 10
```

### Force update on a single NUC

```powershell
& "C:\ProgramData\showcase-monitor\update.ps1"
```

---

## Adding New NUCs

### NUC Naming Convention

```
STATE_PREFIX/CLIENT/PROJECT/SCREEN-TYPE
```

| Prefix | State |
|--------|-------|
| `1` | QLD |
| `2` | NSW |
| `3` | VIC |
| `4` | QLD / Byron Bay |
| `X` | Inactive / Decommissioned |

### Steps

1. Confirm NUC name following the naming convention
2. Use the install command template with the new NUC name
3. Run on the NUC following the installation steps above
4. Add the NUC name and command to `nuc-install-commands.md` for future reference

---

## Resetting a NUC

### Using uninstall.bat (recommended)

1. Open the **Showcase Monitor** folder from the desktop shortcut
2. Right-click `uninstall.bat` and select **Run as administrator**
3. Wait for the completion message
4. Re-run the correct install command

### Manual reset via PowerShell

```powershell
Unregister-ScheduledTask -TaskName "Showcase NUC Monitor" -Confirm:$false
Unregister-ScheduledTask -TaskName "Showcase NUC Monitor Updater" -Confirm:$false
Remove-Item "C:\ProgramData\showcase-monitor" -Recurse -Force
Remove-Item ([System.Environment]::GetFolderPath('CommonDesktopDirectory') + '\Showcase Monitor.lnk') -Force
Remove-MpPreference -ExclusionPath "C:\ProgramData\showcase-monitor"
```

Then re-run the install command.

---

## Google Drive Structure

All screenshots land in a single flat folder: **[03] NUC Dashboard**

### File Naming

```
NUC-NAME - YYYY-MM-DD HH-MM.jpg
```

Examples:
```
2-ALAND-THE-WALDEN-55 - 2026-05-06 08-30.jpg
3-GOLDFIELDS-BRIGHTLY-MODEL - 2026-05-06 09-00.jpg
```

### Retention

- Screenshots older than **7 days** per NUC deleted automatically on each new upload
- Handled by Google Apps Script, not the NUC

### Daily Check Workflow

1. Open **[03] NUC Dashboard** in Google Drive
2. Sort by **Date Modified** (newest first)
3. Scan thumbnails for issues (black screen, wrong content, popup)
4. Remote into any NUC that needs attention

---

## Troubleshooting

### No screenshot in dashboard

**Step 1:** Check the log
```powershell
Get-Content "C:\ProgramData\showcase-monitor\monitor.log" -Tail 20
```
The log tells you exactly which step failed.

**Step 2:** Check internet
```powershell
Test-NetConnection google.com -Port 443
```

**Step 3:** Check Apps Script executions log at script.google.com

---

### Scheduled task not running

Open `taskschd.msc`, verify **Showcase NUC Monitor** exists with status **Ready**. If missing, re-run the install command. Confirm the task runs as `InteractiveToken` — SYSTEM context produces black screenshots.

---

### Wrong NUC name

Run `uninstall.bat` as Admin then re-run the correct install command.

---

### 401 Unauthorized

Ensure webhook URL uses the public format:
```
https://script.google.com/macros/s/SCRIPT_ID/exec
```

---

### Update not applying

Check `update.log`. Common causes: no internet at 2am, `version.txt` not pushed, or `webhook.txt`/`nuc-id.txt` missing from the NUC.

---

## Changelog

### v1.9 — May 2026
- Replaced PowerShell screenshot logic with compiled `NucMonitor.exe` (.NET 4, AMSI-safe)
- `run-silent.vbs` now reads `webhook.txt` and `nuc-id.txt` and calls `NucMonitor.exe` directly (no PowerShell in hot path)
- Webhook URL and NUC ID stored in `webhook.txt` and `nuc-id.txt`
- Full per-run logging in `monitor.log` — every step logged including screen bounds, JPEG size, webhook response code
- Log auto-rotates at 500KB to `monitor-archive.log`
- `update.ps1` now downloads `NucMonitor.exe` as part of fleet updates

### v1.6 — April 2026
- Replaced broken `Set-ScheduledTask` reconciliation with full XML task re-registration
- `update.ps1` self-refreshes on version mismatch
- One-time bootstrap in `monitor.ps1` to deploy v1.6 `update.ps1` to fleet

### v1.5 — April 2026
- Added 10-minute random delay to spread fleet uploads
- Screenshot cadence changed to every 30 minutes (was hourly)

### v1.4 — April 2026
- Added `update.ps1` auto-updater (daily at 2am)
- Version check via `version.txt` on GitHub
- Webhook URL and NUC ID preserved during updates

### v1.3 — April 2026
- Fixed black screenshot by switching scheduled task to `InteractiveToken`

### v1.2 — April 2026
- DPI-aware screenshot capture
- Added `uninstall.bat`

### v1.0-1.1 — April 2026
- Initial release
