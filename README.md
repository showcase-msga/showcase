# Showcase NUC Monitor v1.5

A lightweight, silent monitoring system for the AD Group Showcase NUC fleet. Each NUC automatically captures a screenshot every hour between 8:30am and 5:00pm and uploads it to a shared Google Drive folder for remote visual verification.

---

## Table of Contents

- [Overview](#overview)
- [How It Works](#how-it-works)
- [File Breakdown](#file-breakdown)
- [Architecture](#architecture)
- [Apps Script Setup](#apps-script-setup)
- [Installation](#installation)
- [Deployment](#deployment)
- [Adding New NUCs](#adding-new-nucs)
- [Resetting a NUC](#resetting-a-nuc)
- [Updating Files](#updating-files)
- [Google Drive Structure](#google-drive-structure)
- [Troubleshooting](#troubleshooting)
- [Changelog](#changelog)

---

## Overview

The Showcase NUC fleet runs Chrome kiosk displays across display suites nationally. Previously, checking each NUC required manually remoting in via Chrome Remote Desktop or TeamViewer one by one — a slow and unscalable process across 200+ machines.

The NUC Monitor solves this by:

- Running silently in the background on each NUC with zero user-facing popups or notifications
- Taking a screenshot every 30 minutes from 8:30am to 5:00pm automatically, with a random 0-10 minute delay on each trigger to spread fleet load
- Capturing the full display at native resolution using DPI-aware capture — works on all display types including LEDs, projectors and standard TVs
- Running in the logged-in user's interactive session so the actual visible kiosk screen is always captured
- Embedding a black header bar on each screenshot showing the NUC ID, timestamp, and a list of visible windows for quick diagnostic context
- Uploading each screenshot to a central Google Drive folder named by NUC and timestamp
- Automatically cleaning up screenshots older than 7 days to keep the folder manageable

The result is a single Google Drive folder your team can open each morning to visually verify all NUCs at a glance, only remoting in when something looks wrong.

---

## How It Works

```
NUC (Task Scheduler — InteractiveToken, logged-in user session)
    └── Triggers run-silent.vbs every hour (8:30am–5:00pm)
            └── Launches monitor.ps1 silently (no window, no popup)
                    └── Sets DPI awareness for accurate capture
                    └── Reads true screen dimensions from GPU via GetDeviceCaps
                    └── Takes full screenshot at native resolution
                    └── Reads NUC name from nuc-id.txt
                    └── Converts screenshot to base64 JPEG at 70% quality
                    └── POSTs payload to Google Apps Script webhook
                            └── Decodes image
                            └── Deletes screenshots older than 7 days for this NUC
                            └── Saves new screenshot to Google Drive
```

### Why InteractiveToken Matters

The scheduled task runs using `InteractiveToken` which means it executes in the same desktop session as the logged-in user. This is critical because:

- Running as `SYSTEM` has no desktop session — screenshots come out black
- `InteractiveToken` sees exactly what is on screen, the same as manually running the bat file
- The kiosk display, Chrome window and all visible content is captured correctly

### Schedule

| Time | Screenshot |
|------|-----------|
| 8:30am | ✓ |
| 9:30am | ✓ |
| 10:30am | ✓ |
| 11:30am | ✓ |
| 12:30pm | ✓ |
| 1:30pm | ✓ |
| 2:30pm | ✓ |
| 3:30pm | ✓ |
| 4:30pm | ✓ |

---

## File Breakdown

### `install.ps1`
The master installer. Runs in memory via the install command — never stored on the NUC itself. It:
- Sets PowerShell execution policy to Bypass
- Creates `C:\ProgramData\showcase-monitor\`
- Downloads `monitor.ps1` from GitHub and injects the webhook URL and NUC name
- Downloads `run-silent.vbs`, `test-screenshot.bat` and `reset.bat`
- Writes `nuc-id.txt` with the NUC name
- Adds a Windows Defender exclusion for the monitor folder
- Creates a **Showcase Monitor** desktop shortcut to the folder
- Registers the Windows Scheduled Task using `InteractiveToken` so it runs in the user's desktop session

---

### `monitor.ps1`
The core monitoring script. Runs silently every hour via the scheduled task. It:
- Uses `SetProcessDPIAware` and `GetDeviceCaps` to read true GPU pixel dimensions
- Captures the full screen at native resolution regardless of DPI scaling
- Works correctly on all display types: LEDs, projectors, standard TVs, touchscreens
- Compresses the screenshot to JPEG at 70% quality
- POSTs a JSON payload (NUC name + base64 image + timestamp) to the Apps Script webhook
- Cleans up the temporary file after sending

The webhook URL and NUC name are injected at install time. The GitHub version uses placeholders (`WEBHOOK_URL_PLACEHOLDER`, `NUCID_PLACEHOLDER`).

---

### `run-silent.vbs`
Launches `monitor.ps1` via PowerShell with zero visible window. Runs without the `-NonInteractive` flag so it can access the logged-in user's desktop session and capture what is actually on screen.

---

### `test-screenshot.bat`
Manually triggers a screenshot for testing or verification. Double-click it on the NUC. It:
- Closes immediately (no lingering window on screen)
- Waits 5 seconds silently in background (gives you time to navigate away)
- Fires the screenshot silently
- Exits cleanly

Check Google Drive approximately 60 seconds after running it.

---

### `reset.bat`
Completely removes all monitor configurations from the NUC. Run as Administrator. It removes:
- The `Showcase NUC Monitor` scheduled task
- The entire `C:\ProgramData\showcase-monitor\` folder and all contents
- The **Showcase Monitor** desktop shortcut
- The Windows Defender exclusion

After running, re-run the install command to start fresh.

---

### `nuc-id.txt`
Plain text file containing the NUC's display name. Written by `install.ps1` at install time. Used as the filename prefix in Google Drive.

Example:
```
2/ALAND/THE-WALDEN/55
```

---

## Architecture

```
GitHub (showcase-msga/showcase)
├── install.ps1          ← Master installer (no sensitive data)
├── monitor.ps1          ← Screenshot script (placeholders only)
├── run-silent.vbs       ← Silent launcher (InteractiveToken compatible)
├── test-screenshot.bat  ← Manual test trigger (5s delay, auto-close)
└── reset.bat            ← Full uninstall / reset

Each NUC (C:\ProgramData\showcase-monitor\)
├── monitor.ps1          ← Webhook URL + NUC name baked in
├── run-silent.vbs
├── test-screenshot.bat
├── reset.bat
└── nuc-id.txt           ← Unique NUC name

Google Apps Script (Web App — public access)
└── Receives POST from NUCs
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

### Steps

**1. Open Admin PowerShell on the NUC**

Windows Search > PowerShell > Right-click > Run as Administrator

**2. Find the install command**

Open `nuc-install-commands.md`, search (Ctrl+F) for the NUC name, copy the command block below it.

**3. Paste and run**

Right-click in PowerShell to paste, press Enter, wait ~30 seconds.

**4. Confirm success**

```
Showcase NUC Monitor installed successfully.
NUC ID: [NUC NAME]
Folder: C:\ProgramData\showcase-monitor
```

**5. Test**

Double-click `test-screenshot.bat` from the **Showcase Monitor** desktop shortcut, wait 60 seconds, check Google Drive for the screenshot.

**6. Verify scheduled task**

`Win + R` > `taskschd.msc` > Confirm **Showcase NUC Monitor** exists with status **Ready**

---

## Deployment

### Install Command Format

```powershell
powershell -ExecutionPolicy Bypass -Command "& {`$nucId='NUC/NAME/HERE'; `$webhook='WEBHOOK_URL'; Invoke-Expression (Invoke-WebRequest 'GITHUB_RAW_URL/install.ps1' -UseBasicParsing).Content}"
```

> Webhook URL and GitHub URL intentionally omitted. Refer to `nuc-install-commands.md` for full commands.

### Files Deployed to Each NUC

| File | Location | Purpose |
|------|----------|---------|
| `monitor.ps1` | `C:\ProgramData\showcase-monitor\` | Core screenshot script |
| `run-silent.vbs` | `C:\ProgramData\showcase-monitor\` | Silent launcher |
| `test-screenshot.bat` | `C:\ProgramData\showcase-monitor\` | Manual test trigger |
| `reset.bat` | `C:\ProgramData\showcase-monitor\` | Full uninstall / reset |
| `nuc-id.txt` | `C:\ProgramData\showcase-monitor\` | NUC identity file |

---

## Adding New NUCs

No files need to be updated. Use the install command template with the new NUC name.

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

1. Confirm the NUC name following the naming convention
2. Use the install command template from `nuc-install-commands.md`
3. Replace `NUC/NAME/HERE` with the new NUC name
4. Run on the NUC following the installation steps above
5. Add the new NUC name to `nuc-install-commands.md` for future reference

> ⚠️ Use the exact NUC name including slashes, spaces and brackets.

---

## Resetting a NUC

Use `reset.bat` to completely remove all monitor configurations and start fresh. Useful when a NUC has the wrong name, a broken install, or needs a script update.

### Using reset.bat (Recommended)

1. Open the **Showcase Monitor** folder from the desktop shortcut
2. Right-click `reset.bat` and select **Run as administrator**
3. Wait for the completion message
4. Re-run the correct install command from `nuc-install-commands.md`

### Manual Reset via PowerShell

```powershell
Unregister-ScheduledTask -TaskName "Showcase NUC Monitor" -Confirm:$false
Remove-Item "C:\ProgramData\showcase-monitor" -Recurse -Force
Remove-Item ([System.Environment]::GetFolderPath('CommonDesktopDirectory') + '\Showcase Monitor.lnk') -Force
Remove-MpPreference -ExclusionPath "C:\ProgramData\showcase-monitor"
```

Then re-run the install command.

---

## Updating Files

### Updating Scripts on GitHub

1. Edit the file locally
2. Upload to GitHub (Add file > Upload files > Commit changes)
3. All future installs automatically use the updated version

### Pushing Updates to Already-Installed NUCs

Re-run the install command on each NUC. It overwrites all files with the latest from GitHub and recreates the scheduled task. There is no bulk update mechanism — each NUC must be updated individually via remote access.

---

## Google Drive Structure

All screenshots land in a single flat folder: **[03] NUC Dashboard**

### File Naming

```
NUC-NAME - YYYY-MM-DD HH-MM.jpg
```

Examples:
```
2-ALAND-THE-WALDEN-55 - 2026-04-15 08-30.jpg
3-GOLDFIELDS-BRIGHTLY-MODEL (HEADLESS) - 2026-04-15 09-30.jpg
4-SHERPA-SYMPHONY-68 - 2026-04-15 14-30.jpg
```

### Retention

- Screenshots older than **7 days** per NUC deleted automatically on each new upload
- Handled by Google Apps Script, not the NUC
- Approximately **9 screenshots per NUC per day**

### Daily Check Workflow

1. Open **[03] NUC Dashboard** in Google Drive
2. Sort by **Date Modified** (newest first)
3. Scan thumbnails for issues (popup, black screen, wrong content)
4. Remote into any NUC that needs attention

---

## Troubleshooting

### Screenshots are all black

**Cause:** Scheduled task was running as SYSTEM with no desktop session

**Fix:** Re-run the install command to get the updated `install.ps1` which uses `InteractiveToken`. The task now runs in the logged-in user's session.

---

### Script blocked by antivirus

**Symptom:** `ScriptContainsMaliciousContent` error

**Fix:**
```powershell
Add-MpPreference -ExclusionPath "C:\ProgramData\showcase-monitor"
```
Then re-run the install command.

---

### Screenshot shows partial screen

**Cause:** DPI scaling mismatch on older install

**Fix:** Re-run the install command to pull the latest `monitor.ps1` with DPI-aware capture.

---

### No screenshot in Drive after test

**Check 1:** Internet connection
```powershell
Test-NetConnection google.com -Port 443
```

**Check 2:** Run script directly
```powershell
powershell -ExecutionPolicy Bypass -NoProfile -File "C:\ProgramData\showcase-monitor\monitor.ps1"
```

**Check 3:** Check Apps Script Executions log at script.google.com

---

### Wrong NUC name in filename

**Fix:** Run `reset.bat` as Admin then re-run the correct install command.

---

### Scheduled task not running

**Fix:** Open `taskschd.msc`, verify **Showcase NUC Monitor** exists with status **Ready**. If missing, re-run the install command.

---

### 401 Unauthorized

**Fix:** Ensure webhook URL uses:
```
https://script.google.com/macros/s/SCRIPT_ID/exec
```
Run `reset.bat` and reinstall with the correct URL.

---

## Changelog

### v1.5 — April 2026
- Added 10-minute random delay to screenshot scheduled task, spreading fleet uploads across a 10-minute window to eliminate Apps Script concurrency rejections during peak bursts
- `update.ps1` now reconciles the random delay on every run, so existing NUCs pick up the fix at the next nightly auto-update without needing reinstall
- `monitor.ps1` now prepends a black header bar to every screenshot showing NUC ID, timestamp, and the list of visible windows (process name + window title) for quick diagnostic context
- `install.ps1` task XML updated with `<RandomDelay>PT10M</RandomDelay>` for new installs
- Apps Script simplified: Archive folder logic removed, Dashboard folder now the single source of truth (latest screenshot per NUC)
- Documentation updated to reflect 30-minute cadence (was incorrectly documented as hourly in earlier versions)

### v1.4 — April 2026
- Added `update.ps1` — silent auto-updater runs daily at 2am
- Version check via `version.txt` on GitHub, updates only if version differs
- Webhook URL and NUC ID preserved automatically during updates
- All update activity logged to `update.log` with timestamp and version
- Renamed `reset.bat` to `uninstall.bat`
- `uninstall.bat` now also removes the updater scheduled task
- `install.ps1` now registers two scheduled tasks: screenshot and updater
- `version.txt` written to NUC folder at install time

### v1.3 — April 2026
- Fixed black screenshot issue by changing scheduled task from SYSTEM to InteractiveToken
- Task now runs in the logged-in user's desktop session, capturing the actual visible screen
- Removed `-NonInteractive` flag from `run-silent.vbs` to allow desktop session access
- Added `reset.bat` to the list of files downloaded by `install.ps1`

### v1.2 — April 2026
- Fixed screenshot capture using DPI-aware `GetDeviceCaps` method
- Now correctly captures full screen on all display types (LED, projector, TV, touchscreen)
- Added `reset.bat` for full uninstall and clean reinstall
- `test-screenshot.bat` now closes immediately and waits 5 seconds before firing

### v1.1 — April 2026
- Added `test-screenshot.bat` for manual screenshot testing
- Fixed `test-screenshot.bat` to run silently with no visible window

### v1.0 — April 2026
- Initial release
- Silent screenshot capture every hour 8:30am–5:00pm
- Google Drive upload via Apps Script webhook
- 7 day rolling retention per NUC
- Single command deployment from GitHub
- Windows Defender exclusion added automatically
- Desktop shortcut created on install
- 251 NUCs supported across NSW, VIC, QLD
