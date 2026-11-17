#!/usr/bin/env bash
# Usage: Scripts/package_app.sh [debug|release]
# Builds the app and assembles build/<APP_NAME>.app, ad-hoc signed.
# T1.5 adds the icon and the .dmg for release builds.
set -euo pipefail

CONF=${1:-debug}
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"

source "$ROOT/version.env"
EXECUTABLE="SergnaneseSocial"
ARCH=arm64

swift build -c "$CONF" --arch "$ARCH" --product "$EXECUTABLE"
BIN_DIR=$(swift build -c "$CONF" --arch "$ARCH" --show-bin-path)

APP="$ROOT/build/${APP_NAME}.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/$EXECUTABLE" "$APP/Contents/MacOS/$EXECUTABLE"
chmod +x "$APP/Contents/MacOS/$EXECUTABLE"

# Info.plist from the template.
sed -e "s|__APP_NAME__|${APP_NAME}|g" \
  -e "s|__BUNDLE_ID__|${BUNDLE_ID}|g" \
  -e "s|__EXECUTABLE__|${EXECUTABLE}|g" \
  -e "s|__VERSION__|${VERSION}|g" \
  -e "s|__BUILD__|${BUILD}|g" \
  "$ROOT/Packaging/Info.plist" > "$APP/Contents/Info.plist"

# Plain resource folders (never Bundle.module).
for dir in Templates Seed Fixtures; do
  if [[ -d "$ROOT/Resources/$dir" ]]; then
    cp -R "$ROOT/Resources/$dir" "$APP/Contents/Resources/$dir"
  fi
done

# An it.lproj folder marks the app as Italian, so system menus and panels are in Italian.
mkdir -p "$APP/Contents/Resources/it.lproj"
: > "$APP/Contents/Resources/it.lproj/InfoPlist.strings"

xattr -cr "$APP"
codesign --force --sign - "$APP"

echo "Created $APP"
