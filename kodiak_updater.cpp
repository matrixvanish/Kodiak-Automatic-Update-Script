#define _CRT_SECURE_NO_WARNINGS
#include <windows.h>
#include <urlmon.h>
#include <shlwapi.h>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <regex>
#include <sstream>
#include <string>
#include <vector>

#pragma comment(lib, "urlmon.lib")
#pragma comment(lib, "shlwapi.lib")

namespace fs = std::filesystem;

static const std::string REPO_OWNER = "missiletechradar";
static const std::string REPO_NAME = "kdupdates";
static const fs::path VERINFO_LOCAL = "verinfo.txt";
static const fs::path VERINFO_SYSTEM = "C:\\Windows\\Branding\\Basebrd\\verinfo.ini";
static const int SUPPORTED_BUILDS[] = {1001, 1051};

void pause_and_exit(int code) {
    std::cout << "\nPress Enter to exit...";
    std::cin.get();
    ExitProcess(code);
}

void print_banner() {
    std::cout << "========================================\n";
    std::cout << "Kodiak Automatic Updater\n";
    std::cout << "========================================\n\n";
}

bool is_supported_build(int build) {
    for (int b : SUPPORTED_BUILDS) {
        if (b == build) return true;
    }
    return false;
}

fs::path get_temp_dir() {
    char tempPath[MAX_PATH];
    DWORD len = GetTempPathA(MAX_PATH, tempPath);
    if (len == 0 || len > MAX_PATH) {
        return fs::temp_directory_path() / "kodiak_update";
    }
    return fs::path(tempPath) / "kodiak_update";
}

fs::path find_version_source() {
    if (fs::exists(VERINFO_SYSTEM)) return VERINFO_SYSTEM;
    if (fs::exists(VERINFO_LOCAL)) return VERINFO_LOCAL;

    std::cout << "[ERROR] No version info file found!\n";
    std::cout << "Checked: " << VERINFO_SYSTEM.string() << "\n";
    std::cout << "Checked: " << VERINFO_LOCAL.string() << "\n";
    pause_and_exit(1);
    return {};
}

int extract_first_int(const std::string& s) {
    std::regex re("(\\d+)");
    std::smatch m;
    if (std::regex_search(s, m, re)) {
        return std::stoi(m[1].str());
    }
    return -1;
}

int extract_build(const fs::path& path) {
    std::ifstream file(path);
    if (!file) {
        std::cout << "[ERROR] Could not open version file: " << path.string() << "\n";
        pause_and_exit(1);
    }

    std::string line;
    while (std::getline(file, line)) {
        std::string lower = line;
        for (char& c : lower) c = static_cast<char>(tolower(static_cast<unsigned char>(c)));
        if (lower.find("build") != std::string::npos) {
            auto pos = line.find('=');
            if (pos != std::string::npos) {
                int build = extract_first_int(line.substr(pos + 1));
                if (build >= 0) return build;
            }
        }
    }

    std::cout << "[ERROR] Could not read build version from " << path.string() << "!\n";
    pause_and_exit(1);
    return -1;
}

bool run_command_capture(const std::string& command, std::string& output) {
    FILE* pipe = _popen(command.c_str(), "r");
    if (!pipe) return false;

    char buffer[4096];
    while (fgets(buffer, sizeof(buffer), pipe)) {
        output += buffer;
    }
    int rc = _pclose(pipe);
    return rc == 0;
}

std::string extract_json_string(const std::string& json, const std::string& key) {
    std::regex re("\\\"" + key + "\\\"\\s*:\\s*\\\"([^\\\"]*)\\\"");
    std::smatch m;
    if (std::regex_search(json, m, re)) {
        return m[1].str();
    }
    return "";
}

std::vector<std::string> extract_asset_urls(const std::string& json) {
    std::vector<std::string> urls;
    std::regex re("\\\"browser_download_url\\\"\\s*:\\s*\\\"([^\\\"]+)\\\"");
    auto begin = std::sregex_iterator(json.begin(), json.end(), re);
    auto end = std::sregex_iterator();
    for (auto i = begin; i != end; ++i) {
        urls.push_back((*i)[1].str());
    }
    return urls;
}

std::string choose_download_url(const std::string& json) {
    auto urls = extract_asset_urls(json);
    for (const auto& url : urls) {
        if (url.size() >= 4 && url.substr(url.size() - 4) == ".zip") {
            return url;
        }
    }
    if (!urls.empty()) return urls[0];
    return extract_json_string(json, "zipball_url");
}

struct UpdateInfo {
    std::string latestVersion;
    int latestBuild = -1;
    std::string downloadUrl;
};

UpdateInfo fetch_update_info() {
    std::cout << "Fetching update info from GitHub...\n\n";

    std::string ps =
        "powershell -NoProfile -ExecutionPolicy Bypass -Command \""
        "$ProgressPreference='SilentlyContinue'; "
        "$u='https://api.github.com/repos/" + REPO_OWNER + "/" + REPO_NAME + "/releases/latest'; "
        "$r=Invoke-WebRequest -UseBasicParsing -Headers @{ 'User-Agent'='KodiakUpdater/1.0'; 'Accept'='application/vnd.github+json' } -Uri $u; "
        "$r.Content\"";

    std::string json;
    if (!run_command_capture(ps, json) || json.empty()) {
        std::cout << "[ERROR] Failed to fetch update information from GitHub.\n";
        pause_and_exit(1);
    }

    UpdateInfo info;
    info.latestVersion = extract_json_string(json, "tag_name");
    if (info.latestVersion.empty()) {
        info.latestVersion = extract_json_string(json, "name");
    }
    std::string releaseName = extract_json_string(json, "name");
    std::string releaseBody = extract_json_string(json, "body");
    info.latestBuild = extract_first_int(info.latestVersion);
    if (info.latestBuild < 0) info.latestBuild = extract_first_int(releaseName);
    if (info.latestBuild < 0) info.latestBuild = extract_first_int(releaseBody);
    info.downloadUrl = choose_download_url(json);
    return info;
}

