@echo off
setlocal
REM Launch the PowerShell rebuild script with Bypass policy and keep the window open.
REM Use this if right-click "Run with PowerShell" flashes closed (policy block / early error).
cd /d "%~dp0"
set "PS_EXE=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
if not exist "%PS_EXE%" set "PS_EXE=powershell.exe"
"%PS_EXE%" -NoProfile -ExecutionPolicy Bypass -NoExit -File "%~dp0_rebuild_index_links.ps1" %*
endlocal
