#!/usr/bin/env bash
# Builds build/Transkribe.app (release, ad-hoc signed).
# Usage: scripts/build-app.sh [--install]   (--install copies it to /Applications)
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/build/Transkribe.app"
cd "$ROOT"

echo "→ Compiling (release)…"
swift build -c release --product Transkribe
swift build -c release --product transkribe-mcp
BIN="$(swift build -c release --show-bin-path)/Transkribe"
MCP="$(swift build -c release --show-bin-path)/transkribe-mcp"

echo "→ Assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Transkribe"
cp "$MCP" "$APP/Contents/MacOS/transkribe-mcp"
cp Resources/Info.plist "$APP/Contents/Info.plist"

echo "→ Rendering icon"
ICONSET="$(mktemp -d)/AppIcon.iconset"
mkdir -p "$ICONSET"
swift scripts/make-icon.swift "$ICONSET/icon_512x512@2x.png"
for size in 16 32 128 256 512; do
  sips -z $size $size "$ICONSET/icon_512x512@2x.png" --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
  double=$((size * 2))
  sips -z $double $double "$ICONSET/icon_512x512@2x.png" --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"

echo "→ Signing (ad-hoc)"
codesign --force --deep --sign - --identifier sh.ratel.transkribe "$APP"

if [[ "${1:-}" == "--install" ]]; then
  rm -rf /Applications/Transkribe.app
  cp -R "$APP" /Applications/
  echo "✓ Installed to /Applications/Transkribe.app"
else
  echo "✓ Built $APP"
fi
