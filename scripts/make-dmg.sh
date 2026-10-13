#!/bin/zsh
# Release packaging: notarize the app → signed DMG → notarize the DMG.
# Run scripts/build-app.sh first.
#   zsh scripts/make-dmg.sh                 notarized DMG in dist/
#   zsh scripts/make-dmg.sh --no-notarize   signed DMG only (local tests)
#
# One time, for notarization (asks for an app-specific password from account.apple.com):
#   xcrun notarytool store-credentials everywhere-notary --apple-id <email> --team-id 8ZN67F8SW8
set -euo pipefail
cd "${0:A:h:h}"
APP_NAME="What's Next"
IDENTITY="${SIGN_IDENTITY:-Developer ID Application: massimo pozzi (8ZN67F8SW8)}"
PROFILE="${NOTARY_PROFILE:-everywhere-notary}"
APP="dist/$APP_NAME.app"
[[ -d "$APP" ]] || { print "Missing $APP: run scripts/build-app.sh first."; exit 1 }
VERSION=$(defaults read "$PWD/$APP/Contents/Info" CFBundleShortVersionString)
DMG="dist/WhatsNext-$VERSION.dmg"
NOTARIZE=1
[[ "${1:-}" == "--no-notarize" ]] && NOTARIZE=0

notarize() {
  xcrun notarytool submit "$1" --keychain-profile "$PROFILE" --wait
  xcrun stapler staple "$2"
}

codesign --verify --deep --strict "$APP"
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

if (( NOTARIZE )); then
  print "→ Notarizing the app…"
  ditto -c -k --keepParent "$APP" "$WORK/app.zip"
  notarize "$WORK/app.zip" "$APP"
fi

print "→ Creating the DMG…"
mkdir -p "$WORK/dmg"
ditto "$APP" "$WORK/dmg/$APP_NAME.app"
ln -s /Applications "$WORK/dmg/Applications"
rm -f "$DMG"
hdiutil create -volname "What's Next?" -srcfolder "$WORK/dmg" -fs HFS+ -format UDZO -ov "$DMG" >/dev/null
codesign --force --timestamp --sign "$IDENTITY" "$DMG"

if (( NOTARIZE )); then
  print "→ Notarizing the DMG…"
  notarize "$DMG" "$DMG"
  spctl -a -t open --context context:primary-signature -v "$DMG"
fi
shasum -a 256 "$DMG"
print "OK: $DMG"