void clean_temp_dir(const fs::path& tempDir) {
    std::error_code ec;
    fs::remove_all(tempDir, ec);
}

void download_file(const std::string& url, const fs::path& outFile) {
    HRESULT hr = URLDownloadToFileA(nullptr, url.c_str(), outFile.string().c_str(), 0, nullptr);
    if (FAILED(hr)) {
        std::cout << "[ERROR] Download failed! HRESULT=" << std::hex << hr << std::dec << "\n";
        pause_and_exit(1);
    }
}

void extract_zip_with_powershell(const fs::path& zipPath, const fs::path& destPath) {
    std::string command =
        "powershell -NoProfile -ExecutionPolicy Bypass -Command \""
        "$zip='" + zipPath.string() + "'; "
        "$dest='" + destPath.string() + "'; "
        "if (Test-Path $dest) { Remove-Item $dest -Recurse -Force }; "
        "Expand-Archive -Path $zip -DestinationPath $dest -Force\"";

    int rc = system(command.c_str());
    if (rc != 0) {
        std::cout << "[ERROR] Extraction failed!\n";
        pause_and_exit(1);
    }
}

fs::path find_setup_exe(const fs::path& root) {
    for (const auto& entry : fs::recursive_directory_iterator(root)) {
        if (entry.is_regular_file()) {
            std::string filename = entry.path().filename().string();
            for (char& c : filename) c = static_cast<char>(tolower(static_cast<unsigned char>(c)));
            if (filename == "setup.exe") {
                return fs::absolute(entry.path());
            }
        }
    }
    return {};
}

void launch_installer_elevated(const fs::path& setupExe) {
    HINSTANCE result = ShellExecuteA(
        nullptr,
        "runas",
        setupExe.string().c_str(),
        nullptr,
        setupExe.parent_path().string().c_str(),
        SW_SHOWNORMAL
    );

    auto code = reinterpret_cast<INT_PTR>(result);
    if (code <= 32) {
        std::cout << "[ERROR] Failed to launch installer with elevation. ShellExecute code: " << code << "\n";
        pause_and_exit(1);
    }
}

int main() {
    print_banner();

    fs::path tempDir = get_temp_dir();
    fs::path versionSource = find_version_source();
    std::cout << "Reading version from: " << versionSource.string() << "\n\n";

    int currentBuild = extract_build(versionSource);
    std::cout << "Current Build: " << currentBuild << "\n\n";

    if (!is_supported_build(currentBuild)) {
        std::cout << "[WARNING] Build " << currentBuild << " is not supported.\n";
        std::cout << "This updater only supports builds 1001 and 1051.\n";
        pause_and_exit(1);
    }

    std::cout << "[OK] Build " << currentBuild << " is supported.\n\n";

    clean_temp_dir(tempDir);
    fs::create_directories(tempDir);

    UpdateInfo info = fetch_update_info();
    std::cout << "Latest Version: " << info.latestVersion << " (Build: " << info.latestBuild << ")\n\n";

    if (info.latestBuild < 0) {
        std::cout << "[ERROR] Could not determine the latest build number from the GitHub release.\n";
        clean_temp_dir(tempDir);
        pause_and_exit(1);
    }

    if (currentBuild == info.latestBuild) {
        std::cout << "[INFO] You are already on the latest version (" << currentBuild << ").\n";
        std::cout << "No update needed.\n";
        clean_temp_dir(tempDir);
        pause_and_exit(0);
    }

    if (currentBuild > info.latestBuild) {
        std::cout << "[INFO] Your current version (" << currentBuild << ") is newer than the latest release (" << info.latestBuild << ").\n";
        clean_temp_dir(tempDir);
        pause_and_exit(0);
    }

    std::cout << "[UPDATE AVAILABLE] New version " << info.latestBuild << " is available (current: " << currentBuild << ").\n\n";
    std::cout << "========================================\n";
    std::cout << "Starting Update Process\n";
    std::cout << "========================================\n\n";

    if (info.downloadUrl.empty()) {
        std::cout << "[ERROR] No download URL available. Cannot proceed with update.\n";
        clean_temp_dir(tempDir);
        pause_and_exit(1);
    }

    fs::path zipPath = tempDir / "update.zip";
    fs::path extractDir = tempDir / "extracted";

    std::cout << "Downloading update from GitHub...\n\n";
    download_file(info.downloadUrl, zipPath);
    std::cout << "Download complete!\n\n";

    std::cout << "Extracting update package...\n\n";
    extract_zip_with_powershell(zipPath, extractDir);
    std::cout << "Extraction complete!\n\n";

    fs::path setupExe = find_setup_exe(extractDir);
    if (setupExe.empty()) {
        std::cout << "[ERROR] setup.exe not found in update package!\n";
        clean_temp_dir(tempDir);
        pause_and_exit(1);
    }

    std::cout << "Found installer: " << setupExe.string() << "\n\n";

    std::cout << "========================================\n";
    std::cout << "Running Installer\n";
    std::cout << "========================================\n\n";
    std::cout << "Starting setup.exe... Please follow the installer prompts.\n\n";

    launch_installer_elevated(setupExe);

    std::cout << "Installer launched! The installation is running in a separate window.\n";
    std::cout << "Leaving extracted files in place for the installer to use.\n";
    std::cout << "Temp folder: " << tempDir.string() << "\n\n";
    std::cout << "========================================\n";
    std::cout << "Update Check Complete\n";
    std::cout << "========================================\n";

    pause_and_exit(0);
    return 0;
}
