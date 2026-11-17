#!/usr/bin/env bash
# Usage: Scripts/run.sh [args]   (args such as --mock or --smoke are passed to the app)
# Builds a debug .app, then launches it.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
source "$ROOT/version.env"

APP="$ROOT/build/${APP_NAME}.app"
pkill -f "${APP_NAME}.app/Contents/MacOS/" 2>/dev/null || true

"$ROOT/Scripts/package_app.sh" debug

if [[ $# -gt 0 ]]; then
  open -n "$APP" --args "$@"
else
  open -n "$APP"
fi

for _ in {1..15}; do
  if pgrep -f "${APP_NAME}.app/Contents/MacOS/" >/dev/null 2>&1; then
    echo "OK: ${APP_NAME} is running."
    exit 0
  fi
  sleep 0.4
done
echo "ERROR: app exited immediately." >&2
exit 1
