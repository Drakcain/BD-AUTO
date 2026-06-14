@echo off
setlocal
set "INSTALLER=%~dp0Install-BD-AUTO.ps1"

if not exist "%INSTALLER%" (
  echo BD-AUTO installer script was not found:
  echo %INSTALLER%
  pause
  exit /b 2
)

"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%INSTALLER%"
set "EXITCODE=%ERRORLEVEL%"

if not "%EXITCODE%"=="0" (
  echo.
  echo BD-AUTO setup failed with exit code %EXITCODE%.
  echo Review C:\Tools\BD-AUTO\logs for details.
  pause
)

exit /b %EXITCODE%
