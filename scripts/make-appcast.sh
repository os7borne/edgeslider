#!/bin/zsh
# Creates the signed Sparkle feed (site/appcast.xml) for the notarized zip in dist/.
# Run `./build.sh release` first. The EdDSA private key is read from the login Keychain by generate_appcast.
#
#   scripts/make-appcast.sh            # uses the version inside dist/EdgeSlider.zip
#
# Afterwards: create the GitHub release v<version> with dist/EdgeSlider.zip attached, then push site/ so Vercel
# serves the new appcast.xml. Installed copies pick it up on their next daily check.
set -e
cd "$(dirname "$0")/.."
./scripts/fetch-sparkle.sh

ZIP=dist/EdgeSlider.zip
[[ -f $ZIP ]] || { echo "dist/EdgeSlider.zip not found: run ./build.sh release first" >&2; exit 1; }
VERSION=$(unzip -p $ZIP EdgeSlider.app/Contents/Info.plist | plutil -extract CFBundleShortVersionString raw -o - -)
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT

cp $ZIP "$T/EdgeSlider.zip"
# release notes shown in Sparkle's update window (notes/<version>.md, optional)
[[ -f notes/$VERSION.md ]] && cp notes/$VERSION.md "$T/EdgeSlider.md"

./vendor/bin/generate_appcast \
  --download-url-prefix "https://github.com/os7borne/edgeslider/releases/download/v$VERSION/" \
  --embed-release-notes \
  -o site/appcast.xml "$T"

echo "Wrote site/appcast.xml for v$VERSION"
