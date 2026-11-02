#!/bin/zsh
# Regenerates the README screenshots in docs/images/ from the real UI code.
set -e
cd "$(dirname "$0")/.."
./build.sh
./EdgeSlider.app/Contents/MacOS/EdgeSlider --render-screenshots docs/images
