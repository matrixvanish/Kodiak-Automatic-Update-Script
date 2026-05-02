# Kodiak Automatic Updater

The **Kodiak Automatic Updater** is a batch script designed to streamline the process of updating local software by fetching the latest releases from a GitHub repository. It includes built-in version compatibility checks to ensure the system is within the supported build range before proceeding.

## Features

- **Automated Version Detection**: Scans both system and local directories for current version information (`verinfo.ini` or `verinfo.txt`).
- **Compatibility Guardrails**: Prevents updates on builds outside the supported range (Minimum: 1002, Maximum: 1050).
- **GitHub Integration**: Fetches real-time update metadata (version, build, and download URL) using a helper PowerShell script.
- **PowerShell-Powered Downloads**: Utilizes `Invoke-WebRequest` and `Expand-Archive` for reliable file handling and extraction.
- **Automatic Installer Execution**: Locates and launches `setup.exe` from extracted update packages automatically.

## Prerequisites

1. **PowerShell**: Required for fetching metadata and handling zip archives.
2. **fetch.ps1**: A helper PowerShell script must be located in the same directory as `Update.cmd` to handle GitHub API communication.
3. **Internet Access**: Required to connect to the `missiletechradar/kdupdates` repository.

## Installation & Usage

1. Place `Update.cmd` and `fetch.ps1` in your desired application folder.
2. Ensure you have a `verinfo.txt` file in the local folder (or `verinfo.ini` at `C:\Windows\Branding\Basebrd\`) containing a `build=XXXX` entry.
3. Run `Update.cmd` as an Administrator to ensure it has the necessary permissions to read system files and create temporary directories.

## Configuration

The following variables can be adjusted within the script for different environments:

| Variable | Description | Default Value |
| :--- | :--- | :--- |
| `REPO_OWNER` | GitHub Username/Org | `missiletechradar` |
| `REPO_NAME` | GitHub Repository Name | `kdupdates` |
| `MIN_SUPPORTED_BUILD` | Minimum allowed build version | `1002` |
| `MAX_SUPPORTED_BUILD` | Maximum allowed build version | `1050` |

## Error Handling

- **No Version Info**: The script will exit if it cannot find a version source to determine the current build.
- **Incompatible Build**: If the build is too old (< 1002), a warning is issued; if too new (> 1050), the update is skipped to prevent downgrading.
- **Network Issues**: Displays an error if GitHub metadata cannot be retrieved.
- **Missing Installer**: Alerts the user if `setup.exe` is not found within the downloaded ZIP package.

## Technical Details

- **Temporary Files**: Updates are downloaded to `%TEMP%\kodiak_update`.
- **System Path**: Checks `C:\Windows\Branding\Basebrd\verinfo.ini` for enterprise-level version tracking.
