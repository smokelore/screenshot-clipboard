#!/bin/zsh
# Builds build/Screenshot Clipboard.app; with --install, replaces the copy in /Applications and relaunches it.
set -euo pipefail
cd "${0:A:h}"

app="build/Screenshot Clipboard.app"
rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp Resources/Info.plist "$app/Contents/Info.plist"
commit=$(git rev-parse --short HEAD)
[[ -z $(git status --porcelain) ]] || commit+="-modified"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $commit" "$app/Contents/Info.plist" 2>/dev/null \
  || /usr/libexec/PlistBuddy -c "Add :CFBundleVersion string $commit" "$app/Contents/Info.plist"
for f in Resources/*(N); do [[ $f == Resources/Info.plist ]] || cp "$f" "$app/Contents/Resources/"; done
swiftc -O -o "$app/Contents/MacOS/ScreenshotClipboard" Sources/*.swift
# A stable identity keeps macOS privacy grants across rebuilds; ad-hoc signatures change with every build.
identity="Screenshot Clipboard Local Signing"
security find-certificate -c "$identity" >/dev/null 2>&1 || identity=-
codesign --force --sign "$identity" "$app"

if [[ ${1:-} == --install ]]; then
  pkill -x ScreenshotClipboard || true
  rm -rf "/Applications/Screenshot Clipboard.app"
  cp -R "$app" /Applications/
  open "/Applications/Screenshot Clipboard.app"
fi
