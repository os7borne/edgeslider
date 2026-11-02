// SPDX-License-Identifier: GPL-3.0-or-later
// EdgeSlider, Copyright (C) 2026 Osborne Saldanha. See LICENSE.

import SwiftUI
import ServiceManagement

extension Color { static let accentOrange = Color(red: 0.957, green: 0.482, blue: 0.125) }   // #F47B20

private struct Badge: View {
    let symbol: String
    var filled = true      // kept for call sites; icons no longer have a background
    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 16, weight: .regular))
            .foregroundColor(.primary)
            .frame(width: 28, height: 28)
    }
}

/// The panel's on/off switch. Native `Toggle` everywhere, except while rendering README screenshots: a background tool is
/// never the active app, and native switches draw gray when inactive, so a stand-in is drawn instead.
private struct SwitchControl: View {
    @Binding var isOn: Bool
    var small = false

    var body: some View {
        if Screenshots.isRendering {
            let w: CGFloat = small ? 34 : 40, h: CGFloat = small ? 20 : 24
            Capsule().fill(isOn ? Color.accentOrange : Color.gray.opacity(0.35))
                .frame(width: w, height: h)
                .overlay(Circle().fill(Color.white).padding(2), alignment: isOn ? .trailing : .leading)
        } else if small {
            Toggle("", isOn: $isOn).labelsHidden().toggleStyle(.switch).controlSize(.small).tint(.accentOrange)
        } else {
            Toggle("", isOn: $isOn).labelsHidden().toggleStyle(.switch).tint(.accentOrange)
        }
    }
}

private struct ToggleRow: View {
    let icon: String, title: String, subtitle: String
    @Binding var isOn: Bool
    var body: some View {
        HStack(spacing: 12) {
            Badge(symbol: icon)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.system(size: 13, weight: .medium))
                Text(subtitle).font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            SwitchControl(isOn: $isOn)
        }
    }
}

private struct SliderRow: View {
    let icon: String, title: String, valueText: String
    @Binding var value: Double
    let range: ClosedRange<Double>, step: Double
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 12) {
                Badge(symbol: icon, filled: false)
                Text(title).font(.system(size: 13, weight: .medium))
                Spacer()
                Text(valueText).font(.system(size: 12)).monospacedDigit().foregroundStyle(.secondary)
            }
            Slider(value: $value, in: range, step: step).tint(.accentOrange)
        }
    }
}

private struct SectionTitle: View {
    let text: String
    var body: some View {
        Text(text).font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary).padding(.top, 2)
    }
}

struct PopoverRoot: View {
    @ObservedObject private var s = Settings.shared
    @ObservedObject private var updater = Updater.shared
    @State private var page: Int
    @State private var loginOn = SMAppService.mainApp.status == .enabled
    @State private var loginNote: String?

