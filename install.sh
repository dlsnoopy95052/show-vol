#!/bin/zsh
# One-shot installer for ShowVol: fixes the CLT toolchain if needed, builds,
# installs to /Applications, enables start-at-login, and launches.
set -e
cd "$(dirname "$0")"
DUP=/Library/Developer/CommandLineTools/usr/include/swift/bridging.modulemap
T=$(mktemp -d)

compiles() {
  echo 'import Foundation' > $T/t.swift
  swiftc $T/t.swift -o $T/t >/dev/null 2>&1
}

echo "==> Checking Swift toolchain"
command -v swiftc >/dev/null || { echo "swiftc missing; running xcode-select --install"; xcode-select --install; exit 1; }
if ! compiles; then
  if [ -f "$DUP" ]; then
    echo "==> Toolchain broken (duplicate SwiftBridging modulemap). Moving it aside (needs sudo)."
    sudo mv "$DUP" "$DUP.bak"
  fi
  if ! compiles; then
    echo "Toolchain still broken. Reinstall Command Line Tools:"
    echo "  sudo rm -rf /Library/Developer/CommandLineTools && xcode-select --install"
    exit 1
  fi
fi

echo "==> Building (first build can take a few minutes)"
./build.sh

echo "==> Installing to /Applications"
pkill -x ShowVol 2>/dev/null || true
rm -rf /Applications/ShowVol.app
cp -R ShowVol.app /Applications/
xattr -dr com.apple.quarantine /Applications/ShowVol.app 2>/dev/null || true

echo "==> Enabling start at login"
osascript -e 'tell application "System Events" to delete (every login item whose name is "ShowVol")' >/dev/null 2>&1 || true
osascript -e 'tell application "System Events" to make login item at end with properties {path:"/Applications/ShowVol.app", hidden:true}' >/dev/null 2>&1 \
  || echo "   (couldn't add login item automatically; add it in System Settings > General > Login Items)"

echo "==> Launching"
open /Applications/ShowVol.app
echo "Done. Look for the drive icon in the menu bar."
