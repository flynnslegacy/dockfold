#!/bin/zsh
# Builds Dockfold.app (release) into ./build and optionally installs it in /Applications.
# Usage: scripts/build-app.sh [--install]
#
# Environment (used by scripts/release.sh):
#   DOCKFOLD_SIGN_IDENTITY  signing identity; "-" (default) signs ad hoc
#   DOCKFOLD_HARDENED=1     hardened runtime (always on with a real identity)
#   DOCKFOLD_UNIVERSAL=1    Apple silicon + Intel binary
#   DOCKFOLD_VERSION        marketing version written into Info.plist
set -euo pipefail

ROOT="${0:A:h:h}"
BUILD="$ROOT/build"
APP="$BUILD/Dockfold.app"
TEMPLATE="$APP/Contents/Resources/DockfoldFolder.app"
IDENTITY="${DOCKFOLD_SIGN_IDENTITY:--}"

ARCH_FLAGS=()
[[ "${DOCKFOLD_UNIVERSAL:-0}" == "1" ]] && ARCH_FLAGS=(--arch arm64 --arch x86_64)

cd "$ROOT"
swift build -c release "${ARCH_FLAGS[@]}"
BIN="$(swift build -c release "${ARCH_FLAGS[@]}" --show-bin-path)"

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

# Version: marketing version from the environment, build number from the commit count.
BUILD_NUMBER="$(git -C "$ROOT" rev-list --count HEAD 2>/dev/null || echo 1)"
for PLIST in "$APP/Contents/Info.plist" "$TEMPLATE/Contents/Info.plist"; do
  [[ -n "${DOCKFOLD_VERSION:-}" ]] && /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $DOCKFOLD_VERSION" "$PLIST"
  /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUMBER" "$PLIST"
done

# App icon, rendered by the app itself.
ICONSET="$BUILD/AppIcon.iconset"
rm -rf "$ICONSET"
"$BIN/Dockfold" --export-iconset "$ICONSET"
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
rm -rf "$ICONSET"

# Signatures, inner bundle first. Notarization needs the hardened runtime and a secure timestamp.
SIGN_FLAGS=(--force --sign "$IDENTITY")
if [[ "$IDENTITY" != "-" ]]; then
  SIGN_FLAGS+=(--options runtime --timestamp)
elif [[ "${DOCKFOLD_HARDENED:-0}" == "1" ]]; then
  SIGN_FLAGS+=(--options runtime)
fi
codesign "${SIGN_FLAGS[@]}" "$TEMPLATE"
codesign "${SIGN_FLAGS[@]}" --identifier local.dockfold.manager "$APP"
echo "Built $APP"

if [[ "${1:-}" == "--install" ]]; then
  pkill -x Dockfold 2>/dev/null || true
  rm -rf /Applications/Dockfold.app
  cp -R "$APP" /Applications/Dockfold.app
  echo "Installed /Applications/Dockfold.app"
  open /Applications/Dockfold.app
fi
