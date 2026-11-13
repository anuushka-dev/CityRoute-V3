@echo off
REM CityRoute - local setup. Double-click this file or run it from a terminal.
setlocal
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0setup.ps1"
echo.
pause
