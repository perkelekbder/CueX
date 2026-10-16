#!/bin/bash
set -euo pipefail

project_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$project_dir"

swift build -c release
binary_dir="$(swift build -c release --show-bin-path)"
build_stamp="$(date +%Y-%m-%d-%H%M%S)"
snapshot_dir="$project_dir/Builds/CueX-$build_stamp"
app_bundle="$snapshot_dir/CueX.app"
mkdir -p "$app_bundle/Contents/MacOS"
cp "$binary_dir/CueX" "$app_bundle/Contents/MacOS/CueX"

cat > "$app_bundle/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key><string>en</string>
    <key>CFBundleExecutable</key><string>CueX</string>
    <key>CFBundleIdentifier</key><string>com.cuex.app</string>
    <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
    <key>CFBundleName</key><string>CueX</string>
    <key>CFBundleDisplayName</key><string>CueX</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>0.1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSUIElement</key><false/>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSPrincipalClass</key><string>NSApplication</string>
</dict>
</plist>
PLIST

codesign --force --sign - "$app_bundle"
codesign --verify --strict "$app_bundle"
ditto -c -k --sequesterRsrc --keepParent "$app_bundle" "$snapshot_dir/CueX.zip"
printf 'App: %s\nArchive: %s\n' "$app_bundle" "$snapshot_dir/CueX.zip"