    init(page: Int = 0) { _page = State(initialValue: page) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            if let v = updater.availableVersion { updateBanner(v) }
            if page == 0 { mainPage } else { settingsPage }
            Divider()
            footer
            credit
        }
        .padding(16)
        .frame(width: 340)
        .onAppear { refreshLogin() }
    }

    // MARK: header / footer

    private var header: some View {
        HStack(spacing: 10) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable().interpolation(.high)
                .frame(width: 36, height: 36)
                .accessibilityHidden(true)
            Text(page == 0 ? "EdgeSlider" : "Settings").font(.system(size: 15, weight: .semibold))
            Spacer()
            Circle().fill(s.enabled ? Color.green : Color.gray).frame(width: 8, height: 8)
            Text(s.enabled ? "Ready" : "Paused").font(.system(size: 12)).foregroundStyle(.secondary)
            SwitchControl(isOn: $s.enabled, small: true)
        }
    }

    private var footer: some View {
        HStack {
            if page == 0 {
                Button { page = 1 } label: { Label("Settings", systemImage: "gearshape") }
            } else {
                Button { page = 0 } label: { Label("Back", systemImage: "chevron.left") }
                Text("Version \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.1")").font(.system(size: 11)).foregroundStyle(.secondary).padding(.leading, 6)
            }
            Spacer()
            Button { NSApp.terminate(nil) } label: { Image(systemName: "power") }.help("Quit EdgeSlider")
        }
        .buttonStyle(.plain)
        .font(.system(size: 12))
    }

    private var credit: some View {
        HStack(spacing: 4) {
            Text("A mini app by")
            Link("Osborne Saldanha", destination: URL(string: "https://osborne.vc")!)
                .foregroundColor(.accentOrange)
                .help("osborne.vc")
        }
        .font(.system(size: 11))
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity)
    }

    private func updateBanner(_ version: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "arrow.down.circle.fill").foregroundColor(.accentOrange)
            Text("Version \(version) is available").font(.system(size: 12, weight: .semibold))
            Spacer()
            Button("Install") { updater.checkForUpdates() }
                .buttonStyle(.borderedProminent).tint(.accentOrange).controlSize(.small)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.accentOrange.opacity(0.14)))
    }

    // MARK: pages

    private var mainPage: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Badge(symbol: "hand.tap.fill")
                VStack(alignment: .leading, spacing: 1) {
                    Text("Haptic Feedback").font(.system(size: 13, weight: .medium))
                    Text("Clicks as you slide").font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Spacer()
                Picker("", selection: $s.haptic) {
                    ForEach(Haptic.allCases) { Text($0.label).tag($0) }
                }.labelsHidden().pickerStyle(.menu).frame(width: 90)
            }
            ToggleRow(icon: "speaker.slash.fill", title: "Quick Mute",
                      subtitle: "Double-tap the top-right corner", isOn: $s.quickMute)
            ToggleRow(icon: "forward.fill", title: "Media Strip",
                      subtitle: "Swipe the bottom edge to skip songs", isOn: $s.mediaStrip)
            Divider()
            SliderRow(icon: "gauge.with.dots.needle.33percent", title: "Sensitivity",
                      valueText: String(format: "%.1f×", s.sensitivity),
                      value: Binding(get: { Double(s.sensitivity) }, set: { s.sensitivity = Float($0) }),
                      range: 0.5...3.0, step: 0.1)
            SliderRow(icon: "arrow.left.and.right", title: "Edge Width",
                      valueText: "\(Int((s.edgeWidth * 100).rounded()))%",
                      value: Binding(get: { Double(s.edgeWidth * 100) }, set: { s.edgeWidth = Float($0 / 100) }),
                      range: 3...12, step: 1)
        }
    }

    private var settingsPage: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionTitle(text: "Edge Gestures")
            ToggleRow(icon: "arrow.left.arrow.right", title: "Swap Sides",
                      subtitle: s.swapSides ? "Left: Volume · Right: Brightness" : "Left: Brightness · Right: Volume",
                      isOn: $s.swapSides)
            ToggleRow(icon: "rectangle.bottomhalf.filled", title: "Bottom Quarter Only",
                      subtitle: "Ignore touches above the lower 25%", isOn: $s.bottomQuarterOnly)
            Divider()
            SectionTitle(text: "Display")
            ToggleRow(icon: "percent", title: "Show Percentage",
                      subtitle: "Show the value on the slider pill", isOn: $s.showPercent)
            Divider()
            SectionTitle(text: "While Sliding")
            ToggleRow(icon: "cursorarrow", title: "Freeze Cursor",
                      subtitle: "Pointer stays put while sliding", isOn: $s.freezeCursor)
            Divider()
            SectionTitle(text: "General")
            ToggleRow(icon: "power", title: "Open at Login",
                      subtitle: loginNote ?? "Start EdgeSlider when you log in",
                      isOn: Binding(get: { loginOn }, set: setLogin))
            Divider()
            SectionTitle(text: "Updates")
            ToggleRow(icon: "arrow.triangle.2.circlepath", title: "Check Automatically",
                      subtitle: "Look for new versions daily",
                      isOn: Binding(get: { updater.automaticChecks }, set: { updater.automaticChecks = $0 }))
            Button { updater.checkForUpdates() } label: {
                HStack(spacing: 12) {
                    Badge(symbol: "arrow.down.circle")
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Check for Updates…").font(.system(size: 13, weight: .medium))
                        Text("You have version \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "")")
                            .font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: launch at login

    private func refreshLogin() { loginOn = SMAppService.mainApp.status == .enabled }

    private func setLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            loginNote = SMAppService.mainApp.status == .requiresApproval
                ? "Approve in System Settings › Login Items" : nil
        } catch {
            loginNote = "Couldn't change: move the app to /Applications"
        }
        refreshLogin()
    }
}
