#!/bin/zsh
# Builds "Sidebar Todos.app" (release) into ./build and, with --install, copies it to /Applications.
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT=$PWD
APP="$ROOT/build/Sidebar Todos.app"

swift build -c release
BIN="$(swift build -c release --show-bin-path)/SidebarTodos"

# Icon (regenerated only when the drawing script changes).
ICNS="$ROOT/build/AppIcon.icns"
if [[ ! -f $ICNS || scripts/make_icon.swift -nt $ICNS ]]; then
  ICONSET="$ROOT/build/AppIcon.iconset"
  rm -rf "$ICONSET" && mkdir -p "$ICONSET"
  swift scripts/make_icon.swift "$ROOT/build/icon_1024.png" >/dev/null
  for s in 16 32 128 256 512; do
    sips -z $s $s "$ROOT/build/icon_1024.png" --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
    d=$((s * 2))
    sips -z $d $d "$ROOT/build/icon_1024.png" --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
  done
  iconutil -c icns "$ICONSET" -o "$ICNS"
fi

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/SidebarTodos"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp "$ICNS" "$APP/Contents/Resources/AppIcon.icns"
codesign --force --sign - --timestamp=none "$APP"
echo "Built: $APP"

if [[ ${1:-} == --install ]]; then
  DEST="/Applications/Sidebar Todos.app"
  osascript -e 'tell application id "com.mapostolides.SidebarTodos" to quit' 2>/dev/null || true
  sleep 1
  rm -rf "$DEST"
  cp -R "$APP" "$DEST"
  touch "$DEST"
  /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$DEST"
  echo "Installed: $DEST"
fi
