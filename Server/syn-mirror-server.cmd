@echo off
rem SYN Mirror, the server, on Windows: a double click starts the script beside, its menu in this window.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0syn-mirror-server.ps1" %*
