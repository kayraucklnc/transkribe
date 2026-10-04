#!/usr/bin/env bash
# Builds build/Transkribe.dmg: the app, an Applications shortcut, and a designed window.
# Usage: scripts/make-dmg.sh   (builds the app first)
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD="$ROOT/build"
cd "$ROOT"

scripts/build-app.sh

echo "→ Preparing DMG tools"
VENV="$BUILD/.dmg-venv"
if [[ ! -x "$VENV/bin/dmgbuild" ]]; then
  python3 -m venv "$VENV"
  "$VENV/bin/pip" install --quiet dmgbuild
fi

echo "→ Rendering background"
swift scripts/make-dmg-background.swift "$BUILD/dmg-background@2x.png"
sips -z 420 660 -s dpiWidth 72 -s dpiHeight 72 "$BUILD/dmg-background@2x.png" --out "$BUILD/dmg-background.png" >/dev/null
tiffutil -cathidpicheck "$BUILD/dmg-background.png" "$BUILD/dmg-background@2x.png" -out "$BUILD/dmg-background.tiff" >/dev/null

VERSION="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' Resources/Info.plist)"
SETTINGS="$BUILD/dmg-settings.py"
cat > "$SETTINGS" <<PY
files = ["$BUILD/Transkribe.app"]
symlinks = {"Applications": "/Applications"}
icon_locations = {"Transkribe.app": (170, 220), "Applications": (490, 220)}
background = "$BUILD/dmg-background.tiff"
window_rect = ((200, 140), (660, 420))
icon_size = 112
text_size = 13
show_status_bar = False
show_tab_view = False
show_toolbar = False
show_pathbar = False
show_sidebar = False
default_view = "icon-view"
format = "ULFO"
filesystem = "APFS"
hide_extension = ["Transkribe.app"]
badge_icon = None
PY

echo "→ Building DMG"
rm -f "$BUILD/Transkribe.dmg"
"$VENV/bin/dmgbuild" -s "$SETTINGS" "Transkribe $VERSION" "$BUILD/Transkribe.dmg"
codesign --force --sign - "$BUILD/Transkribe.dmg"
echo "✓ Built $BUILD/Transkribe.dmg ($(du -h "$BUILD/Transkribe.dmg" | cut -f1))"
