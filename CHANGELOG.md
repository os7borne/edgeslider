# Changelog

All notable changes to EdgeSlider are listed here. The format follows [Keep a Changelog](https://keepachangelog.com/).

## [1.5.2] - 2026-11-04

### Changed
- The collapsed "Advanced" section is replaced by an "All Settings…" button that opens a separate settings window. The panel stays short.

## [1.5.1] - 2026-11-04

### Changed
- The options hidden in 1.5 return under a collapsed "Advanced" section of the panel.

## [1.5] - 2026-11-04

### Changed
- The menu bar panel is a single page: Sensitivity, Haptic Feedback, Swap Sides, Quick Mute, Switch Output, Open at Login. Edge Width, Hold Delay, Bottom Quarter Only, Corner Position, Show Percentage, Freeze Cursor and the update toggle were hidden (restored in 1.5.1).
- Only one instance of the app runs at a time.

## [1.4] - 2026-11-04

### Added
- Corner Position setting: Quick Mute and Switch Output can listen in the top or the bottom corners of the trackpad.

### Changed
- Hold Delay: a finger must rest on the edge for 150 ms before the slider engages (adjustable under Settings, or off), so a palm brushing past the edge no longer moves brightness or volume.

### Removed
- The media strip (swipe the bottom edge to skip tracks).

## [1.3.3] - 2026-11-03

### Fixed
- The volume and brightness pill and the output-switch pill now show over full-screen apps.

## [1.3.2] - 2026-11-03

### Changed
- Corner double-taps ignore touches within half a second of a key press, and both taps must land in the same spot, so a resting palm no longer triggers them.

## [1.3.1] - 2026-11-03

### Fixed
- Corner double-taps (Quick Mute, Switch Output) missed taps near the corner tip. Tap length, movement and spacing limits are more forgiving.

## [1.3] - 2026-11-03

### Added
- Switch Output: double-tap the top-left corner to cycle the sound output through the connected devices (off by default). A pill at the top of the screen shows the new device.

## [1.2] - 2026-11-02

First public release.

### Added
- Edge sliders: slide along the left edge of the trackpad for brightness and the right edge for volume. Swappable.
- Haptic feedback at every step, with Off, Light and Strong settings, and a firmer bump at the minimum and maximum.
- On-screen indicator that slides in from the screen edge, with an optional percentage.
- Pointer stays pinned in place while you slide.
- Protection against accidental touches: a touch must land on the edge and move before it engages, and the sliders can be limited to the lower part of the pad.
- Media strip: swipe along the bottom edge for the next or previous track.
- Quick Mute: double-tap the top-right corner (off by default).
- Menu bar panel with sensitivity, edge width and the other settings, plus Open at Login.
- Automatic updates through Sparkle, with an orange menu bar icon and an Install button when a new version is ready.
- Universal build (Apple Silicon and Intel) for macOS 13 or later, signed with a Developer ID and notarized by Apple.

[1.2]: https://github.com/os7borne/edgeslider/releases/tag/v1.2
