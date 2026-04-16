' ============================================================
' run-silent.vbs - Launches monitor.ps1 silently
' ============================================================
Dim shell
Set shell = CreateObject("WScript.Shell")
shell.Run "powershell.exe -ExecutionPolicy Bypass -WindowStyle Hidden -NoProfile -File ""C:\ProgramData\showcase-monitor\monitor.ps1""", 0, False
Set shell = Nothing
