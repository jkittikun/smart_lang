#!/usr/bin/env bash
# Packs SmartLang.app into a drag-to-install disk image.
# Usage: ./scripts/make_dmg.sh [VERSION]   (run ./scripts/build_app.sh first)
# Output: SmartLang-VERSION.dmg (or SmartLang.dmg without a version)
set -euo pipefail
cd "$(dirname "$0")/.."

APP="SmartLang.app"
VERSION="${1:-${VERSION:-}}"
DMG="SmartLang${VERSION:+-$VERSION}.dmg"
VOLNAME="SmartLang${VERSION:+ $VERSION}"

[[ -d "$APP" ]] || { echo "No $APP — run ./scripts/build_app.sh first"; exit 1; }

WORK="$(mktemp -d)"
trap 'hdiutil detach "$WORK/mnt" -quiet 2>/dev/null || true; rm -rf "$WORK"' EXIT

echo "==> Staging"
mkdir -p "$WORK/stage"
cp -R "$APP" "$WORK/stage/"
ln -s /Applications "$WORK/stage/Applications"   # drag target

echo "==> Creating disk image"
hdiutil create -quiet -volname "$VOLNAME" -srcfolder "$WORK/stage" \
    -fs HFS+ -format UDRW -ov "$WORK/rw.dmg"

# Give the mounted volume the app icon.
mkdir -p "$WORK/mnt"
hdiutil attach -quiet -nobrowse -noautoopen -mountpoint "$WORK/mnt" "$WORK/rw.dmg"
cp "Resources/AppIcon.icns" "$WORK/mnt/.VolumeIcon.icns"
if command -v SetFile >/dev/null 2>&1; then
    SetFile -a C "$WORK/mnt"
else
    echo "   (SetFile not found; the volume will use the default icon)"
fi
hdiutil detach -quiet "$WORK/mnt"

echo "==> Compressing"
rm -f "$DMG"
hdiutil convert -quiet "$WORK/rw.dmg" -format UDZO -imagekey zlib-level=9 -o "$DMG"
echo "Done: $(pwd)/$DMG"
