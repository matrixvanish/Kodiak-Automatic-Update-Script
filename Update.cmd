@echo off
setlocal enabledelayedexpansion

:: ============================================================
:: Kodiak Automatic Update Script
:: Consolidated Version: fetch.ps1 logic included inline
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

:: --- Version Detection ---
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

:: --- Compatibility Check ---
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

:: --- Integrated Fetch Logic ---
echo Fetching update info from GitHub...
echo/

if exist "%TEMP_DIR%" rmdir /s /q "%TEMP_DIR%"
mkdir "%TEMP_DIR%"

:: Create an inline PowerShell script to replace fetch.ps1
(
echo $repoOwner = "%REPO_OWNER%"
echo $repoName = "%REPO_NAME%"
echo try {
echo     $url = "https://api.github.com/repos/$repoOwner/$repoName/releases/latest"
echo     $response = Invoke-RestMethod -Uri $url -Method Get -ErrorAction Stop
echo     $version = $response.tag_name
echo     $build = ($response.body -split '`' ^| Select-String "Build:").ToString().Split(':')[-1].Trim()
echo     $asset = $response.assets ^| Where-Object { $_.name -like "*.zip" } ^| Select-Object -First 1
echo     Write-Output "LATEST_VERSION=$version"
echo     Write-Output "LATEST_BUILD=$build"
echo     Write-Output "DOWNLOAD_URL=$($asset.browser_download_url)"
echo } catch { exit 1 }
) > "%TEMP_DIR%\fetch_logic.ps1"

powershell -NoProfile -ExecutionPolicy Bypass -File "%TEMP_DIR%\fetch_logic.ps1" > "%TEMP_DIR%\update_info.txt" 2>&1

:: Parse metadata
set "LATEST_VERSION="
set "LATEST_BUILD="
set "DOWNLOAD_URL="

for /f "tokens=2 delims==" %%b in ('findstr /i "LATEST_VERSION=" "%TEMP_DIR%\update_info.txt" 2^>nul') do set "LATEST_VERSION=%%b"
for /f "tokens=2 delims==" %%b in ('findstr /i "LATEST_BUILD=" "%TEMP_DIR%\update_info.txt" 2^>nul') do set "LATEST_BUILD=%%b"
for /f "tokens=2 delims==" %%b in ('findstr /i "DOWNLOAD_URL=" "%TEMP_DIR%\update_info.txt" 2^>nul') do set "DOWNLOAD_URL=%%b"

if not defined LATEST_VERSION (
    echo [ERROR] Failed to fetch update information from GitHub.
    goto :cleanup
)

echo Latest Version: %LATEST_VERSION% (Build: %LATEST_BUILD%^)
echo/

:: --- Update Logic ---
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

:proceed_update
echo/
echo ========================================
echo  Starting Update Process
echo ========================================
echo/

if not defined DOWNLOAD_URL (
    echo [ERROR] No download URL available.
    goto :cleanup
)

echo Downloading update from GitHub...
powershell -NoProfile -ExecutionPolicy Bypass -Command "Invoke-WebRequest -Uri '%DOWNLOAD_URL%' -OutFile '%TEMP_DIR%\update.zip' -TimeoutSec 60"

if errorlevel 1 (
    echo [ERROR] Download failed!
    goto :cleanup
)

echo Extracting update package...
powershell -NoProfile -ExecutionPolicy Bypass -Command "Expand-Archive -Path '%TEMP_DIR%\update.zip' -DestinationPath '%TEMP_DIR%\extracted' -Force"

:: Find and run setup.exe
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
    goto :cleanup
)

echo Starting setup.exe...
start "" "%SETUP_EXE%"

:cleanup
if exist "%TEMP_DIR%\fetch_logic.ps1" del "%TEMP_DIR%\fetch_logic.ps1"
echo/
echo ========================================
echo  Update Check Complete
echo ========================================
pause
exit /b 0
