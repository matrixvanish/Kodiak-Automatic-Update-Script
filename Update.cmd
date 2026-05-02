@echo off
setlocal enabledelayedexpansion

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

echo Fetching update info from GitHub...
echo/

if exist "%TEMP_DIR%" rmdir /s /q "%TEMP_DIR%"
mkdir "%TEMP_DIR%"

set "PS_CMD=$r=Invoke-RestMethod 'https://api.github.com/repos/%REPO_OWNER%/%REPO_NAME%/releases/latest'; $b=($r.body -split '`' | Select-String 'Build:').ToString().Split(':')[-1].Trim(); $a=($r.assets | Where-Object {$_.name -like '*.zip'} | Select-Object -First 1).browser_download_url; Write-Output \"LATEST_VERSION=$($r.tag_name)\"; Write-Output \"LATEST_BUILD=$b\"; Write-Output \"DOWNLOAD_URL=$a\""

powershell -NoProfile -ExecutionPolicy Bypass -Command "%PS_CMD%" > "%TEMP_DIR%\update_info.txt" 2>&1

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

echo Downloading update...
powershell -NoProfile -ExecutionPolicy Bypass -Command "Invoke-WebRequest -Uri '%DOWNLOAD_URL%' -OutFile '%TEMP_DIR%\update.zip' -TimeoutSec 60"

echo Extracting update...
powershell -NoProfile -ExecutionPolicy Bypass -Command "Expand-Archive -Path '%TEMP_DIR%\update.zip' -DestinationPath '%TEMP_DIR%\extracted' -Force"

set "SETUP_EXE="
for /r "%TEMP_DIR%\extracted" %%f in (setup.exe) do (
    if exist "%%f" (
        set "SETUP_EXE=%%f"
        goto :launch
    )
)

:launch
if defined SETUP_EXE (
    echo Starting installer...
    echo PLEASE WAIT: Script will resume once installer is closed.
    echo/
    :: Wait for the process to finish
    start /wait "" "%SETUP_EXE%"
    echo/
    echo Installer closed.
) else (
    echo [ERROR] setup.exe not found in update package!
)

:cleanup
echo Cleaning up temporary files...
if exist "%TEMP_DIR%" rmdir /s /q "%TEMP_DIR%"
echo/
echo ========================================
echo  Update Process Finished
echo ========================================
pause
exit /b 0
