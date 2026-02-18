#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${SCRIPT_DIR}"

APP_NAME="Humlex"
APP_DISPLAY_NAME="Humlex"
VERSION="${1:-1.0}"                       # accept version as first arg
ARCH="${2:-$(uname -m)}"                  # arm64 or x86_64 (can override via second arg)
APP_BUNDLE=".build/${APP_DISPLAY_NAME}.app"
DMG_NAME="${APP_DISPLAY_NAME}-${VERSION}-${ARCH}.dmg"
DMG_DIR=".build/dmg"
DMG_PATH=".build/${DMG_NAME}"
ICON_SOURCE="Sources/Humlex/assets/icon@1024px.png"
UPDATER_CONFIG="config/updater.conf"
TEMP_DMG=""
MOUNT_DIR=""
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

usage() {
    cat <<EOF
Usage: ./build-dmg.sh [version] [arch]

Arguments:
  version   App and DMG version string (default: 1.0)
  arch      arm64 or x86_64 (default: current machine architecture)
EOF
}

require_command() {
    if ! command -v "$1" > /dev/null 2>&1; then
        log_error "Required command not found: $1"
        exit 1
    fi
}

cleanup() {
    status=$?

    if [ -n "${MOUNT_DIR}" ] && hdiutil info | grep -Fq "${MOUNT_DIR}"; then
        hdiutil detach "${MOUNT_DIR}" > /dev/null 2>&1 || hdiutil detach -force "${MOUNT_DIR}" > /dev/null 2>&1 || true
    fi

    if [ -n "${ICONSET_ROOT}" ] && [ -d "${ICONSET_ROOT}" ]; then
        rm -rf "${ICONSET_ROOT}"
    fi

    if [ -n "${MOUNT_DIR}" ] && [ -d "${MOUNT_DIR}" ]; then
        rmdir "${MOUNT_DIR}" > /dev/null 2>&1 || true
    fi

    if [ -n "${TEMP_DMG}" ] && [ -f "${TEMP_DMG}" ]; then
        rm -f "${TEMP_DMG}"
    fi

    trap - EXIT
    exit "${status}"
}
trap cleanup EXIT

if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
    usage
    exit 0
fi

case "${ARCH}" in
    arm64|x86_64) ;;
    *)
        log_error "Unsupported arch '${ARCH}'. Expected 'arm64' or 'x86_64'."
        usage
        exit 1
        ;;
esac

if [[ ! "${VERSION}" =~ ^[0-9A-Za-z._-]+$ ]]; then
    log_error "Version '${VERSION}' contains invalid characters."
    exit 1
fi

require_command swift
require_command hdiutil
require_command codesign
require_command install_name_tool
require_command otool

if [ ! -f "${UPDATER_CONFIG}" ]; then
    log_error "Missing updater config at ${UPDATER_CONFIG}"
    exit 1
fi

# shellcheck disable=SC1090
source "${UPDATER_CONFIG}"
: "${SU_FEED_URL:?Error: SU_FEED_URL is missing in ${UPDATER_CONFIG}}"
: "${SU_PUBLIC_ED_KEY:?Error: SU_PUBLIC_ED_KEY is missing in ${UPDATER_CONFIG}}"

printf "%b=== Building %s v%s (%s) ===%b\n" "${C_BOLD}${C_BLUE}" "${APP_DISPLAY_NAME}" "${VERSION}" "${ARCH}" "${C_RESET}"
echo ""

SWIFT_BUILD_ARGS=(-c release --arch "${ARCH}")

# ── 1. Compile ────────────────────────────────────────────────────────
log_step "[1/5] Compiling..."
swift build "${SWIFT_BUILD_ARGS[@]}"
BIN_DIR="$(swift build "${SWIFT_BUILD_ARGS[@]}" --show-bin-path)"
BIN_PATH="${BIN_DIR}/${APP_NAME}"
if [ ! -x "${BIN_PATH}" ]; then
    log_error "Built binary not found at ${BIN_PATH}"
    exit 1
fi
CONTENTS_DIR="${APP_BUNDLE}/Contents"
MACOS_DIR="${CONTENTS_DIR}/MacOS"
RESOURCES_DIR="${CONTENTS_DIR}/Resources"

FRAMEWORKS_DIR="${CONTENTS_DIR}/Frameworks"

rm -rf "${APP_BUNDLE}"
mkdir -p "${MACOS_DIR}" "${RESOURCES_DIR}" "${FRAMEWORKS_DIR}"
cp "${BIN_PATH}" "${MACOS_DIR}/${APP_DISPLAY_NAME}"

# Embed Sparkle.framework into the app bundle
SPARKLE_FW="${BIN_DIR}/Sparkle.framework"
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

