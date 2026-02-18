#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${SCRIPT_DIR}"

APP_NAME="Humlex"
APP_DISPLAY_NAME="Humlex"
APP_BUNDLE=".build/${APP_DISPLAY_NAME}.app"
CONTENTS_DIR="${APP_BUNDLE}/Contents"
MACOS_DIR="${CONTENTS_DIR}/MacOS"
RESOURCES_DIR="${CONTENTS_DIR}/Resources"
ICON_SOURCE="Sources/Humlex/assets/icon@1024px.png"
UPDATER_CONFIG="config/updater.conf"
ICONSET_ROOT=""

if [ -t 1 ] && [ "${NO_COLOR:-}" != "1" ]; then
    C_RESET=$'\033[0m'
    C_BOLD=$'\033[1m'
    C_RED=$'\033[31m'
    C_GREEN=$'\033[32m'
    C_YELLOW=$'\033[33m'
    C_BLUE=$'\033[34m'
    C_CYAN=$'\033[36m'
else
    C_RESET=""
    C_BOLD=""
    C_RED=""
    C_GREEN=""
    C_YELLOW=""
    C_BLUE=""
    C_CYAN=""
fi

STEP_SYMBOL="->"
OK_SYMBOL="[OK]"
WARN_SYMBOL="[!]"
ERR_SYMBOL="[x]"

if [ -t 1 ]; then
    STEP_SYMBOL="=>"
    OK_SYMBOL="✓"
    WARN_SYMBOL="⚠"
    ERR_SYMBOL="✗"
fi

log_step() {
    printf "%b%s%b %s\n" "${C_CYAN}${C_BOLD}" "${STEP_SYMBOL}" "${C_RESET}" "$1"
}

log_info() {
    printf "%b%s%b %s\n" "${C_BLUE}" "i" "${C_RESET}" "$1"
}

log_ok() {
    printf "%b%s%b %s\n" "${C_GREEN}${C_BOLD}" "${OK_SYMBOL}" "${C_RESET}" "$1"
}

log_warn() {
    printf "%b%s%b %s\n" "${C_YELLOW}${C_BOLD}" "${WARN_SYMBOL}" "${C_RESET}" "$1" >&2
}

log_error() {
    printf "%b%s%b %s\n" "${C_RED}${C_BOLD}" "${ERR_SYMBOL}" "${C_RESET}" "$1" >&2
}

require_command() {
    if ! command -v "$1" > /dev/null 2>&1; then
        log_error "Required command not found: $1"
        exit 1
    fi
}

cleanup() {
    if [ -n "${ICONSET_ROOT}" ] && [ -d "${ICONSET_ROOT}" ]; then
        rm -rf "${ICONSET_ROOT}"
    fi
}
trap cleanup EXIT

require_command swift
require_command codesign
require_command install_name_tool
require_command otool
require_command open

if [ ! -f "${UPDATER_CONFIG}" ]; then
    log_error "Missing updater config at ${UPDATER_CONFIG}"
    exit 1
fi

# shellcheck disable=SC1090
source "${UPDATER_CONFIG}"
: "${SU_FEED_URL:?Error: SU_FEED_URL is missing in ${UPDATER_CONFIG}}"
: "${SU_PUBLIC_ED_KEY:?Error: SU_PUBLIC_ED_KEY is missing in ${UPDATER_CONFIG}}"

printf "%b=== Running %s (dev app bundle) ===%b\n" "${C_BOLD}${C_BLUE}" "${APP_DISPLAY_NAME}" "${C_RESET}"
log_step "Building ${APP_DISPLAY_NAME}..."
swift build

BIN_PATH="$(swift build --show-bin-path)/${APP_NAME}"
if [ ! -x "${BIN_PATH}" ]; then
    log_error "Built binary not found at ${BIN_PATH}"
    exit 1
fi

FRAMEWORKS_DIR="${CONTENTS_DIR}/Frameworks"

