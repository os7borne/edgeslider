// SPDX-License-Identifier: GPL-3.0-or-later
// EdgeSlider, Copyright (C) 2026 Osborne Saldanha. See LICENSE.

import Foundation

enum Haptic: Int, CaseIterable, Identifiable {
    case off, light, strong
    var id: Int { rawValue }
    var label: String { ["Off", "Light", "Strong"][rawValue] }
}

/// All user preferences, persisted in UserDefaults. Read from the touch thread, written from the UI.
final class Settings: ObservableObject {
    static let shared = Settings()
    private let d = UserDefaults.standard

    @Published var enabled: Bool        { didSet { d.set(enabled, forKey: "enabled") } }
    @Published var sensitivity: Float   { didSet { d.set(sensitivity, forKey: "sensitivity") } }   // 0.5 ... 3
    @Published var edgeWidth: Float     { didSet { d.set(edgeWidth, forKey: "edgeWidth") } }       // 0.03 ... 0.12
    @Published var haptic: Haptic       { didSet { d.set(haptic.rawValue, forKey: "haptic") } }
    @Published var freezeCursor: Bool   { didSet { d.set(freezeCursor, forKey: "freezeCursor") } }
    @Published var swapSides: Bool      { didSet { d.set(swapSides, forKey: "swapSides") } }
    @Published var bottomQuarterOnly: Bool { didSet { d.set(bottomQuarterOnly, forKey: "bottomQuarterOnly") } }
    @Published var quickMute: Bool      { didSet { d.set(quickMute, forKey: "quickMute") } }
    @Published var mediaStrip: Bool     { didSet { d.set(mediaStrip, forKey: "mediaStrip") } }
    @Published var showPercent: Bool    { didSet { d.set(showPercent, forKey: "showPercent") } }

    private init() {
        d.register(defaults: [
            "enabled": true, "sensitivity": 1.3, "edgeWidth": 0.07, "haptic": Haptic.strong.rawValue,
            "freezeCursor": true, "swapSides": false, "bottomQuarterOnly": false,
            "quickMute": false,      // off by default: with Tap to Click on, taps also click under the pointer
            "mediaStrip": true, "showPercent": true,
        ])
        enabled = d.bool(forKey: "enabled")
        sensitivity = d.float(forKey: "sensitivity")
        edgeWidth = d.float(forKey: "edgeWidth")
        haptic = Haptic(rawValue: d.integer(forKey: "haptic")) ?? .strong
        freezeCursor = d.bool(forKey: "freezeCursor")
        swapSides = d.bool(forKey: "swapSides")
        bottomQuarterOnly = d.bool(forKey: "bottomQuarterOnly")
        quickMute = d.bool(forKey: "quickMute")
        mediaStrip = d.bool(forKey: "mediaStrip")
        showPercent = d.bool(forKey: "showPercent")
    }
}
