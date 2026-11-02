#!/bin/sh
# Apply or remove this mod on a staged, independently signed copy of Rex.
set -eu
HERE="$(cd "$(dirname "$0")" && pwd)"
PREFIX="$HOME/Library/Application Support/rexmod-vntyping"
APP="${REX_APP:-/Applications/Rex Beta.app}"
BIN="$APP/Contents/MacOS/Rex"
DYLIB="$PREFIX/RexVietnameseInput.dylib"
HELPER="$HERE/scripts/dylib-load-command.py"
MODE="${1:-add}"
case "$MODE" in add|--remove|--check) ;; *) echo "usage: patch.sh [--check|--remove]" >&2; exit 2 ;; esac
[ -f "$BIN" ] || { echo "Rex executable not found: $BIN" >&2; exit 1; }

check_patch() {
  libraries=$(/usr/bin/otool -L "$BIN") || { echo "Cannot inspect $BIN" >&2; exit 1; }
  printf '%s\n' "$libraries" | grep -Fq "$(printf '\t')$DYLIB ("
}
if [ "$MODE" = "--check" ]; then
  if check_patch; then echo present; else echo absent; exit 3; fi
  exit 0
fi
[ -f "$HELPER" ] || { echo "Missing load-command helper: $HELPER" >&2; exit 1; }
if [ "$MODE" = add ]; then
  [ -f "$DYLIB" ] || { echo "Build the dylib with install.sh first" >&2; exit 1; }
  /usr/bin/codesign --verify "$DYLIB"
fi
mkdir -p "$PREFIX"
LOCK="$PREFIX/.patch.lock"
mkdir "$LOCK" 2>/dev/null || { echo "Another patch is running; retry later" >&2; exit 75; }
STAGE=""
REPLACED=""
cleanup() {
  if [ ! -e "$APP" ] && [ -n "$REPLACED" ] && [ -d "$REPLACED/Rex Beta.app" ]; then
    mv "$REPLACED/Rex Beta.app" "$APP" || echo "Restore the app from $REPLACED manually" >&2
  fi
  [ -z "$STAGE" ] || rm -rf "$STAGE"
  rmdir "$LOCK"
}
trap cleanup EXIT
trap 'exit 1' HUP INT TERM
if check_patch; then
  [ "$MODE" = "--remove" ] || { echo "Patch already present"; exit 0; }
else
  [ "$MODE" != "--remove" ] || { echo "Patch already absent"; exit 0; }
fi
/usr/bin/codesign --verify --strict "$APP"
STAGE="$(mktemp -d "$PREFIX/.stage.XXXXXX")"
S="$STAGE/Rex Beta.app"
/usr/bin/ditto "$APP" "$S"
if /usr/bin/lipo -info "$S/Contents/MacOS/Rex" | grep -q '^Architectures in the fat file:'; then
  /usr/bin/lipo "$S/Contents/MacOS/Rex" -thin arm64 -output "$STAGE/Rex.arm64"
  mv "$STAGE/Rex.arm64" "$S/Contents/MacOS/Rex"
fi
if [ "$MODE" = "--remove" ]; then
  /usr/bin/python3 -I "$HELPER" --remove "$S/Contents/MacOS/Rex" "$DYLIB"
else
  /usr/bin/python3 -I "$HELPER" "$S/Contents/MacOS/Rex" "$DYLIB"
fi
ENT="$STAGE/entitlements.plist"
/usr/bin/codesign -d --entitlements - --xml "$APP" > "$ENT" 2> "$STAGE/signature.log"
/usr/bin/python3 -I - "$ENT" "$MODE" <<'PY'
from pathlib import Path
import plistlib
import sys
path = Path(sys.argv[1])
raw = path.read_bytes()
entitlements = plistlib.loads(raw) if raw else {}
if sys.argv[2] == "add":
    entitlements["com.apple.security.cs.disable-library-validation"] = True
path.write_bytes(plistlib.dumps(entitlements))
PY
/usr/bin/codesign -f -s - --options runtime --entitlements "$ENT" "$S"
/usr/bin/codesign --verify --strict "$S"
if [ "$MODE" = add ] && [ ! -e "$PREFIX/backup" ]; then
  /usr/bin/ditto "$APP" "$STAGE/backup/Rex Beta.app"
  mv "$STAGE/backup" "$PREFIX/backup"
fi
# Preserve displaced bundles until the user has restarted and approves cleanup.
mkdir -p "$PREFIX/replaced"
REPLACED="$(mktemp -d "$PREFIX/replaced/swap.XXXXXX")"
mv "$APP" "$REPLACED/Rex Beta.app"
mv "$S" "$APP"
echo "Updated $APP; quit and reopen it to load the change."
if [ "$APP" = "/Applications/Rex Beta.app" ]; then
  /usr/bin/osascript -e 'display notification "Quit Rex (⌘Q) and reopen it to apply the typing mod change." with title "rexmod-vntyping"' >/dev/null 2>&1 || true
fi
