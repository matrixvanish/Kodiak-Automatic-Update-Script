@echo off
setlocal enabledelayedexpansion

:: ============================================================
:: Kodiak Automatic Update Script
:: Fetches updates from missiletechradar/kdupdates
:: Checks version compatibility before updating
:: ============================================================

set "REPO_OWNER=missiletechradar"
set "REPO_NAME=kdupdates"
set "VERINFO_LOCAL=verinfo.txt"
set "VERINFO_SYSTEM=C:\Windows\Branding\Basebrd\verinfo.ini"
set "TEMP_DIR=%TEMP%\kodiak_update"
set "MIN_SUPPORTED_BUILD=1002"
set "MAX_SUPPORTED_BUILD=1050"

echo ========================================
echo  Kodiak Automatic Updater
echo ========================================
echo/

:: Try to read version from system location first, fall back to local file
set "VERINFO_SOURCE="
set "CURRENT_BUILD="

if exist "%VERINFO_SYSTEM%" (
    set "VERINFO_SOURCE=%VERINFO_SYSTEM%"
) else if exist "%VERINFO_LOCAL%" (
    set "VERINFO_SOURCE=%VERINFO_LOCAL%"
) else (
    echo [ERROR] No version info file found!
    echo Checked: %VERINFO_SYSTEM%
    echo Checked: %VERINFO_LOCAL%
    pause
    exit /b 1
)

echo Reading version from: %VERINFO_SOURCE%
echo/

for /f "tokens=2 delims==" %%a in ('findstr /i "build" "%VERINFO_SOURCE%" 2^>nul') do (
    set "CURRENT_BUILD=%%a"
)

if defined CURRENT_BUILD (
    for /f %%a in ("%CURRENT_BUILD%") do set "CURRENT_BUILD=%%a"
)

if not defined CURRENT_BUILD (
    echo [ERROR] Could not read build version from %VERINFO_SOURCE%!
    pause
    exit /b 1
)

echo Current Build: %CURRENT_BUILD%
echo/

:: Check version compatibility
:: Version 1001 does not support 1051+
set /a BUILD_NUM=%CURRENT_BUILD%

if %BUILD_NUM% LSS %MIN_SUPPORTED_BUILD% (
    echo [WARNING] Build %CURRENT_BUILD% is below minimum supported build (%MIN_SUPPORTED_BUILD%^).
    echo This version may not be compatible with the latest updates.
    echo/
    set "FORCE_UPDATE=1"
) else if %BUILD_NUM% GTR %MAX_SUPPORTED_BUILD% (
    echo [WARNING] Build %CURRENT_BUILD% exceeds maximum supported build (%MAX_SUPPORTED_BUILD%^).
    echo You may already be on a newer version.
    echo/
    set "SKIP_UPDATE=1"
) else (
    echo [OK] Build %CURRENT_BUILD% is within supported range.
    echo/
)

:: Fetch latest version info from GitHub
echo Fetching update info from GitHub...
echo/

:: Create temp directory
if exist "%TEMP_DIR%" rmdir /s /q "%TEMP_DIR%"
mkdir "%TEMP_DIR%"

:: Try to fetch latest release info using PowerShell
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0fetch.ps1" "%REPO_OWNER%" "%REPO_NAME%" > "%TEMP_DIR%\update_info.txt" 2>&1

:: Parse the response
set "LATEST_VERSION="
set "LATEST_BUILD="
set "DOWNLOAD_URL="

for /f "delims=" %%a in ('findstr /i "LATEST_VERSION=" "%TEMP_DIR%\update_info.txt" 2^>nul') do (
    for /f "tokens=2 delims==" %%b in ("%%a") do set "LATEST_VERSION=%%b"
)

for /f "delims=" %%a in ('findstr /i "LATEST_BUILD=" "%TEMP_DIR%\update_info.txt" 2^>nul') do (
    for /f "tokens=2 delims==" %%b in ("%%a") do set "LATEST_BUILD=%%b"
)

