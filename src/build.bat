@echo off
rem Builds NucMonitor.exe from NucMonitor.cs with the .NET Framework 4 compiler that ships with Windows.
rem Output goes to the repo root, where install.ps1 and update.ps1 download it from.
setlocal
set CSC=%WINDIR%\Microsoft.NET\Framework64\v4.0.30319\csc.exe
if not exist "%CSC%" set CSC=%WINDIR%\Microsoft.NET\Framework\v4.0.30319\csc.exe
"%CSC%" /nologo /codepage:65001 /target:winexe /optimize+ /platform:anycpu ^
  /out:"%~dp0..\NucMonitor.exe" ^
  /reference:System.dll /reference:System.Core.dll /reference:System.Drawing.dll /reference:System.Windows.Forms.dll ^
  "%~dp0NucMonitor.cs"
if errorlevel 1 (echo BUILD FAILED & exit /b 1)
echo Built NucMonitor.exe