mkdir -p "${MACOS_DIR}" "${RESOURCES_DIR}" "${FRAMEWORKS_DIR}"
cp "${BIN_PATH}" "${MACOS_DIR}/${APP_DISPLAY_NAME}"

# Embed Sparkle.framework into the app bundle
SPARKLE_FW="$(dirname "${BIN_PATH}")/Sparkle.framework"
if [ -d "${SPARKLE_FW}" ]; then
    log_info "Embedding Sparkle.framework..."
    cp -R "${SPARKLE_FW}" "${FRAMEWORKS_DIR}/"
    if ! otool -l "${MACOS_DIR}/${APP_DISPLAY_NAME}" | grep -A2 "LC_RPATH" | grep -q "@executable_path/../Frameworks"; then
        # Add rpath so the binary can find the framework in Contents/Frameworks/
        install_name_tool -add_rpath "@executable_path/../Frameworks" "${MACOS_DIR}/${APP_DISPLAY_NAME}"
    fi
    # Re-sign after modifying the binary (install_name_tool invalidates the ad-hoc signature)
    codesign --force --sign - "${MACOS_DIR}/${APP_DISPLAY_NAME}"
else
    log_warn "Sparkle.framework not found at ${SPARKLE_FW}"
fi

# Generate .icns from source PNG
if [ -f "${ICON_SOURCE}" ]; then
    require_command sips
    require_command iconutil

    log_step "Generating app icon..."
    ICONSET_ROOT="$(mktemp -d)"
    ICONSET_DIR="${ICONSET_ROOT}/AppIcon.iconset"
    mkdir -p "${ICONSET_DIR}"

    sips -z 16   16   "${ICON_SOURCE}" --out "${ICONSET_DIR}/icon_16x16.png"      > /dev/null
    sips -z 32   32   "${ICON_SOURCE}" --out "${ICONSET_DIR}/icon_16x16@2x.png"   > /dev/null
    sips -z 32   32   "${ICON_SOURCE}" --out "${ICONSET_DIR}/icon_32x32.png"      > /dev/null
    sips -z 64   64   "${ICON_SOURCE}" --out "${ICONSET_DIR}/icon_32x32@2x.png"   > /dev/null
    sips -z 128  128  "${ICON_SOURCE}" --out "${ICONSET_DIR}/icon_128x128.png"    > /dev/null
    sips -z 256  256  "${ICON_SOURCE}" --out "${ICONSET_DIR}/icon_128x128@2x.png" > /dev/null
    sips -z 256  256  "${ICON_SOURCE}" --out "${ICONSET_DIR}/icon_256x256.png"    > /dev/null
    sips -z 512  512  "${ICON_SOURCE}" --out "${ICONSET_DIR}/icon_256x256@2x.png" > /dev/null
    sips -z 512  512  "${ICON_SOURCE}" --out "${ICONSET_DIR}/icon_512x512.png"    > /dev/null
    sips -z 1024 1024 "${ICON_SOURCE}" --out "${ICONSET_DIR}/icon_512x512@2x.png" > /dev/null

    iconutil -c icns "${ICONSET_DIR}" -o "${RESOURCES_DIR}/AppIcon.icns"
    log_ok "Icon embedded."
else
    log_warn "${ICON_SOURCE} not found, skipping icon."
fi

log_step "Writing Info.plist..."
cat > "${CONTENTS_DIR}/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>${APP_DISPLAY_NAME}</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleIdentifier</key>
    <string>com.local.humlex</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>${APP_DISPLAY_NAME}</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>0.0.0-dev</string>
    <key>CFBundleVersion</key>
    <string>0.0.0-dev</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
    <key>SUFeedURL</key>
    <string>${SU_FEED_URL}</string>
    <key>SUPublicEDKey</key>
    <string>${SU_PUBLIC_ED_KEY}</string>
    <key>SUEnableAutomaticChecks</key>
    <true/>
</dict>
</plist>
PLIST

log_step "Opening ${APP_BUNDLE}..."
open "${APP_BUNDLE}"
log_ok "App opened."
