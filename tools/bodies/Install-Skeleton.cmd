@echo off
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Install-Skeleton.ps1" %*
if errorlevel 1 echo Installation failed. See the error above.
pause
