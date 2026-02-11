#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "${ROOT_DIR}"

APP_NAME="AIChat"
APP_DISPLAY_NAME="Humlex"
APP_BUNDLE=".build/${APP_DISPLAY_NAME}.app"
CONTENTS_DIR="${APP_BUNDLE}/Contents"
MACOS_DIR="${CONTENTS_DIR}/MacOS"
RESOURCES_DIR="${CONTENTS_DIR}/Resources"
FRAMEWORKS_DIR="${CONTENTS_DIR}/Frameworks"
ICON_SOURCE="assets/icon@1024px.png"
UPDATER_CONFIG="config/updater.conf"

WATCH_MODE=false
OPEN_AFTER_BUILD=true
QUIT_BEFORE_OPEN=true
CLEAN_BUILD=false
BUILD_CONFIGURATION="debug"

if [[ -t 1 ]]; then
    C_RESET="\033[0m"
    C_DIM="\033[2m"
    C_BOLD="\033[1m"
    C_BLUE="\033[34m"
    C_GREEN="\033[32m"
    C_YELLOW="\033[33m"
    C_RED="\033[31m"
else
    C_RESET=""
    C_DIM=""
    C_BOLD=""
    C_BLUE=""
    C_GREEN=""
    C_YELLOW=""
    C_RED=""
fi

timestamp() {
    date +"%H:%M:%S"
}

log_info() {
    printf "%b[%s] [INFO] %s%b\n" "${C_BLUE}" "$(timestamp)" "$*" "${C_RESET}"
}

log_ok() {
    printf "%b[%s] [ OK ] %s%b\n" "${C_GREEN}" "$(timestamp)" "$*" "${C_RESET}"
}

log_warn() {
    printf "%b[%s] [WARN] %s%b\n" "${C_YELLOW}" "$(timestamp)" "$*" "${C_RESET}"
}

log_error() {
    printf "%b[%s] [FAIL] %s%b\n" "${C_RED}" "$(timestamp)" "$*" "${C_RESET}" >&2
}

print_header() {
    printf "%b\n" "${C_BOLD}----------------------------------------${C_RESET}"
    printf "%b\n" "${C_BOLD} Humlex Dev Runner${C_RESET}"
    printf "%b\n" "${C_BOLD}----------------------------------------${C_RESET}"
    printf "%b\n" "${C_DIM}root: ${ROOT_DIR}${C_RESET}"
}

print_config() {
    printf "%b\n" "${C_BOLD}Configuration${C_RESET}"
    printf "  build:   %s\n" "${BUILD_CONFIGURATION}"
    printf "  watch:   %s\n" "${WATCH_MODE}"
    printf "  clean:   %s\n" "${CLEAN_BUILD}"
    printf "  open:    %s\n" "${OPEN_AFTER_BUILD}"
    printf "  quit:    %s\n" "${QUIT_BEFORE_OPEN}"
}

on_error() {
    local code="$1"
    log_error "Script failed (exit ${code})."
}

trap 'on_error "$?"' ERR

usage() {
    cat <<'EOF'
Usage: ./dev.sh [options]

Options:
  --watch           Rebuild/relaunch on file changes (requires fswatch)
  --no-open         Build app bundle only, do not open it
  --no-quit         Do not quit existing Humlex before launch
  --clean           Run swift package clean before build
  --release         Build release configuration
  -h, --help        Show this help
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --watch)
            WATCH_MODE=true
            ;;
        --no-open)
            OPEN_AFTER_BUILD=false
            ;;
        --no-quit)
            QUIT_BEFORE_OPEN=false
            ;;
        --clean)
            CLEAN_BUILD=true
            ;;
        --release)
            BUILD_CONFIGURATION="release"
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "Unknown option: $1" >&2
            usage
            exit 1
            ;;
    esac
    shift
done

if [[ ! -f "${UPDATER_CONFIG}" ]]; then
    log_error "Missing updater config at ${UPDATER_CONFIG}"
    exit 1
fi

# shellcheck disable=SC1090
source "${UPDATER_CONFIG}"

if [[ -z "${SU_FEED_URL:-}" || -z "${SU_PUBLIC_ED_KEY:-}" ]]; then
    log_error "SU_FEED_URL and SU_PUBLIC_ED_KEY must be set in ${UPDATER_CONFIG}"
    exit 1
fi

swift_flags=("-c" "${BUILD_CONFIGURATION}")

quit_existing_app() {
    if ! ${QUIT_BEFORE_OPEN}; then
        return
    fi

    log_info "Closing running ${APP_DISPLAY_NAME} instance (if any)..."
    osascript -e "tell application \"${APP_DISPLAY_NAME}\" to quit" >/dev/null 2>&1 || true
    pkill -x "${APP_DISPLAY_NAME}" >/dev/null 2>&1 || true
}

