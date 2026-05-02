@echo off
setlocal enabledelayedexpansion

set "REPO_OWNER=missiletechradar"
set "REPO_NAME=kdupdates"
set "VERINFO_LOCAL=verinfo.txt"
set "VERINFO_SYSTEM=C:\Windows\Branding\Basebrd\verinfo.ini"
set "TEMP_DIR=%TEMP%\kodiak_update"

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
    pause
    exit /b 1
)

for /f "tokens=2 delims==" %%a in ('findstr /i "build" "%VERINFO_SOURCE%" 2^>nul') do (
    set "CURRENT_BUILD=%%a"
)

if defined CURRENT_BUILD (
    for /f %%a in ("%CURRENT_BUILD%") do set "CURRENT_BUILD=%%a"
)

if NOT "%CURRENT_BUILD%"=="1001" (
    echo [ERROR] Build %CURRENT_BUILD% is not supported.
    echo This script only supports updates for Build 1001.
    pause
    exit /b 1
)

echo [OK] Build 1001 detected.
echo/

echo Fetching update info from GitHub...
if exist "%TEMP_DIR%" rmdir /s /q "%TEMP_DIR%"
mkdir "%TEMP_DIR%"

set "PS_CMD=$r=Invoke-RestMethod 'https://api.github.com/repos/%REPO_OWNER%/%REPO_NAME%/releases/latest'; $a=($r.assets | Where-Object {$_.name -like '*.zip'} | Select-Object -First 1).browser_download_url; Write-Output \"TAG=$($r.tag_name)\"; Write-Output \"URL=$a\""

powershell -NoProfile -ExecutionPolicy Bypass -Command "%PS_CMD%" > "%TEMP_DIR%\update_info.txt" 2>&1

set "LATEST_TAG="
set "DOWNLOAD_URL="
for /f "tokens=2 delims==" %%b in ('findstr /i "TAG=" "%TEMP_DIR%\update_info.txt"') do set "LATEST_TAG=%%b"
for /f "tokens=2 delims==" %%b in ('findstr /i "URL=" "%TEMP_DIR%\update_info.txt"') do set "DOWNLOAD_URL=%%b"

if not defined LATEST_TAG (
    echo [ERROR] Failed to fetch update information.
    goto :cleanup
)

if NOT "%LATEST_TAG:~-5%"=="-1001" (
    echo [INFO] You are in the latest build.
    goto :cleanup
)

echo/
echo ========================================
echo  Starting Update Process
echo ========================================
echo/

echo Downloading update...
powershell -NoProfile -ExecutionPolicy Bypass -Command "Invoke-WebRequest -Uri '%DOWNLOAD_URL%' -OutFile '%TEMP_DIR%\update.zip' -TimeoutSec 60"

echo Extracting update...
powershell -NoProfile -ExecutionPolicy Bypass -Command "Expand-Archive -Path '%TEMP_DIR%\update.zip' -DestinationPath '%TEMP_DIR%\extracted' -Force"

set "SETUP_EXE="
for /r "%TEMP_DIR%\extracted" %%f in (setup.exe) do (if exist "%%f" set "SETUP_EXE=%%f")

if defined SETUP_EXE (
    echo Starting installer...
    echo PLEASE WAIT: Script will resume once installer is closed.
    echo/
    start /wait "" "%SETUP_EXE%"
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
