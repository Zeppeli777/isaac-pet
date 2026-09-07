@echo off
REM Build the Windows (WPF) port of Isaac Pet.
REM Prefers the repo-local portable SDK at .dotnet-sdk, falls back to system dotnet.
setlocal
set "REPO=%~dp0..\.."
if exist "%REPO%\.dotnet-sdk\dotnet.exe" (
    set "DOTNET=%REPO%\.dotnet-sdk\dotnet.exe"
    set "DOTNET_MULTILEVEL_LOOKUP=0"
) else (
    set "DOTNET=dotnet"
)
set "DOTNET_CLI_TELEMETRY_OPTOUT=1"
cd /d "%REPO%\Windows\IsaacPet.Windows"
"%DOTNET%" build -c Release %*
endlocal
