#!/bin/zsh
# Builds Dockfold for distribution outside the Mac App Store:
# Developer ID signature, Apple notarization, stapled ticket, signed and notarized DMG.
#
# Usage: scripts/release.sh <version>        e.g. scripts/release.sh 1.0.0
#
# One-time setup:
#   1. Certificate: Xcode › Réglages › Comptes › (ton équipe) › Gérer les certificats › + › Developer ID Application
#   2. Notarization credentials, stored in the keychain (app-specific password from account.apple.com):
#        xcrun notarytool store-credentials dockfold-notary --apple-id <ton Apple ID> --team-id <ton Team ID>
set -euo pipefail

VERSION="${1:?Usage: scripts/release.sh <version>}"
ROOT="${0:A:h:h}"
BUILD="$ROOT/build"
APP="$BUILD/Dockfold.app"
DMG="$BUILD/Dockfold-$VERSION.dmg"
PROFILE="${DOCKFOLD_NOTARY_PROFILE:-dockfold-notary}"

IDENTITY="$(security find-identity -v -p codesigning | awk -F'"' '/Developer ID Application/ {print $2; exit}')"
if [[ -z "$IDENTITY" ]]; then
  echo "Aucun certificat « Developer ID Application » dans le trousseau."
  echo "Crée-le dans Xcode › Réglages › Comptes › Gérer les certificats › + › Developer ID Application."
  exit 1
fi
if ! xcrun notarytool history --keychain-profile "$PROFILE" >/dev/null 2>&1; then
  echo "Identifiants de notarisation « $PROFILE » introuvables. Enregistre-les une fois avec :"
  echo "  xcrun notarytool store-credentials $PROFILE --apple-id <ton Apple ID> --team-id <ton Team ID>"
  exit 1
fi

# Submits a file to Apple's notary service and stops with the log if it is refused.
notarize() {
  local file="$1" result id outcome
  result="$(xcrun notarytool submit "$file" --keychain-profile "$PROFILE" --wait --output-format json)"
  id="$(print -r -- "$result" | plutil -extract id raw -o - -)"
  outcome="$(print -r -- "$result" | plutil -extract status raw -o - -)"
  echo "Notarisation de ${file:t} : $outcome"
  if [[ "$outcome" != "Accepted" ]]; then
    xcrun notarytool log "$id" --keychain-profile "$PROFILE"
    exit 1
  fi
}

echo "Signature avec : $IDENTITY"
DOCKFOLD_SIGN_IDENTITY="$IDENTITY" DOCKFOLD_UNIVERSAL=1 DOCKFOLD_VERSION="$VERSION" "$ROOT/scripts/build-app.sh"
codesign --verify --deep --strict "$APP"

# 1. The app: notarize a zip of it, then staple the ticket so it also opens offline.
ZIP="$BUILD/Dockfold-$VERSION-notarize.zip"
ditto -c -k --keepParent "$APP" "$ZIP"
notarize "$ZIP"
rm -f "$ZIP"
xcrun stapler staple "$APP"

# 2. The DMG: the app plus a shortcut to /Applications, signed, notarized and stapled too.
STAGE="$BUILD/dmg"
rm -rf "$STAGE" "$DMG"
mkdir -p "$STAGE"
ditto "$APP" "$STAGE/Dockfold.app"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "Dockfold" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
rm -rf "$STAGE"
codesign --force --timestamp --sign "$IDENTITY" "$DMG"
notarize "$DMG"
xcrun stapler staple "$DMG"

# 3. Gatekeeper's own verdict, as a downloaded copy would get it.
spctl --assess --type execute --verbose=2 "$APP"
spctl --assess --type open --context context:primary-signature --verbose=2 "$DMG"
echo "SHA-256 : $(shasum -a 256 "$DMG" | cut -d' ' -f1)"
echo "Prêt : $DMG"
