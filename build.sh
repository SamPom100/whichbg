#!/usr/bin/env zsh
set -e

DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="$DIR/build"
APP_DIR="$BUILD_DIR/WhichBG.app"

echo "Building WhichBG for macOS..."

rm -rf "$BUILD_DIR"
mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Resources"

# Compile binary
swiftc -O \
    "$DIR/WhichBG/main.swift" \
    "$DIR/WhichBG/AppDelegate.swift" \
    "$DIR/WhichBG/Core.swift" \
    "$DIR/WhichBG/DesktopPictureViewController.swift" \
    "$DIR/WhichBG/GlobalEventMonitor.swift" \
    -lsqlite3 \
    -o "$APP_DIR/Contents/MacOS/WhichBG"

# Prepare Info.plist
cat << 'EOF' > "$APP_DIR/Contents/Info.plist"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleDevelopmentRegion</key>
	<string>en</string>
	<key>CFBundleExecutable</key>
	<string>WhichBG</string>
	<key>CFBundleIconFile</key>
	<string>AppIcon</string>
	<key>CFBundleIdentifier</key>
	<string>com.musicallyut.WhichBG</string>
	<key>CFBundleInfoDictionaryVersion</key>
	<string>6.0</string>
	<key>CFBundleName</key>
	<string>WhichBG</string>
	<key>CFBundlePackageType</key>
	<string>APPL</string>
	<key>CFBundleShortVersionString</key>
	<string>0.5</string>
	<key>CFBundleVersion</key>
	<string>2</string>
	<key>LSApplicationCategoryType</key>
	<string>public.app-category.utilities</string>
	<key>LSMinimumSystemVersion</key>
	<string>10.13</string>
	<key>LSUIElement</key>
	<true/>
	<key>NSHumanReadableCopyright</key>
	<string>Copyright © Utkarsh Upadhyay. All rights reserved.</string>
	<key>NSPrincipalClass</key>
	<string>NSApplication</string>
</dict>
</plist>
EOF

# Copy Resources (Use 64x64 high-res asset for sharp status icon on Retina screens)
cp "$DIR/WhichBG/Images.xcassets/StatusIcon.imageset/Website_Design_64.png" "$APP_DIR/Contents/Resources/StatusIcon.png" 2>/dev/null || true
cp "$DIR/WhichBG/Images.xcassets/AppIcon.appiconset/Website_Design_256.png" "$APP_DIR/Contents/Resources/AppIcon.png" 2>/dev/null || true

# Update zipped app if app directory exists
if [ -d "$DIR/app" ]; then
    (cd "$BUILD_DIR" && zip -r "$DIR/app/WhichBG.app.zip" "WhichBG.app")
fi

echo "Successfully built $APP_DIR"
