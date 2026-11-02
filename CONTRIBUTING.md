# Contributing to EdgeSlider

Thanks for helping. EdgeSlider is a small app, so the bar for contributing is low: a clear bug report is already a real contribution.

## Reporting a bug

Open an issue and include:

- your **macOS version** and **Mac model** (Apple menu → About This Mac)
- which **trackpad** you use (built-in, or Magic Trackpad)
- what you did, what you expected, and what happened

Because EdgeSlider relies on Apple's undocumented interfaces, behavior can differ between macOS versions and trackpad generations, so those details really matter.

## Suggesting a feature

Open an issue first. The app is deliberately tiny, and I'd rather talk through a feature than have you build something I can't merge. Ideas that fit well are other things with a level or a few steps that can live on an edge. Anything that needs new permissions, a new dependency, or a network connection needs a strong reason.

## Building and running

```sh
./build.sh          # dev build, ad-hoc signed, no certificate needed
open EdgeSlider.app
```

You need macOS 13+ and the Xcode command line tools. See the [README](README.md#build-from-source) for the project layout.

## Pull requests

- Keep them small and focused, one change per PR.
- **Test on a real trackpad.** There's no way to unit test touch handling without one, so say in the PR what you tried and on what hardware and macOS version.
- Keep the touch callback fast. It runs on a high-frequency background thread, so slow work (audio, brightness, UI) belongs on the apply queue or the main thread, as it does today.
- Match the existing style: plain Swift, no new dependencies, short comments that say why.
- If you change the panel, run `scripts/screenshots.sh` and include the updated images in `docs/images/`.
- Don't bump the version, edit the update feed, or touch `site/appcast.xml`. Releases are cut by the maintainer.

## Licensing

EdgeSlider is licensed under the GNU GPL v3 or later. By submitting a contribution you agree it may be distributed under that license. New Swift files should start with the same two-line header as the existing ones:

```swift
// SPDX-License-Identifier: GPL-3.0-or-later
// EdgeSlider, Copyright (C) 2026 Osborne Saldanha. See LICENSE.
```
