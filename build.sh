#!/bin/bash
# Builds mGBAHold.app next to this script.
set -e
cd "$(dirname "$0")"

APP="mGBAHold.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

swiftc -O -o "$APP/Contents/MacOS/mGBAHold" main.swift

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>            <string>mGBAHold</string>
    <key>CFBundleDisplayName</key>     <string>mGBAHold</string>
    <key>CFBundleIdentifier</key>      <string>com.jashith.mgbahold</string>
    <key>CFBundleExecutable</key>      <string>mGBAHold</string>
    <key>CFBundlePackageType</key>     <string>APPL</string>
    <key>CFBundleShortVersionString</key> <string>1.0</string>
    <key>CFBundleVersion</key>         <string>1</string>
    <key>LSMinimumSystemVersion</key>  <string>13.0</string>
    <key>LSUIElement</key>             <true/>
    <key>NSPrincipalClass</key>        <string>NSApplication</string>
    <key>NSHighResolutionCapable</key> <true/>
</dict>
</plist>
PLIST

codesign --force --sign - "$APP" >/dev/null 2>&1 || true
echo "Built $(pwd)/$APP"
