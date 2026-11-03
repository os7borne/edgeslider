// SPDX-License-Identifier: GPL-3.0-or-later
// EdgeSlider, Copyright (C) 2026 Osborne Saldanha. See LICENSE.

import Foundation

enum Haptic: Int, CaseIterable, Identifiable {
    case off, light, strong
    var id: Int { rawValue }
    var label: String { ["Off", "Light", "Strong"][rawValue] }
}

enum CornerEdge: Int, CaseIterable, Identifiable {
    case top, bottom
    var id: Int { rawValue }
    var label: String { ["Top", "Bottom"][rawValue] }
    var word: String { ["top", "bottom"][rawValue] }
}

/// All user preferences, persisted in UserDefaults. Read from the touch thread, written from the UI.
final class Settings: ObservableObject {
    static let shared = Settings()
    private let d = UserDefaults.standard

    @Published var enabled: Bool        { didSet { d.set(enabled, forKey: "enabled") } }
    @Published var sensitivity: Float   { didSet { d.set(sensitivity, forKey: "sensitivity") } }   // 0.5 ... 3
    @Published var edgeWidth: Float     { didSet { d.set(edgeWidth, forKey: "edgeWidth") } }       // 0.03 ... 0.12
    @Published var holdDelay: Float     { didSet { d.set(holdDelay, forKey: "holdDelay") } }          // seconds, 0 ... 0.5
    @Published var haptic: Haptic       { didSet { d.set(haptic.rawValue, forKey: "haptic") } }
    @Published var freezeCursor: Bool   { didSet { d.set(freezeCursor, forKey: "freezeCursor") } }
    @Published var swapSides: Bool      { didSet { d.set(swapSides, forKey: "swapSides") } }
    @Published var bottomQuarterOnly: Bool { didSet { d.set(bottomQuarterOnly, forKey: "bottomQuarterOnly") } }
    @Published var quickMute: Bool      { didSet { d.set(quickMute, forKey: "quickMute") } }
    @Published var switchOutput: Bool   { didSet { d.set(switchOutput, forKey: "switchOutput") } }
    @Published var cornerEdge: CornerEdge { didSet { d.set(cornerEdge.rawValue, forKey: "cornerEdge") } }
    @Published var showPercent: Bool    { didSet { d.set(showPercent, forKey: "showPercent") } }

    private init() {
        d.register(defaults: [
            "enabled": true, "sensitivity": 1.3, "edgeWidth": 0.07, "haptic": Haptic.strong.rawValue, "holdDelay": 0.15,
            "freezeCursor": true, "swapSides": false, "bottomQuarterOnly": false,
            "quickMute": false,      // off by default: with Tap to Click on, taps also click under the pointer
            "cornerEdge": CornerEdge.top.rawValue,
            "switchOutput": false,   // off by default, same Tap to Click caveat as quickMute
            "showPercent": true,
        ])
        enabled = d.bool(forKey: "enabled")
        sensitivity = d.float(forKey: "sensitivity")
        edgeWidth = d.float(forKey: "edgeWidth")
        holdDelay = d.float(forKey: "holdDelay")
        haptic = Haptic(rawValue: d.integer(forKey: "haptic")) ?? .strong
        freezeCursor = d.bool(forKey: "freezeCursor")
        swapSides = d.bool(forKey: "swapSides")
        bottomQuarterOnly = d.bool(forKey: "bottomQuarterOnly")
        quickMute = d.bool(forKey: "quickMute")
        switchOutput = d.bool(forKey: "switchOutput")
        cornerEdge = CornerEdge(rawValue: d.integer(forKey: "cornerEdge")) ?? .top
        showPercent = d.bool(forKey: "showPercent")
    }
}
