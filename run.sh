#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

APP_NAME="AIChat"
APP_DISPLAY_NAME="Humlex"
APP_BUNDLE=".build/${APP_DISPLAY_NAME}.app"
CONTENTS_DIR="${APP_BUNDLE}/Contents"
MACOS_DIR="${CONTENTS_DIR}/MacOS"
RESOURCES_DIR="${CONTENTS_DIR}/Resources"
ICON_SOURCE="assets/icon@1024px.png"

echo "Building ${APP_DISPLAY_NAME}..."
swift build

BIN_PATH="$(swift build --show-bin-path)/${APP_NAME}"

mkdir -p "${MACOS_DIR}" "${RESOURCES_DIR}"
cp "${BIN_PATH}" "${MACOS_DIR}/${APP_DISPLAY_NAME}"

# Generate .icns from source PNG
if [ -f "${ICON_SOURCE}" ]; then
    echo "Generating app icon..."
    ICONSET_DIR=$(mktemp -d)/AppIcon.iconset
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
    rm -rf "$(dirname "${ICONSET_DIR}")"
    echo "Icon embedded."
else
    echo "Warning: ${ICON_SOURCE} not found, skipping icon."
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
    <string>1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
    <key>SUFeedURL</key>
    <string>https://raw.githubusercontent.com/lassejlv/humlex/main/docs/appcast.xml</string>
    <key>SUPublicEDKey</key>
    <string>8kpw38a9r7rrVsa9d5bhzEDZGoYX4yffaWedaydM/pA=</string>
    <key>SUEnableAutomaticChecks</key>
    <true/>
</dict>
</plist>
PLIST

echo "Opening ${APP_BUNDLE}..."
open "${APP_BUNDLE}"
