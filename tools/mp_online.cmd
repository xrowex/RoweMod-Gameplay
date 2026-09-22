@echo off
cd /d "%~dp0"
if exist "%~dp0deps\RoweModOnline.exe" (
    start "" "%~dp0deps\RoweModOnline.exe" %*
) else (
    pythonw "%~dp0mp_online.py" %*
)
