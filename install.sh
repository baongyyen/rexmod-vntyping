#!/bin/sh
# Build and install; --no-agent patches once; --remove unloads and unpatches.
set -eu
ROOT="$(cd "$(dirname "$0")" && pwd)"
PREFIX="$HOME/Library/Application Support/rexmod-vntyping"
APP="${REX_APP:-/Applications/Rex Beta.app}"
LABEL="dev.rexmod-vntyping.repatch"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
SERVICE="gui/$(id -u)/$LABEL"
MODE="${1:-install}"
case "$MODE" in
  install|--no-agent|--remove) ;;
  --help|-h) echo "usage: install.sh [--no-agent|--remove]"; exit 0 ;;
  *) echo "usage: install.sh [--no-agent|--remove]" >&2; exit 2 ;;
esac
stop_agent() {
  if [ -f "$PLIST" ]; then
    if /bin/launchctl print "$SERVICE" >/dev/null 2>&1; then
      /bin/launchctl bootout "$SERVICE"
    fi
    rm "$PLIST"
  fi
}
if [ "$MODE" = "--remove" ]; then
  stop_agent
  REX_APP="$APP" /bin/sh "$ROOT/patch.sh" --remove
  echo "Patch removal completed; installation files and backups were retained."
  exit 0
fi
[ "$(uname -s)" = Darwin ] && [ "$(uname -m)" = arm64 ] || {
  echo "An Apple silicon Mac with a native arm64 shell is required" >&2; exit 1;
}
[ "$(sw_vers -productVersion | cut -d. -f1)" -ge 15 ] || {
  echo "macOS 15 or later is required" >&2; exit 1;
}
[ -f "$APP/Contents/MacOS/Rex" ] || { echo "Rex not found at $APP" >&2; exit 1; }
/usr/bin/xcrun --find clang >/dev/null
/usr/bin/python3 -I -c 'import plistlib, struct'
for source in src/RexVietnameseInput.m scripts/dylib-load-command.py patch.sh; do
  [ -f "$ROOT/$source" ] || { echo "Missing source: $ROOT/$source" >&2; exit 1; }
done
mkdir -p "$PREFIX"
BUILD="$(mktemp -d "$PREFIX/.build.XXXXXX")"
trap 'rm -rf "$BUILD"' EXIT
trap 'exit 1' HUP INT TERM
/usr/bin/xcrun clang -dynamiclib -fobjc-arc -arch arm64 -framework AppKit \
  -mmacosx-version-min=15.0 "-Wl,-install_name,$PREFIX/RexVietnameseInput.dylib" \
  -o "$BUILD/RexVietnameseInput.dylib" "$ROOT/src/RexVietnameseInput.m"
/usr/bin/codesign -f -s - "$BUILD/RexVietnameseInput.dylib"
/usr/bin/codesign --verify "$BUILD/RexVietnameseInput.dylib"
stop_agent
for source in install.sh patch.sh scripts/dylib-load-command.py src/RexVietnameseInput.m; do
  if [ "$ROOT/$source" != "$PREFIX/$source" ]; then
    mkdir -p "$(dirname "$PREFIX/$source")"
    case "$source" in *.m) permission=644 ;; *) permission=755 ;; esac
    /usr/bin/install -m "$permission" "$ROOT/$source" "$PREFIX/$source.new"
    mv "$PREFIX/$source.new" "$PREFIX/$source"
  fi
done
mv "$BUILD/RexVietnameseInput.dylib" "$PREFIX/RexVietnameseInput.dylib"
REX_APP="$APP" /bin/sh "$PREFIX/patch.sh"
if [ "$MODE" = install ]; then
  mkdir -p "$(dirname "$PLIST")"
  /usr/bin/python3 -I - "$PLIST" "$PREFIX" "$APP" "$LABEL" <<'PY'
import plistlib
import sys
from pathlib import Path
plist, prefix, app, label = sys.argv[1:]
job = {
    "Label": label,
    "ProgramArguments": ["/bin/sh", str(Path(prefix) / "patch.sh")],
    "EnvironmentVariables": {"REX_APP": app},
    "WatchPaths": [str(Path(app) / "Contents/Info.plist")],
    "StartInterval": 600,
    "RunAtLoad": True,
    "ThrottleInterval": 30,
    "StandardOutPath": str(Path(prefix) / "agent.log"),
    "StandardErrorPath": str(Path(prefix) / "agent.log"),
}
Path(plist).write_bytes(plistlib.dumps(job))
PY
  /bin/launchctl bootstrap "gui/$(id -u)" "$PLIST"
  echo "Automatic re-patching registered as $LABEL."
fi
echo "Installed. Quit and reopen Rex, then verify real keyboard input."
