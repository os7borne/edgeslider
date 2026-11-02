#!/bin/zsh
# Downloads the pinned Sparkle release into vendor/ (framework + signing tools), verifying its checksum.
set -e
cd "$(dirname "$0")/.."
VER=2.10.1
SHA=1a856d2a9edb8e628de88121d7be04cf0e2167f8641650b78fca00b14244cf27
if [[ -d vendor/Sparkle.framework && -f vendor/.sparkle-$VER ]]; then exit 0; fi
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
curl -fsSL -o "$T/s.tar.xz" "https://github.com/sparkle-project/Sparkle/releases/download/$VER/Sparkle-$VER.tar.xz"
[[ "$(shasum -a 256 "$T/s.tar.xz" | cut -d' ' -f1)" == "$SHA" ]] || { echo "Sparkle checksum mismatch" >&2; exit 1; }
mkdir -p "$T/x"; tar -xf "$T/s.tar.xz" -C "$T/x"
rm -rf vendor; mkdir -p vendor/bin
ditto "$T/x/Sparkle.framework" vendor/Sparkle.framework
cp "$T/x/LICENSE" vendor/Sparkle-LICENSE.txt
cp "$T/x/bin/generate_keys" "$T/x/bin/generate_appcast" "$T/x/bin/sign_update" vendor/bin/
touch vendor/.sparkle-$VER
echo "Sparkle $VER ready in vendor/"
