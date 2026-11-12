#!/bin/zsh
# Builds Dockfold.app (release) into ./build and optionally installs it in /Applications.
# Usage: scripts/build-app.sh [--install]
set -euo pipefail

ROOT="${0:A:h:h}"
BUILD="$ROOT/build"
APP="$BUILD/Dockfold.app"
TEMPLATE="$APP/Contents/Resources/DockfoldFolder.app"

cd "$ROOT"
swift build -c release
BIN="$(swift build -c release --show-bin-path)"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN/Dockfold" "$APP/Contents/MacOS/Dockfold"
cp "$ROOT/config/Dockfold-Info.plist" "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"

# Folder template: copied and customised by Dockfold for every folder.
mkdir -p "$TEMPLATE/Contents/MacOS" "$TEMPLATE/Contents/Resources"
cp "$BIN/DockfoldFolder" "$TEMPLATE/Contents/MacOS/DockfoldFolder"
cp "$ROOT/config/DockfoldFolder-Info.plist" "$TEMPLATE/Contents/Info.plist"
printf 'APPL????' > "$TEMPLATE/Contents/PkgInfo"

# App icon, rendered by the app itself.
ICONSET="$BUILD/AppIcon.iconset"
rm -rf "$ICONSET"
"$BIN/Dockfold" --export-iconset "$ICONSET"
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
rm -rf "$ICONSET"

# Ad-hoc signatures, inner bundle first.
codesign --force --sign - "$TEMPLATE"
codesign --force --sign - --identifier local.dockfold.manager "$APP"
echo "Built $APP"

if [[ "${1:-}" == "--install" ]]; then
  pkill -x Dockfold 2>/dev/null || true
  rm -rf /Applications/Dockfold.app
  cp -R "$APP" /Applications/Dockfold.app
  echo "Installed /Applications/Dockfold.app"
  open /Applications/Dockfold.app
fi
