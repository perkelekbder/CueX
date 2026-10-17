#!/bin/bash
set -euo pipefail

project_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$project_dir"

# SwiftUI compiler plug-ins require the full Xcode toolchain. Installing
# Command Line Tools for Git may change xcode-select without removing Xcode.
if [[ -z "${DEVELOPER_DIR:-}" ]]; then
    selected_developer_dir="$(xcode-select -p)"
    if [[ "$selected_developer_dir" == */CommandLineTools ]]; then
        if [[ -d /Applications/Xcode.app/Contents/Developer ]]; then
            export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
        else
            printf 'Install Xcode or set DEVELOPER_DIR to its Contents/Developer directory.\n' >&2
            exit 1
        fi
    fi
fi

xcrun swift build -c release
binary_dir="$(xcrun swift build -c release --show-bin-path)"
build_stamp="$(date +%Y-%m-%d-%H%M%S)"
snapshot_dir="$project_dir/Builds/CueX-$build_stamp"
app_bundle="$snapshot_dir/CueX.app"
mkdir -p "$app_bundle/Contents/MacOS"
cp "$binary_dir/CueX" "$app_bundle/Contents/MacOS/CueX"

# Generate native and Retina icon sizes from the original artwork.
iconset="$snapshot_dir/CueX.iconset"
mkdir -p "$iconset" "$app_bundle/Contents/Resources"
for size in 16 32 128 256 512; do
    retina_size=$((size * 2))
    sips -z "$size" "$size" "$project_dir/Assets/AppIcon.png" \
        --out "$iconset/icon_${size}x${size}.png" >/dev/null
    sips -z "$retina_size" "$retina_size" "$project_dir/Assets/AppIcon.png" \
        --out "$iconset/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$iconset" -o "$app_bundle/Contents/Resources/CueX.icns"

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
    <key>CFBundleIconFile</key><string>CueX.icns</string>
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
