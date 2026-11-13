@echo off
REM CityRoute - build and run the demo in Docker.
setlocal
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0run-docker.ps1"
echo.
pause
