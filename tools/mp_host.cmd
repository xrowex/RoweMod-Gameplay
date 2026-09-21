@echo off
REM Host a RoweMod multiplayer LAN session (run before or alongside the game).
cd /d "%~dp0\.."
python tools\rowemod_mp.py host %*
