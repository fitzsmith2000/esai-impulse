#!/bin/zsh
# Build ESAI Impulse with SwiftPM and assemble an ad-hoc signed .app in build/.
set -euo pipefail
root="${0:A:h}"; cd "$root"
app="$root/build/ESAI Impulse.app"
# SwiftPM (Package.swift) works with full Xcode; plain swiftc is the fallback for
# Command Line Tools installs whose PackageDescription library is mismatched.
mkdir -p build
bin="$root/build/ESAIImpulse"
if [[ "${USE_SWIFTPM:-0}" == 1 ]]; then
  swift build -c release --arch arm64
  bin="$(swift build -c release --arch arm64 --show-bin-path)/ESAIImpulse"
else
  swiftc -swift-version 5 -target arm64-apple-macos13.0 -O -parse-as-library \
    -framework AppKit -framework SwiftUI -framework ServiceManagement -framework UserNotifications -framework Security \
    Sources/ESAIImpulse/*.swift -o "$bin"
fi
"$bin" --self-test
rm -rf "$app"; mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources/Licenses"
cp "$bin" "$app/Contents/MacOS/ESAIImpulse"
cp Resources/Info.plist "$app/Contents/Info.plist"
cp Resources/AppIcon.icns "$app/Contents/Resources/AppIcon.icns"
cp Resources/StatusTemplate.pdf "$app/Contents/Resources/StatusTemplate.pdf"
cp Resources/Licenses/* "$app/Contents/Resources/Licenses/"
cp THIRD_PARTY_NOTICES.md LICENSE "$app/Contents/Resources/"
codesign --force --deep -s - "$app"
codesign --verify --deep --strict "$app"
print -r -- "$app"
