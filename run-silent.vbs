' ============================================================
' run-silent.vbs (v1.9)
' Reads webhook URL and NUC ID from text files.
' Calls NucMonitor.exe directly - no PowerShell, no AMSI.
' ============================================================
Dim monitorDir, webhookUrl, nucId, shell

monitorDir = "C:\ProgramData\showcase-monitor"

' Read webhook.txt
Dim fso, f
Set fso = CreateObject("Scripting.FileSystemObject")
Set f = fso.OpenTextFile(monitorDir & "\webhook.txt", 1)
webhookUrl = Trim(f.ReadAll())
f.Close()

' Read nuc-id.txt
Set f = fso.OpenTextFile(monitorDir & "\nuc-id.txt", 1)
nucId = Trim(f.ReadAll())
f.Close()

' Run exe silently
Set shell = CreateObject("WScript.Shell")
shell.Run """" & monitorDir & "\NucMonitor.exe"" """ & webhookUrl & """ """ & nucId & """", 0, False

Set shell = Nothing
Set fso = Nothing