for /f "delims=" %%a in ('findstr /i "DOWNLOAD_URL=" "%TEMP_DIR%\update_info.txt" 2^>nul') do (
    for /f "tokens=2 delims==" %%b in ("%%a") do set "DOWNLOAD_URL=%%b"
)

:: Check if fetch was successful
if not defined LATEST_VERSION (
    echo [ERROR] Failed to fetch update information from GitHub.
    echo Please check your internet connection and try again.
    goto :cleanup
)

echo Latest Version: %LATEST_VERSION% (Build: %LATEST_BUILD%^)
echo/

:: Compare versions
if defined SKIP_UPDATE (
    echo [INFO] Skipping update - you appear to be on a newer version.
    goto :cleanup
)

if defined FORCE_UPDATE (
    echo [INFO] Force update recommended due to version incompatibility.
    goto :proceed_update
)

if "%CURRENT_BUILD%"=="%LATEST_BUILD%" (
    echo [INFO] You are already on the latest version (%CURRENT_BUILD%^).
    echo No update needed.
    goto :cleanup
)

if %BUILD_NUM% LSS %LATEST_BUILD% (
    echo [UPDATE AVAILABLE] New version %LATEST_BUILD% is available (current: %CURRENT_BUILD%^).
    goto :proceed_update
) else (
    echo [INFO] Your current version (%CURRENT_BUILD%^) is newer than the latest release (%LATEST_BUILD%^).
    goto :cleanup
)

:proceed_update
echo/
echo ========================================
echo  Starting Update Process
echo ========================================
echo/

if not defined DOWNLOAD_URL (
    echo [ERROR] No download URL available. Cannot proceed with update.
    goto :cleanup
)

echo Downloading update from GitHub...
echo/

:: Download the update
powershell -NoProfile -ExecutionPolicy Bypass -Command "Invoke-WebRequest -Uri '%DOWNLOAD_URL%' -OutFile '%TEMP_DIR%\update.zip' -TimeoutSec 60"

if errorlevel 1 (
    echo [ERROR] Download failed!
    goto :cleanup
)

echo Download complete!
echo/
echo Extracting update package...
echo/

:: Extract the zip file using PowerShell with proper handling
powershell -NoProfile -ExecutionPolicy Bypass -Command "$zipPath = '%TEMP_DIR%\update.zip'; $destPath = '%TEMP_DIR%\extracted'; if (Test-Path $destPath) { Remove-Item $destPath -Recurse -Force }; Expand-Archive -Path $zipPath -DestinationPath $destPath -Force"

if errorlevel 1 (
    echo [ERROR] Extraction failed!
    goto :cleanup
)

echo Extraction complete!
echo/

:: Find setup.exe in the extracted folder (may be in subdirectory)
set "SETUP_EXE="
for /r "%TEMP_DIR%\extracted" %%f in (setup.exe) do (
    if exist "%%f" (
        set "SETUP_EXE=%%f"
        goto :found_setup
    )
)

:found_setup
if not defined SETUP_EXE (
    echo [ERROR] setup.exe not found in update package!
    dir "%TEMP_DIR%\extracted" /s /b 2>nul
    goto :cleanup
)

:: Resolve short path to long path
for %%i in ("%SETUP_EXE%") do set "SETUP_EXE=%%~fi"

echo Found installer: %SETUP_EXE%
echo/

:: Verify file exists before launching
if not exist "%SETUP_EXE%" (
    echo [ERROR] Installer file does not exist at: %SETUP_EXE%
    dir "%TEMP_DIR%\extracted" /s /b 2>nul
    goto :cleanup
)
echo ========================================
echo  Running Installer
echo ========================================
echo/
echo Starting setup.exe... Please follow the installer prompts.
echo/

:: Run the installer
start "" "%SETUP_EXE%"

echo Installer launched! The installation is running in a separate window.
echo Leaving extracted files in place for the installer to use.
echo Temp folder: %TEMP_DIR%
echo/
echo ========================================
echo  Update Check Complete
echo ========================================
pause
exit /b 0