build_bundle() {
    local start_time
    local end_time
    local duration
    local bin_path
    local sparkle_fw
    local iconset_dir

    start_time=$(date +%s)

    if ${CLEAN_BUILD}; then
        log_info "Cleaning package..."
        swift package clean
        log_ok "Clean complete"
    fi

    log_info "Building ${APP_DISPLAY_NAME} (${BUILD_CONFIGURATION})..."
    swift build "${swift_flags[@]}"

    bin_path="$(swift build "${swift_flags[@]}" --show-bin-path)/${APP_NAME}"
    if [[ ! -f "${bin_path}" ]]; then
        log_error "Build output not found at ${bin_path}"
        exit 1
    fi

    mkdir -p "${MACOS_DIR}" "${RESOURCES_DIR}" "${FRAMEWORKS_DIR}"
    cp "${bin_path}" "${MACOS_DIR}/${APP_DISPLAY_NAME}"

    sparkle_fw="$(dirname "${bin_path}")/Sparkle.framework"
    if [[ -d "${sparkle_fw}" ]]; then
        log_info "Embedding Sparkle.framework..."
        rm -rf "${FRAMEWORKS_DIR}/Sparkle.framework"
        cp -R "${sparkle_fw}" "${FRAMEWORKS_DIR}/"
        install_name_tool -add_rpath "@executable_path/../Frameworks" "${MACOS_DIR}/${APP_DISPLAY_NAME}" 2>/dev/null || true
        codesign --force --sign - "${MACOS_DIR}/${APP_DISPLAY_NAME}"
        log_ok "Sparkle embedded"
    else
        log_warn "Sparkle.framework not found, continuing without it"
    fi

    if [[ -f "${ICON_SOURCE}" ]]; then
        iconset_dir="$(mktemp -d)/AppIcon.iconset"
        mkdir -p "${iconset_dir}"

        sips -z 16   16   "${ICON_SOURCE}" --out "${iconset_dir}/icon_16x16.png"      >/dev/null
        sips -z 32   32   "${ICON_SOURCE}" --out "${iconset_dir}/icon_16x16@2x.png"   >/dev/null
        sips -z 32   32   "${ICON_SOURCE}" --out "${iconset_dir}/icon_32x32.png"      >/dev/null
        sips -z 64   64   "${ICON_SOURCE}" --out "${iconset_dir}/icon_32x32@2x.png"   >/dev/null
        sips -z 128  128  "${ICON_SOURCE}" --out "${iconset_dir}/icon_128x128.png"    >/dev/null
        sips -z 256  256  "${ICON_SOURCE}" --out "${iconset_dir}/icon_128x128@2x.png" >/dev/null
        sips -z 256  256  "${ICON_SOURCE}" --out "${iconset_dir}/icon_256x256.png"    >/dev/null
        sips -z 512  512  "${ICON_SOURCE}" --out "${iconset_dir}/icon_256x256@2x.png" >/dev/null
        sips -z 512  512  "${ICON_SOURCE}" --out "${iconset_dir}/icon_512x512.png"    >/dev/null
        sips -z 1024 1024 "${ICON_SOURCE}" --out "${iconset_dir}/icon_512x512@2x.png" >/dev/null

        iconutil -c icns "${iconset_dir}" -o "${RESOURCES_DIR}/AppIcon.icns"
        rm -rf "$(dirname "${iconset_dir}")"
    fi

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

    end_time=$(date +%s)
    duration=$((end_time - start_time))
    log_ok "Build complete in ${duration}s"
}

launch_app() {
    if ! ${OPEN_AFTER_BUILD}; then
        return
    fi

    quit_existing_app
    log_info "Opening ${APP_BUNDLE}..."
    open "${APP_BUNDLE}"
    log_ok "Launched ${APP_DISPLAY_NAME}"
}

build_and_maybe_launch() {
    build_bundle
    launch_app
}

if ${WATCH_MODE}; then
    if ! command -v fswatch >/dev/null 2>&1; then
        log_error "--watch requires fswatch. Install with: brew install fswatch"
        exit 1
    fi

    print_header
    print_config
    build_and_maybe_launch
    log_info "Watching for changes (Ctrl+C to stop)..."
    while true; do
        changes="$(fswatch -1 -r --exclude '(^|/)\.git/' --exclude '(^|/)\.build/' "${ROOT_DIR}")"
        first_change="${changes%%$'\n'*}"
        first_change="${first_change#${ROOT_DIR}/}"
        log_info "Change detected: ${first_change}"
        log_info "Rebuilding..."
        build_and_maybe_launch
    done
else
    print_header
    print_config
    build_and_maybe_launch
fi
