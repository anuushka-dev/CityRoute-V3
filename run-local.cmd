@echo off
REM CityRoute - start the local demo (API on 8001, demo on 5173).
setlocal
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0run-local.ps1"
echo.
pause
