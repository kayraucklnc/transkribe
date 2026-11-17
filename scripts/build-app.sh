#!/usr/bin/env bash
# Builds build/Transkribe.app (release).
# Usage: scripts/build-app.sh [--install]   (--install copies it to /Applications)
# Signing, first match wins:
#   DEVELOPER_ID="Developer ID Application: Your Name (TEAMID)"  for distribution (hardened runtime,
#     as notarization requires).
#   SIGN_IDENTITY, or a "Transkribe Local" code-signing certificate in the keychain: a stable
#     identity for your own builds, so macOS keeps the microphone, Screen Recording and
#     Accessibility permissions across rebuilds (create it once: scripts/make-local-cert.sh).
#   Otherwise ad-hoc: macOS sees every build as a new app and asks for permissions again.
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
cp -R "$(dirname "$BIN")/Transkribe_TranskribeCore.bundle" "$APP/Contents/Resources/"

echo "→ Building icon"
ICONSET="$(mktemp -d)/AppIcon.iconset"
mkdir -p "$ICONSET"
cp Resources/AppIcon.png "$ICONSET/icon_512x512@2x.png"
for size in 16 32 128 256 512; do
  sips -z $size $size "$ICONSET/icon_512x512@2x.png" --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
  double=$((size * 2))
  sips -z $double $double "$ICONSET/icon_512x512@2x.png" --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"

if [[ -n "${DEVELOPER_ID:-}" ]]; then
  echo "→ Signing with $DEVELOPER_ID"
  codesign --force --options runtime --timestamp --sign "$DEVELOPER_ID" "$APP/Contents/MacOS/transkribe-mcp"
  codesign --force --options runtime --timestamp --entitlements Resources/Transkribe.entitlements \
    --sign "$DEVELOPER_ID" --identifier kayrauckilinc.dev.transkribe "$APP"
else
  LOCAL="${SIGN_IDENTITY:-}"
  if [[ -z "$LOCAL" ]] && security find-identity -v -p codesigning 2>/dev/null | grep -q '"Transkribe Local"'; then
    LOCAL="Transkribe Local"
  fi
  if [[ -n "$LOCAL" ]]; then
    echo "→ Signing with $LOCAL (permissions stay across rebuilds)"
    codesign --force --sign "$LOCAL" "$APP/Contents/MacOS/transkribe-mcp"
    codesign --force --sign "$LOCAL" --identifier kayrauckilinc.dev.transkribe "$APP"
  else
    echo "→ Signing (ad-hoc). macOS will ask for permissions again after installing this build;"
    echo "  run scripts/make-local-cert.sh once to keep them across rebuilds."
    codesign --force --deep --sign - --identifier kayrauckilinc.dev.transkribe "$APP"
  fi
fi

if [[ "${1:-}" == "--install" ]]; then
  rm -rf /Applications/Transkribe.app
  cp -R "$APP" /Applications/
  echo "✓ Installed to /Applications/Transkribe.app"
else
  echo "✓ Built $APP"
fi