# ── 2. Generate .icns ────────────────────────────────────────────────
log_step "[2/5] Generating app icon..."
if [ -f "${ICON_SOURCE}" ]; then
    require_command sips
    require_command iconutil

    ICONSET_ROOT="$(mktemp -d)"
    ICONSET_DIR="${ICONSET_ROOT}/AppIcon.iconset"
    mkdir -p "${ICONSET_DIR}"

    ICON_SPECS=$'16 16 icon_16x16.png\n32 32 icon_16x16@2x.png\n32 32 icon_32x32.png\n64 64 icon_32x32@2x.png\n128 128 icon_128x128.png\n256 256 icon_128x128@2x.png\n256 256 icon_256x256.png\n512 512 icon_256x256@2x.png\n512 512 icon_512x512.png\n1024 1024 icon_512x512@2x.png'
    while read -r width height output_name; do
        sips -z "${width}" "${height}" "${ICON_SOURCE}" --out "${ICONSET_DIR}/${output_name}" > /dev/null
    done <<< "${ICON_SPECS}"

    iconutil -c icns "${ICONSET_DIR}" -o "${RESOURCES_DIR}/AppIcon.icns"
else
    log_warn "${ICON_SOURCE} not found, skipping icon."
fi

# ── 3. Write Info.plist ───────────────────────────────────────────────
log_step "[3/5] Writing Info.plist..."
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
    <string>${VERSION}</string>
    <key>CFBundleVersion</key>
    <string>${VERSION}</string>
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

log_step "[3.5/5] Re-signing app bundle..."
codesign --force --deep --sign - "${APP_BUNDLE}"
codesign --verify --deep --strict --verbose=2 "${APP_BUNDLE}"

# ── 4. Build DMG staging area ────────────────────────────────────────
log_step "[4/5] Staging DMG contents..."
rm -rf "${DMG_DIR}" "${DMG_PATH}"
mkdir -p "${DMG_DIR}"
cp -R "${APP_BUNDLE}" "${DMG_DIR}/"
ln -s /Applications "${DMG_DIR}/Applications"

# ── 5. Create DMG ─────────────────────────────────────────────────────
log_step "[5/5] Creating ${DMG_NAME}..."

if [ "${CI:-}" = "true" ]; then
    # CI: simple compressed DMG (no Finder/AppleScript styling available)
    hdiutil create -volname "${APP_DISPLAY_NAME}" \
        -srcfolder "${DMG_DIR}" \
        -ov -format UDZO \
        -imagekey zlib-level=9 \
        "${DMG_PATH}" > /dev/null
else
    # Local: styled DMG with icon positioning
    require_command osascript

    TEMP_DMG=".build/${APP_DISPLAY_NAME}-temp.dmg"
    hdiutil create -volname "${APP_DISPLAY_NAME}" \
        -srcfolder "${DMG_DIR}" \
        -ov -format UDRW \
        "${TEMP_DMG}" > /dev/null

    ATTACH_OUTPUT="$(hdiutil attach -readwrite -noverify "${TEMP_DMG}")"
    MOUNT_DIR="$(printf "%s\n" "${ATTACH_OUTPUT}" | awk '/\/Volumes\// {print substr($0, index($0, "/Volumes/")); exit}')"
    if [ -z "${MOUNT_DIR}" ] || [ ! -d "${MOUNT_DIR}" ]; then
        log_error "Failed to determine DMG mount directory."
        exit 1
    fi

    if ! osascript <<APPLESCRIPT
tell application "Finder"
    tell disk "${APP_DISPLAY_NAME}"
        open
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set bounds of container window to {100, 100, 640, 400}
        set theViewOptions to icon view options of container window
        set arrangement of theViewOptions to not arranged
        set icon size of theViewOptions to 96
        set position of item "${APP_DISPLAY_NAME}.app" of container window to {140, 150}
        set position of item "Applications" of container window to {400, 150}
        close
    end tell
end tell
APPLESCRIPT
    then
        log_warn "Finder styling failed; continuing with unstyled DMG."
    fi

    sleep 1
    sync

    if [ -f "${RESOURCES_DIR}/AppIcon.icns" ]; then
        cp "${RESOURCES_DIR}/AppIcon.icns" "${MOUNT_DIR}/.VolumeIcon.icns"
        if command -v SetFile > /dev/null 2>&1; then
            SetFile -a C "${MOUNT_DIR}" 2>/dev/null || true
        fi
    fi

    hdiutil detach "${MOUNT_DIR}" > /dev/null
    MOUNT_DIR=""

    hdiutil convert "${TEMP_DMG}" -format UDZO -imagekey zlib-level=9 -o "${DMG_PATH}" > /dev/null
    rm -f "${TEMP_DMG}"
    TEMP_DMG=""
fi

rm -rf "${DMG_DIR}"

echo ""
printf "%b=== Done ===%b\n" "${C_BOLD}${C_GREEN}" "${C_RESET}"
printf "  %b%s%b %s\n" "${C_GREEN}" "${OK_SYMBOL}" "${C_RESET}" "App:  ${APP_BUNDLE}"
printf "  %b%s%b %s\n" "${C_GREEN}" "${OK_SYMBOL}" "${C_RESET}" "DMG:  ${DMG_PATH}"
echo ""
printf "%b%s%b %s\n" "${C_CYAN}" "Size:" "${C_RESET}" "$(du -h "${DMG_PATH}" | cut -f1)"
