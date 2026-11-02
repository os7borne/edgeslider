# EdgeSlider

A tiny macOS menu bar app: slide a finger along the left or right edge of the trackpad to change brightness and volume.
Website: https://edgeslider.osborne.vc

- Left edge: brightness. Right edge: volume (swappable).
- Haptic ticks, pointer pinned while sliding, bottom-edge swipe for next/previous track, optional double-tap-corner mute.
- Native Swift, no dependencies. Reads trackpad touches through Apple's private `MultitouchSupport` framework and sets brightness through `DisplayServices`, so it is not App Store compatible.

## Build

```sh
./build.sh            # dev build (this Mac, ad-hoc signed)
./build.sh install    # dev build + copy to /Applications
./build.sh release    # universal, Developer ID signed, notarized -> dist/EdgeSlider.zip
```

`release` needs a Developer ID Application certificate and an App Store Connect API key. Put `KEY_PATH`, `KEY_ID` and `ISSUER` in a git-ignored `release.local.env` next to `build.sh`.

Updates use [Sparkle](https://sparkle-project.org). After `./build.sh release`, run `scripts/make-appcast.sh` to write the signed `site/appcast.xml` (the EdDSA private key is read from the login Keychain), attach `dist/EdgeSlider.zip` to a GitHub release tagged `v<version>`, and push `site/`.

## Website

`site/` is a static one-page site (deployed on Vercel with Root Directory set to `site`).

A mini app by [Osborne Saldanha](https://osborne.vc).
