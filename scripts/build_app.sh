#!/usr/bin/env bash
# Builds SmartLang.app (menu-bar app) from the Swift package.
# Usage: ./scripts/build_app.sh [--install]   (--install copies it to /Applications)
#        UNIVERSAL=1 ./scripts/build_app.sh     (arm64 + x86_64 binary)
#        VERSION=1.2.3 ./scripts/build_app.sh   (default: the latest vX.Y.Z git tag)
#        SIGN_IDENTITY="name" ./scripts/build_app.sh   (default: ad hoc, "-")
set -euo pipefail
cd "$(dirname "$0")/.."

APP="SmartLang.app"
if [[ -z "${VERSION:-}" ]]; then
    VERSION="$(git describe --tags --abbrev=0 --match 'v[0-9]*' 2>/dev/null | sed 's/^v//' || true)"
    VERSION="${VERSION:-1.0.0}"
fi
BUNDLE_ID="${BUNDLE_ID:-com.smartlang.SmartLang}"
SIGN_IDENTITY="${SIGN_IDENTITY:--}"

# Native build by default (fast, works with just the Command Line Tools).
# UNIVERSAL=1 builds an arm64 + x86_64 binary (used by CI).
if [[ "${UNIVERSAL:-0}" == "1" ]]; then
    echo "==> Building (release, universal arm64 + x86_64)"
    ARCH_FLAGS=(--arch arm64 --arch x86_64)
else
    echo "==> Building (release, $(uname -m))"
    ARCH_FLAGS=()
fi
swift build -c release ${ARCH_FLAGS[@]+"${ARCH_FLAGS[@]}"}
BIN="$(swift build -c release ${ARCH_FLAGS[@]+"${ARCH_FLAGS[@]}"} --show-bin-path)/SmartLang"

echo "==> Assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/SmartLang"
# App icon (regenerate with: python3 scripts/make_icon.py)
cp "Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>SmartLang</string>
    <key>CFBundleDisplayName</key><string>SmartLang</string>
    <key>CFBundleIdentifier</key><string>${BUNDLE_ID}</string>
    <key>CFBundleExecutable</key><string>SmartLang</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundleShortVersionString</key><string>${VERSION}</string>
    <key>CFBundleVersion</key><string>${VERSION}</string>
    <key>LSMinimumSystemVersion</key><string>13.0</string>
    <key>LSUIElement</key><true/>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSAppleEventsUsageDescription</key><string>SmartLang types corrected text into the app you are using.</string>
</dict>
</plist>
PLIST

if [[ "$SIGN_IDENTITY" == "-" ]]; then
    echo "==> Signing (ad hoc)"
else
    echo "==> Signing with $SIGN_IDENTITY"
fi
codesign --force --deep --timestamp=none --sign "$SIGN_IDENTITY" "$APP"
codesign --verify --deep --strict "$APP"

if [[ "${1:-}" == "--install" ]]; then
    echo "==> Installing to /Applications"
    rm -rf "/Applications/$APP"
    cp -R "$APP" /Applications/
    # Make Finder/Dock pick up a changed icon right away.
    touch "/Applications/$APP"
    echo "Open it with: open /Applications/$APP"
else
    echo "Done: $(pwd)/$APP   (open it with: open $APP)"
fi
