#!/usr/bin/env bash
# Usage: Scripts/package_app.sh [debug|release|smoke]
#   smoke  takes the already built build/<APP_NAME>.app, copies it to a temp folder, deletes .build
#          and runs it with --smoke, so resources that only resolve on the build machine are caught.
# Builds the app and assembles build/<APP_NAME>.app, ad-hoc signed.
# Release builds also produce build/Sergnanese-Social-<version>.dmg (app + Applications shortcut).
# Needs only the Command Line Tools: swift, codesign, hdiutil, ditto.
set -euo pipefail

CONF=${1:-debug}
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"

source "$ROOT/version.env"

if [[ "$CONF" == "smoke" ]]; then
  SRC_APP="$ROOT/build/${APP_NAME}.app"
  [[ -d "$SRC_APP" ]] || { echo "ERROR: $SRC_APP not found; run package_app.sh release first." >&2; exit 1; }
  COPY_DIR=$(mktemp -d)
  trap 'rm -rf "$COPY_DIR"' EXIT
  ditto "$SRC_APP" "$COPY_DIR/${APP_NAME}.app"
  rm -rf "$ROOT/.build"
  codesign --verify --deep --strict "$COPY_DIR/${APP_NAME}.app"
  OUT=$(cd "$COPY_DIR" && "./${APP_NAME}.app/Contents/MacOS/SergnaneseSocial" --smoke)
  echo "$OUT"
  grep -q "^SMOKE OK$" <<<"$OUT" || { echo "ERROR: smoke check did not print SMOKE OK" >&2; exit 1; }
  exit 0
fi
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

cp "$ROOT/Packaging/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"

xattr -cr "$APP"
codesign --force --sign - "$APP"
codesign --verify --deep --strict "$APP"

echo "Created $APP"

if [[ "$CONF" == "release" ]]; then
  DMG="$ROOT/build/${APP_NAME// /-}-${VERSION}.dmg"
  STAGE=$(mktemp -d)
  trap 'rm -rf "$STAGE"' EXIT
  ditto "$APP" "$STAGE/${APP_NAME}.app"
  ln -s /Applications "$STAGE/Applications"
  rm -f "$DMG"
  hdiutil create -volname "$APP_NAME" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
  echo "Created $DMG"
fi
