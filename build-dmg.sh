#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

APP_NAME="AIChat"
APP_DISPLAY_NAME="Humlex"
VERSION="${1:-1.0}"                       # accept version as first arg
ARCH="${2:-$(uname -m)}"                  # arm64 or x86_64 (can override via second arg)
APP_BUNDLE=".build/${APP_DISPLAY_NAME}.app"
DMG_NAME="${APP_DISPLAY_NAME}-${VERSION}-${ARCH}.dmg"
DMG_DIR=".build/dmg"
DMG_PATH=".build/${DMG_NAME}"
ICON_SOURCE="assets/icon@1024px.png"

echo "=== Building ${APP_DISPLAY_NAME} v${VERSION} (${ARCH}) ==="
echo ""

# ── 1. Compile ────────────────────────────────────────────────────────
echo "[1/5] Compiling..."
if [ "${ARCH}" = "x86_64" ]; then
    swift build -c release --arch x86_64
elif [ "${ARCH}" = "arm64" ]; then
    swift build -c release --arch arm64
else
    swift build -c release
fi

if [ "${ARCH}" = "x86_64" ]; then
    BIN_PATH="$(swift build -c release --arch x86_64 --show-bin-path)/${APP_NAME}"
elif [ "${ARCH}" = "arm64" ]; then
    BIN_PATH="$(swift build -c release --arch arm64 --show-bin-path)/${APP_NAME}"
else
    BIN_PATH="$(swift build -c release --show-bin-path)/${APP_NAME}"
fi
CONTENTS_DIR="${APP_BUNDLE}/Contents"
MACOS_DIR="${CONTENTS_DIR}/MacOS"
RESOURCES_DIR="${CONTENTS_DIR}/Resources"

rm -rf "${APP_BUNDLE}"
mkdir -p "${MACOS_DIR}" "${RESOURCES_DIR}"
cp "${BIN_PATH}" "${MACOS_DIR}/${APP_DISPLAY_NAME}"

# ── 2. Generate .icns ────────────────────────────────────────────────
echo "[2/5] Generating app icon..."
if [ -f "${ICON_SOURCE}" ]; then
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
else
    echo "Warning: ${ICON_SOURCE} not found, skipping icon."
fi

# ── 3. Write Info.plist ───────────────────────────────────────────────
echo "[3/5] Writing Info.plist..."
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
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
</dict>
</plist>
PLIST

# ── 4. Build DMG staging area ────────────────────────────────────────
echo "[4/5] Staging DMG contents..."
rm -rf "${DMG_DIR}" "${DMG_PATH}"
mkdir -p "${DMG_DIR}"
cp -R "${APP_BUNDLE}" "${DMG_DIR}/"
ln -s /Applications "${DMG_DIR}/Applications"

# ── 5. Create DMG ─────────────────────────────────────────────────────
echo "[5/5] Creating ${DMG_NAME}..."

if [ "${CI:-}" = "true" ]; then
    # CI: simple compressed DMG (no Finder/AppleScript styling available)
    hdiutil create -volname "${APP_DISPLAY_NAME}" \
        -srcfolder "${DMG_DIR}" \
        -ov -format UDZO \
        -imagekey zlib-level=9 \
        "${DMG_PATH}" > /dev/null
else
    # Local: styled DMG with icon positioning
    TEMP_DMG=".build/${APP_DISPLAY_NAME}-temp.dmg"
    hdiutil create -volname "${APP_DISPLAY_NAME}" \
        -srcfolder "${DMG_DIR}" \
        -ov -format UDRW \
        "${TEMP_DMG}" > /dev/null

    MOUNT_DIR=$(hdiutil attach -readwrite -noverify "${TEMP_DMG}" | grep "/Volumes/" | sed 's/.*\/Volumes/\/Volumes/')

    osascript <<APPLESCRIPT
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

    sleep 1
    sync

    if [ -f "${RESOURCES_DIR}/AppIcon.icns" ]; then
        cp "${RESOURCES_DIR}/AppIcon.icns" "${MOUNT_DIR}/.VolumeIcon.icns"
        SetFile -a C "${MOUNT_DIR}" 2>/dev/null || true
    fi

    hdiutil detach "${MOUNT_DIR}" > /dev/null
    hdiutil convert "${TEMP_DMG}" -format UDZO -imagekey zlib-level=9 -o "${DMG_PATH}" > /dev/null
    rm -f "${TEMP_DMG}"
fi

rm -rf "${DMG_DIR}"

echo ""
echo "=== Done ==="
echo "  App:  ${APP_BUNDLE}"
echo "  DMG:  ${DMG_PATH}"
echo ""
echo "Size: $(du -h "${DMG_PATH}" | cut -f1)"
