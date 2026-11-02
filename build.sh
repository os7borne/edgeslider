#!/bin/zsh
# ./build.sh            dev build: this Mac only, ad-hoc signed
# ./build.sh install    dev build, then copy to /Applications (needed for a reliable "Open at Login")
# ./build.sh release    universal (arm64 + x86_64), Developer ID signed, notarized, stapled -> dist/EdgeSlider.zip
set -e
cd "$(dirname "$0")"

MODE=${1:-dev}
APP=EdgeSlider.app
VERSION=1.2
BUILD=2
MIN_OS=13.0
BUNDLE_ID=vc.osborne.edgeslider
SRC=(main.swift Settings.swift SettingsView.swift Updater.swift)
FEED_URL=https://edgeslider.osborne.vc/appcast.xml
# Sparkle EdDSA public key (the private half is in the login Keychain; `vendor/bin/generate_keys -p` prints this)
SPARKLE_PUBLIC_KEY="9b3+QblYKhj4vExT8bWWQaht7qxzEevMcAXwv080L9w="
SPFLAGS=(-F vendor -framework Sparkle -Xlinker -rpath -Xlinker @executable_path/../Frameworks)
IDENTITY="Developer ID Application: Osborne Saldanha (4CMN2DUGUL)"
# Notarization credentials (KEY_PATH, KEY_ID, ISSUER) come from a git-ignored local file; see README
[[ -f release.local.env ]] && source ./release.local.env

./scripts/fetch-sparkle.sh
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT

rm -rf $APP
mkdir -p $APP/Contents/MacOS $APP/Contents/Resources $APP/Contents/Frameworks

# --- binary ---
if [[ "$MODE" == "release" ]]; then
  for arch in arm64 x86_64; do
    swiftc -O -target $arch-apple-macos$MIN_OS "${SPFLAGS[@]}" "${SRC[@]}" -o "$T/EdgeSlider-$arch"
  done
  lipo -create "$T/EdgeSlider-arm64" "$T/EdgeSlider-x86_64" -output $APP/Contents/MacOS/EdgeSlider
else
  swiftc -O -target $(uname -m)-apple-macos$MIN_OS "${SPFLAGS[@]}" "${SRC[@]}" -o $APP/Contents/MacOS/EdgeSlider
fi

# --- embed Sparkle (not sandboxed, so its XPC helper services aren't needed) ---
ditto vendor/Sparkle.framework $APP/Contents/Frameworks/Sparkle.framework
rm -rf $APP/Contents/Frameworks/Sparkle.framework/Versions/B/XPCServices $APP/Contents/Frameworks/Sparkle.framework/XPCServices

# --- app icon: render the iconset with make-icon.swift, then pack it into AppIcon.icns ---
swiftc -O make-icon.swift -o "$T/make-icon"
"$T/make-icon" "$T/AppIcon.iconset"
iconutil -c icns "$T/AppIcon.iconset" -o $APP/Contents/Resources/AppIcon.icns
cp "$T/AppIcon.iconset/icon_512x512@2x.png" AppIcon-1024.png

cat > $APP/Contents/Info.plist <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleName</key><string>EdgeSlider</string>
<key>CFBundleDisplayName</key><string>EdgeSlider</string>
<key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
<key>CFBundleExecutable</key><string>EdgeSlider</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>$VERSION</string>
<key>CFBundleVersion</key><string>$BUILD</string>
<key>LSMinimumSystemVersion</key><string>$MIN_OS</string>
<key>LSApplicationCategoryType</key><string>public.app-category.utilities</string>
<key>LSUIElement</key><true/>
<key>SUFeedURL</key><string>$FEED_URL</string>
<key>SUPublicEDKey</key><string>$SPARKLE_PUBLIC_KEY</string>
<key>SUEnableAutomaticChecks</key><true/>
<key>NSHumanReadableCopyright</key><string>© Osborne Saldanha</string>
</dict></plist>
EOF

# --- sign ---
if [[ "$MODE" == "release" ]]; then
  # sign inside-out: Sparkle's helpers, then the framework, then the app
  SPK=$APP/Contents/Frameworks/Sparkle.framework
  for item in "$SPK/Versions/B/Autoupdate" "$SPK/Versions/B/Updater.app" "$SPK"; do
    codesign --force --options runtime --timestamp --sign "$IDENTITY" "$item"
  done
  codesign --force --options runtime --timestamp --sign "$IDENTITY" $APP
  codesign --verify --strict --verbose=2 $APP
else
  codesign --force --deep --sign - $APP
fi
echo "Built $APP ($MODE)"

# --- notarize + package ---
if [[ "$MODE" == "release" ]]; then
  mkdir -p dist
  ditto -c -k --keepParent $APP "$T/notarize.zip"
  xcrun notarytool submit "$T/notarize.zip" --key "$KEY_PATH" --key-id "$KEY_ID" --issuer "$ISSUER" --wait
  xcrun stapler staple $APP
  rm -f dist/EdgeSlider.zip
  ditto -c -k --keepParent $APP dist/EdgeSlider.zip
  spctl -a -vv $APP
  echo "Release ready: dist/EdgeSlider.zip"
fi

if [[ "$MODE" == "install" ]]; then
  pkill EdgeSlider 2>/dev/null || true
  rm -rf /Applications/$APP
  ditto $APP /Applications/$APP
  echo "Installed /Applications/$APP"
fi
