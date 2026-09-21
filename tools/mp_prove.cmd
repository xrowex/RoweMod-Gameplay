@echo off
cd /d "%~dp0\.."
python tools\mp_prove.py %*
exit /b %ERRORLEVEL%
