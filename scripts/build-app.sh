#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
APP_NAME="What's Next"
LS_REGISTER=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
xcodegen generate
xcodebuild -project DoveSonoArrivato.xcodeproj -scheme DoveSonoArrivato \
  -configuration Release -derivedDataPath .xcode-build build > .xcode-build.log 2>&1 || {
  tail -60 .xcode-build.log
  exit 1
}
mkdir -p dist
STAGING=$(mktemp -d "$PWD/dist/.staging-XXXXXX")
ditto ".xcode-build/Build/Products/Release/$APP_NAME.app" "$STAGING/$APP_NAME.app"
codesign --verify --deep --strict "$STAGING/$APP_NAME.app"
for OLD_NAME in "$APP_NAME" 'Post It!' 'Dove sono arrivato'; do
  if [[ -d "dist/$OLD_NAME.app" ]]; then
    "$LS_REGISTER" -u "$PWD/dist/$OLD_NAME.app" || true
    mv "dist/$OLD_NAME.app" "dist/previous-build-$(date +%Y%m%d-%H%M%S)-$OLD_NAME"
  fi
  "$LS_REGISTER" -u "$PWD/.xcode-build/Build/Products/Release/$OLD_NAME.app" || true
  /usr/bin/pluginkit -r "$PWD/.xcode-build/Build/Products/Release/$OLD_NAME.app/Contents/PlugIns/PostItWidget.appex" 2>/dev/null || true
done
mv "$STAGING/$APP_NAME.app" "dist/$APP_NAME.app"
rmdir "$STAGING"
# Keep only the three most recent previous builds; older copies are just disk weight.
for OLD in dist/previous-build-*(N/On[4,-1]); do rm -rf "$OLD"; done
"$LS_REGISTER" -f "$PWD/dist/$APP_NAME.app"
/usr/bin/pluginkit -a "$PWD/dist/$APP_NAME.app/Contents/PlugIns/PostItWidget.appex"
# WidgetKit can keep an old extension process alive after its bundle is replaced.
/usr/bin/pkill -x PostItWidget || true
print "App con widget pronta: $PWD/dist/$APP_NAME.app"
