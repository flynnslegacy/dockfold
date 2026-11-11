#!/bin/zsh
# Builds Nido.app (release) into ./build and optionally installs it in /Applications.
# Usage: scripts/build-app.sh [--install]
set -euo pipefail

ROOT="${0:A:h:h}"
BUILD="$ROOT/build"
APP="$BUILD/Nido.app"
TEMPLATE="$APP/Contents/Resources/NidoFolder.app"

cd "$ROOT"
swift build -c release
BIN="$(swift build -c release --show-bin-path)"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN/Nido" "$APP/Contents/MacOS/Nido"
cp "$ROOT/config/Nido-Info.plist" "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"

# Folder template: copied and customised by Nido for every folder.
mkdir -p "$TEMPLATE/Contents/MacOS" "$TEMPLATE/Contents/Resources"
cp "$BIN/NidoFolder" "$TEMPLATE/Contents/MacOS/NidoFolder"
cp "$ROOT/config/NidoFolder-Info.plist" "$TEMPLATE/Contents/Info.plist"
printf 'APPL????' > "$TEMPLATE/Contents/PkgInfo"

# App icon, rendered by the app itself.
ICONSET="$BUILD/AppIcon.iconset"
rm -rf "$ICONSET"
"$BIN/Nido" --export-iconset "$ICONSET"
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
rm -rf "$ICONSET"

# Ad-hoc signatures, inner bundle first.
codesign --force --sign - "$TEMPLATE"
codesign --force --sign - --identifier local.nido.manager "$APP"
echo "Built $APP"

if [[ "${1:-}" == "--install" ]]; then
  pkill -x Nido 2>/dev/null || true
  rm -rf /Applications/Nido.app
  cp -R "$APP" /Applications/Nido.app
  echo "Installed /Applications/Nido.app"
  open /Applications/Nido.app
fi
