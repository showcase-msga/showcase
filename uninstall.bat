@echo off
echo Removing Showcase NUC Monitor...

:: Remove scheduled tasks
powershell -ExecutionPolicy Bypass -Command "Unregister-ScheduledTask -TaskName 'Showcase NUC Monitor' -Confirm:$false -ErrorAction SilentlyContinue"
powershell -ExecutionPolicy Bypass -Command "Unregister-ScheduledTask -TaskName 'Showcase NUC Monitor Updater' -Confirm:$false -ErrorAction SilentlyContinue"

:: Remove monitor folder
powershell -ExecutionPolicy Bypass -Command "Remove-Item 'C:\ProgramData\showcase-monitor' -Recurse -Force -ErrorAction SilentlyContinue"

:: Remove desktop shortcut
powershell -ExecutionPolicy Bypass -Command "Remove-Item ([System.Environment]::GetFolderPath('CommonDesktopDirectory') + '\Showcase Monitor.lnk') -Force -ErrorAction SilentlyContinue"

:: Remove Defender exclusion
powershell -ExecutionPolicy Bypass -Command "Remove-MpPreference -ExclusionPath 'C:\ProgramData\showcase-monitor' -ErrorAction SilentlyContinue"

echo Done. All Showcase NUC Monitor files and tasks have been removed.
echo You can now re-run the install command to start fresh.
pause
