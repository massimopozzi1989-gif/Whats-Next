#!/bin/zsh
# Package dist/What's Next.app into a signed, notarized and stapled DMG.
# Run scripts/build-app.sh first. Notarization uses a notarytool keychain profile:
#   xcrun notarytool store-credentials whats-next-notary --apple-id YOU@EXAMPLE.COM --team-id 8ZN67F8SW8
set -euo pipefail
cd "${0:A:h:h}"
APP_NAME="What's Next"
PROFILE="${NOTARY_PROFILE:-whats-next-notary}"
APP="dist/$APP_NAME.app"
[[ -d "$APP" ]] || { print "Missing $APP: run scripts/build-app.sh first."; exit 1 }
VERSION=$(defaults read "$PWD/$APP/Contents/Info" CFBundleShortVersionString)
DMG="dist/WhatsNext-$VERSION.dmg"

codesign --verify --deep --strict "$APP"
STAGE=$(mktemp -d)
trap 'rm -rf "$STAGE"' EXIT
ditto "$APP" "$STAGE/$APP_NAME.app"
ln -s /Applications "$STAGE/Applications"
rm -f "$DMG"
hdiutil create -volname "What's Next?" -srcfolder "$STAGE" -fs HFS+ -format UDZO -ov "$DMG" >/dev/null
codesign --sign "Developer ID Application" --timestamp "$DMG"

if xcrun notarytool history --keychain-profile "$PROFILE" >/dev/null 2>&1; then
  xcrun notarytool submit "$DMG" --keychain-profile "$PROFILE" --wait
  xcrun stapler staple "$DMG"
  xcrun stapler validate "$DMG"
  spctl --assess --type open --context context:primary-signature --verbose=2 "$DMG"
else
  print "Notarization skipped: no notarytool profile \"$PROFILE\" in the keychain."
fi
shasum -a 256 "$DMG"
print "DMG ready: $PWD/$DMG"
