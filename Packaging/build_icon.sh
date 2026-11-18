#!/usr/bin/env bash
# Regenerates Packaging/AppIcon.icns from Packaging/crest-source.png (Command Line Tools only:
# swift, sips, iconutil). Run it when the crest changes; the .icns is committed.
set -euo pipefail
DIR=$(cd "$(dirname "$0")" && pwd)
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
SRC=$(ls "$DIR"/crest-source.* | head -1)
swift "$DIR/make_icon.swift" "$SRC" "$WORK/master.png"
SET="$WORK/AppIcon.iconset"
mkdir "$SET"
for s in 16 32 128 256 512; do
  sips -z $s $s "$WORK/master.png" --out "$SET/icon_${s}x${s}.png" >/dev/null
  sips -z $((s * 2)) $((s * 2)) "$WORK/master.png" --out "$SET/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$SET" -o "$DIR/AppIcon.icns"
echo "Created $DIR/AppIcon.icns"
