#!/bin/zsh
set -e
cd "$(dirname "$0")"
APP=ShowVol.app
rm -rf $APP; mkdir -p $APP/Contents/MacOS
swiftc -O src/main.swift -o $APP/Contents/MacOS/ShowVol
mkdir -p $APP/Contents/Resources; cp resources/AppIcon.icns $APP/Contents/Resources/
cat > $APP/Contents/Info.plist <<P
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleName</key><string>ShowVol</string>
<key>CFBundleIdentifier</key><string>local.showvol</string>
<key>CFBundleExecutable</key><string>ShowVol</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>LSUIElement</key><true/>
</dict></plist>
P
codesign --force --sign - $APP 2>/dev/null || true
echo "Built $APP"
