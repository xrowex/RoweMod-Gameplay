@echo off
REM Join a RoweMod multiplayer host. Example: mp_join.cmd 192.168.1.10
cd /d "%~dp0\.."
if "%~1"=="" (
  echo Usage: mp_join.cmd ^<host-lan-ip^> [--name YourName]
  exit /b 1
)
python tools\rowemod_mp.py join --host %*
