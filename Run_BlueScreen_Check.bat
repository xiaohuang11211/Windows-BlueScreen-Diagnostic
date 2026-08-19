@echo off
setlocal
set "PROJECT_DIR=%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%PROJECT_DIR%src\BlueScreen_Check.ps1"
exit /b %ERRORLEVEL%
