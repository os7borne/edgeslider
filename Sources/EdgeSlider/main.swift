// SPDX-License-Identifier: GPL-3.0-or-later
// EdgeSlider, Copyright (C) 2026 Osborne Saldanha. See LICENSE.

import Cocoa
import CoreAudio
import os

let log = Logger(subsystem: "vc.osborne.edgeslider", category: "input")

// MARK: - Settings

let deadZone: Float = 0.035      // vertical travel (fraction of pad height) before the control engages

// Palm rejection. Contact size comes from the private MTTouch record; thresholds were calibrated from --log-touches
// captures on one MacBook trackpad (fingertip size 0.5-1.0 / major 7-10, thumb or firm press up to ~1.5 / 12, palm 2.3-6 / 17-25).
// Once a gesture is engaged the limits are higher, so a firm press does not drop it (hysteresis).
enum Palm {
    static let landing: (size: Float, major: Float) = (2.0, 15)
    static let engaged: (size: Float, major: Float) = (2.8, 19)
    static let keyGuard = 0.5    // seconds after a key press during which new touches and corner taps are ignored (palms rest while typing)
    static func secondsSinceKey() -> Double {
        CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: .keyDown)
    }
}

/// One setup for both on-screen pills. A non-activating panel that moves to the active Space is what shows over
/// other apps' full-screen Spaces (.canJoinAllSpaces did not).
func makeHUDPanel(size: NSSize) -> NSPanel {
    let panel = NSPanel(contentRect: NSRect(origin: .zero, size: size),
                        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
    panel.isFloatingPanel = true; panel.hidesOnDeactivate = false; panel.becomesKeyOnlyIfNeeded = true
    panel.level = .screenSaver
    panel.isOpaque = false
    panel.backgroundColor = .clear
    panel.hasShadow = true
    panel.ignoresMouseEvents = true
    panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary, .ignoresCycle]
    return panel
}

// MARK: - Volume (CoreAudio)

enum Volume {
    static var deviceID = AudioDeviceID(0)
    static var muted = false
    static func refreshDevice() {
        var id = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var addr = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                                              mScope: kAudioObjectPropertyScopeGlobal,
                                              mElement: kAudioObjectPropertyElementMain)
        AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &id)
        deviceID = id
    }
    static var addr = AudioObjectPropertyAddress(mSelector: 0x766D7663 /* 'vmvc' */,
                                                 mScope: kAudioDevicePropertyScopeOutput,
                                                 mElement: kAudioObjectPropertyElementMain)
    static var muteAddr = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyMute,
                                                     mScope: kAudioDevicePropertyScopeOutput,
                                                     mElement: kAudioObjectPropertyElementMain)
    static func readMute() -> Bool {
        var m = UInt32(0); var size = UInt32(4)
        AudioObjectGetPropertyData(deviceID, &muteAddr, 0, nil, &size, &m)
        return m != 0
    }
    static func get() -> Float {
        refreshDevice()
        muted = readMute()
        var v = Float32(0); var size = UInt32(4)
        AudioObjectGetPropertyData(deviceID, &addr, 0, nil, &size, &v)
        return v
    }
    static func set(_ value: Float) {
        var v = Float32(min(max(value, 0), 1))
        AudioObjectSetPropertyData(deviceID, &addr, 0, nil, 4, &v)
        let shouldMute = v <= 0.001
        if shouldMute != muted {                       // only touch mute when it changes
            muted = shouldMute
            var mute = UInt32(shouldMute ? 1 : 0)
            AudioObjectSetPropertyData(deviceID, &muteAddr, 0, nil, 4, &mute)
        }
    }
    /// Toggles mute and returns the new state.
    static func toggleMute() -> Bool {
        refreshDevice()
        var n = UInt32(readMute() ? 0 : 1)
        AudioObjectSetPropertyData(deviceID, &muteAddr, 0, nil, 4, &n)
        muted = n != 0
        return muted
    }
}

// MARK: - Output device switching (CoreAudio)

enum AudioOutput {
    struct Device { let id: AudioDeviceID; let name: String; let symbol: String }

    private static func address(_ selector: AudioObjectPropertySelector,
                                _ scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
    }

    private static func uint32(_ id: AudioObjectID, _ selector: AudioObjectPropertySelector) -> UInt32 {
        var a = address(selector); var v = UInt32(0); var size = UInt32(4)
        AudioObjectGetPropertyData(id, &a, 0, nil, &size, &v)
        return v
    }

    private static func hasOutput(_ id: AudioObjectID) -> Bool {
        var a = address(kAudioDevicePropertyStreamConfiguration, kAudioDevicePropertyScopeOutput)
        var size = UInt32(0)
        guard AudioObjectGetPropertyDataSize(id, &a, 0, nil, &size) == noErr, size > 0 else { return false }
        let raw = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { raw.deallocate() }
        guard AudioObjectGetPropertyData(id, &a, 0, nil, &size, raw) == noErr else { return false }
        let list = UnsafeMutableAudioBufferListPointer(raw.assumingMemoryBound(to: AudioBufferList.self))
        return list.contains { $0.mNumberChannels > 0 }
    }

    private static func name(_ id: AudioObjectID) -> String {
        var a = address(kAudioObjectPropertyName)
        var s: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(id, &a, 0, nil, &size, &s) == noErr, let s = s else { return "Audio Output" }
        return s.takeRetainedValue() as String
    }

    private static func symbol(transport: UInt32, name: String) -> String {
        if name.localizedCaseInsensitiveContains("airpods") { return "airpods" }
        switch transport {
        case kAudioDeviceTransportTypeBluetooth, kAudioDeviceTransportTypeBluetoothLE: return "headphones"
        case kAudioDeviceTransportTypeHDMI, kAudioDeviceTransportTypeDisplayPort: return "display"
        case kAudioDeviceTransportTypeAirPlay: return "airplayaudio"
        case kAudioDeviceTransportTypeUSB: return "hifispeaker.fill"
        default: return "speaker.wave.2.fill"
        }
    }

    /// Real, connected outputs in system order (aggregate, virtual and hidden devices are skipped).
    static func outputs() -> [Device] {
        var a = address(kAudioHardwarePropertyDevices)
        var size = UInt32(0)
        let sys = AudioObjectID(kAudioObjectSystemObject)
        guard AudioObjectGetPropertyDataSize(sys, &a, 0, nil, &size) == noErr else { return [] }
        var ids = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(sys, &a, 0, nil, &size, &ids) == noErr else { return [] }
        return ids.compactMap { id in
            guard hasOutput(id), uint32(id, kAudioDevicePropertyIsHidden) == 0 else { return nil }
            let t = uint32(id, kAudioDevicePropertyTransportType)
            if t == kAudioDeviceTransportTypeAggregate || t == kAudioDeviceTransportTypeVirtual { return nil }
            let n = name(id)
            return Device(id: id, name: n, symbol: symbol(transport: t, name: n))
        }
    }

    /// Makes the next output the system default (output and alerts) and returns it.
    @discardableResult
    static func cycle() -> Device? {
        let list = outputs()
        guard !list.isEmpty else { return nil }
        Volume.refreshDevice()
        let i = list.firstIndex { $0.id == Volume.deviceID }
        let next = list[((i ?? -1) + 1) % list.count]
        guard list.count > 1 else { return next }
        var id = next.id
        let sys = AudioObjectID(kAudioObjectSystemObject)
        for sel in [kAudioHardwarePropertyDefaultOutputDevice, kAudioHardwarePropertyDefaultSystemOutputDevice] {
            var a = address(sel)
            AudioObjectSetPropertyData(sys, &a, 0, nil, UInt32(MemoryLayout<AudioDeviceID>.size), &id)
        }
        Volume.refreshDevice()
        return next
    }
}

// MARK: - Brightness (DisplayServices, private)

enum Brightness {
    typealias GetFn = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32
    typealias SetFn = @convention(c) (CGDirectDisplayID, Float) -> Int32
    static let lib = dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_LAZY)
    static let getFn: GetFn? = lib.flatMap { dlsym($0, "DisplayServicesGetBrightness") }.map { unsafeBitCast($0, to: GetFn.self) }
    static let setFn: SetFn? = lib.flatMap { dlsym($0, "DisplayServicesSetBrightness") }.map { unsafeBitCast($0, to: SetFn.self) }
    /// The built-in panel is the only display DisplayServices can dim reliably. `CGMainDisplayID()` changes with
    /// external displays and after wake, so look the built-in one up instead and cache it for the gesture.
    private(set) static var target = CGMainDisplayID()
    private static func refreshTarget() {
        var ids = [CGDirectDisplayID](repeating: 0, count: 16); var count: UInt32 = 0
        if CGGetOnlineDisplayList(16, &ids, &count) == .success,
           let builtin = ids.prefix(Int(count)).first(where: { CGDisplayIsBuiltin($0) != 0 }) {
            target = builtin
        } else {
            target = CGMainDisplayID()
        }
    }
    /// nil when the current brightness cannot be read (never pretend it is 0%).
    static func get() -> Float? {
        guard let getFn = getFn else { return nil }
        refreshTarget()
        var v: Float = 0
        let r = getFn(target, &v)
        if r != 0 { log.error("DisplayServicesGetBrightness failed (\(r)) for display \(target)"); return nil }
        return v
    }
    static func set(_ value: Float) {
        let r = setFn?(target, min(max(value, 0), 1)) ?? -1
        if r != 0 { log.error("DisplayServicesSetBrightness failed (\(r)) for display \(target)") }
    }
}

/// Applies only the newest value, off the touch thread. If a hardware call hangs, the queue is abandoned
/// after 2 s and replaced, so one stuck call can no longer disable the control until relaunch.
final class Coalescer {
    private let label: String
    private let apply: (Float) -> Void
    private var queue: DispatchQueue
    private let lock = NSLock()
    private var pending: Float?
    private var scheduled = false
    private var runningSince = 0.0          // 0 = not inside apply()
    private var epoch = 0

    init(label: String, apply: @escaping (Float) -> Void) {
        self.label = label; self.apply = apply
        queue = DispatchQueue(label: label, qos: .userInteractive)
    }

    func push(_ v: Float) {
        let now = CFAbsoluteTimeGetCurrent()
        lock.lock()
        pending = v
        if scheduled {
            if runningSince != 0 && now - runningSince > 2 {
                log.error("\(self.label) hung for 2s, abandoning its queue")
                epoch += 1; scheduled = false; runningSince = 0
                queue = DispatchQueue(label: label, qos: .userInteractive)
            } else { lock.unlock(); return }
        }
        scheduled = true
        let e = epoch, q = queue
        lock.unlock()
        q.async { [self] in
            while true {
                lock.lock()
                guard e == epoch else { lock.unlock(); return }          // abandoned
                guard let p = pending else { scheduled = false; runningSince = 0; lock.unlock(); return }
                pending = nil; runningSince = CFAbsoluteTimeGetCurrent()
                lock.unlock()
                apply(p)
                lock.lock(); if e == epoch { runningSince = 0 }; lock.unlock()
            }
        }
    }
}

// MARK: - HUD

final class HUDView: NSView {
    var value: CGFloat = 0
    var showPercent = true
    var symbol = "speaker.wave.2.fill"
    override var isFlipped: Bool { false }
    override func draw(_ dirty: NSRect) {
        let r = bounds
        let pill = NSBezierPath(roundedRect: r, xRadius: 20, yRadius: 20)
        NSColor.white.withAlphaComponent(0.12).setFill(); pill.fill()

        let iconH: CGFloat = showPercent ? 64 : 44
        let bar = NSRect(x: r.minX, y: r.minY, width: r.width, height: r.height - iconH)
        NSGraphicsContext.saveGraphicsState()
        pill.addClip()
        NSColor.white.withAlphaComponent(0.92).setFill()
        NSRect(x: bar.minX, y: bar.minY, width: bar.width, height: bar.height * value).fill()
        NSGraphicsContext.restoreGraphicsState()

        if let img = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 17, weight: .semibold)) {
            let tinted = img.copy() as! NSImage
            tinted.lockFocus(); NSColor.white.set()
            NSRect(origin: .zero, size: tinted.size).fill(using: .sourceAtop); tinted.unlockFocus()
            tinted.draw(at: NSPoint(x: r.midX - tinted.size.width / 2, y: r.maxY - iconH / 2 - tinted.size.height / 2),
                        from: .zero, operation: .sourceOver, fraction: 1)
        }

        if showPercent {
            let text = "\(Int((value * 100).rounded()))%" as NSString
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .semibold),
                .foregroundColor: NSColor.white]
            let sz = text.size(withAttributes: attrs)
            text.draw(at: NSPoint(x: r.midX - sz.width / 2, y: r.maxY - iconH + 4), withAttributes: attrs)
        }
    }
}

final class HUD {
    private let size = NSSize(width: 56, height: 230)
    private let window: NSPanel
    private let view: HUDView
    private var generation = 0
    private var visible = false
    private var hiding = false
    private var shownSide: Side = .left

    // latest requested state, written from the touch thread, consumed on main
    private let lock = NSLock()
    private var latest: (Side, Bool, Float)?
    private var scheduled = false

    init() {
        window = makeHUDPanel(size: size)

        let fx = NSVisualEffectView(frame: NSRect(origin: .zero, size: size))
        fx.material = .hudWindow; fx.state = .active; fx.blendingMode = .behindWindow
        fx.maskImage = NSImage(size: NSSize(width: 40, height: 40), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: 20, yRadius: 20).fill()
            return true
        }
        fx.maskImage?.capInsets = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)
        fx.maskImage?.resizingMode = .stretch

        view = HUDView(frame: fx.bounds)
        view.autoresizingMask = [.width, .height]
        fx.addSubview(view)
        window.contentView = fx
    }

    /// Safe from any thread; coalesces so the main thread only ever draws the newest value.
    func show(_ side: Side, brightness: Bool, _ value: Float) {
        lock.lock(); latest = (side, brightness, value)
        let need = !scheduled; scheduled = true
        lock.unlock()
        if need { DispatchQueue.main.async { self.drain() } }
    }

    private func drain() {
        lock.lock(); let l = latest; scheduled = false; lock.unlock()
        guard let (side, brightness, value) = l else { return }

        view.value = CGFloat(value)
        view.showPercent = Settings.shared.showPercent
        view.symbol = brightness ? "sun.max.fill" : (value <= 0.001 ? "speaker.slash.fill" : "speaker.wave.2.fill")
        view.needsDisplay = true

        guard let sc = NSScreen.main else { return }
        let vf = sc.visibleFrame
        let y = vf.midY - size.height / 2
        let onX  = side == .left ? vf.minX + 18 : vf.maxX - size.width - 18
        let offX = side == .left ? sc.frame.minX - size.width : sc.frame.maxX
        let target = NSRect(x: onX, y: y, width: size.width, height: size.height)

        generation += 1
        let gen = generation

        if !visible || !window.isVisible || side != shownSide {
            // start fully off-screen on the correct edge
            window.alphaValue = 0
            window.setFrame(NSRect(x: offX, y: y, width: size.width, height: size.height), display: false)
            window.orderFrontRegardless()
            visible = true; shownSide = side
            slide(to: target, alpha: 1, duration: 0.22, curve: .easeOut)
        } else if hiding {
            hiding = false                      // reverse a slide-out already in flight
            slide(to: target, alpha: 1, duration: 0.15, curve: .easeOut)
        }
        // otherwise already on screen: nothing to move, just the fill redraws

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
            guard let self = self, self.generation == gen else { return }
            self.hiding = true
            let away = NSRect(x: offX, y: y, width: self.size.width, height: self.size.height)
            self.slide(to: away, alpha: 0, duration: 0.2, curve: .easeIn) {
                if self.generation == gen {
                    self.window.orderOut(nil)
                    self.visible = false; self.hiding = false
                }
            }
        }
    }

    /// Forgets any in-flight animation and hides the pill (sleep/wake, display changes). Main thread.
    func reset() {
        generation += 1
        window.orderOut(nil)
        window.alphaValue = 0
        visible = false; hiding = false
    }

    private func slide(to frame: NSRect, alpha: CGFloat, duration: TimeInterval,
                       curve: CAMediaTimingFunctionName, done: (() -> Void)? = nil) {
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = duration
            ctx.timingFunction = CAMediaTimingFunction(name: curve)
            window.animator().setFrame(frame, display: true)
            window.animator().alphaValue = alpha
        }, completionHandler: done)
    }
}

/// Horizontal pill at the top centre of the main display: icon + output device name.
final class DeviceHUD {
    private let window: NSPanel
    private let icon = NSImageView()
    private let label = NSTextField(labelWithString: "")
    private var generation = 0
    private let height: CGFloat = 52

    init() {
        window = makeHUDPanel(size: NSSize(width: 240, height: height))

        let fx = NSVisualEffectView()
        fx.material = .hudWindow; fx.state = .active; fx.blendingMode = .behindWindow
        fx.maskImage = NSImage(size: NSSize(width: 40, height: 40), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: 20, yRadius: 20).fill()
            return true
        }
        fx.maskImage?.capInsets = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)
        fx.maskImage?.resizingMode = .stretch

        icon.contentTintColor = .white
        icon.symbolConfiguration = .init(pointSize: 17, weight: .semibold)
        label.font = .systemFont(ofSize: 13, weight: .semibold)
        label.textColor = .white
        label.lineBreakMode = .byTruncatingTail
        let stack = NSStackView(views: [icon, label])
        stack.spacing = 10
        stack.edgeInsets = NSEdgeInsets(top: 0, left: 18, bottom: 0, right: 20)
        stack.translatesAutoresizingMaskIntoConstraints = false
        fx.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: fx.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: fx.trailingAnchor),
            stack.centerYAnchor.constraint(equalTo: fx.centerYAnchor),
        ])
        window.contentView = fx
    }

    /// Safe from any thread.
    func show(_ device: AudioOutput.Device) {
        DispatchQueue.main.async { [self] in
            icon.image = NSImage(systemSymbolName: device.symbol, accessibilityDescription: nil)
            label.stringValue = device.name
            let width = min(max(label.intrinsicContentSize.width + 18 + 17 + 10 + 20 + 4, 150), 420)
            guard let sc = NSScreen.main else { return }
            let vf = sc.visibleFrame
            let x = vf.midX - width / 2
            let on = NSRect(x: x, y: vf.maxY - height - 14, width: width, height: height)
            let off = on.offsetBy(dx: 0, dy: 30)
            generation += 1
            let gen = generation
            if !window.isVisible {
                window.alphaValue = 0
                window.setFrame(off, display: false)
                window.orderFrontRegardless()
            }
            slide(to: on, alpha: 1, duration: 0.22, curve: .easeOut)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { [weak self] in
                guard let self = self, self.generation == gen else { return }
                self.slide(to: off, alpha: 0, duration: 0.2, curve: .easeIn) {
                    if self.generation == gen { self.window.orderOut(nil) }
                }
            }
        }
    }

    private func slide(to frame: NSRect, alpha: CGFloat, duration: TimeInterval,
                       curve: CAMediaTimingFunctionName, done: (() -> Void)? = nil) {
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = duration
            ctx.timingFunction = CAMediaTimingFunction(name: curve)
            window.animator().setFrame(frame, display: true)
            window.animator().alphaValue = alpha
        }, completionHandler: done)
    }
}

// MARK: - Edge gesture state machine

enum Side { case left, right }

final class EdgeController {
    private let hud = HUD()
    private let cfg = Settings.shared

    // gesture state (touch thread only)
    private var side: Side?
    private var trackedID: Int32 = -1
    private var landedInEdge = false
    private var landSide: Side = .left
    private var startX: Float = 0, startY: Float = 0, lastY: Float = 0
    private var startT: Double = 0
    private var maxMove: Float = 0
    private var value: Float = 0
    private var anchor = CGPoint.zero
    private var frozen = false
    private var lastTick = 0
    private var atLimit = false
    private enum Corner { case none, right, left }   // right = Quick Mute, left = Switch Output
    private var corner = Corner.none
    private var lastTap: [Corner: (t: Double, x: Float, y: Float)] = [:]   // first tap of a pending double-tap
    private let deviceHUD = DeviceHUD()
    // New gestures are ineligible until every finger lifts: set by a palm-sized contact or by a second finger
    // (so a palm that stays after the other finger lifts is never taken for a fresh landing).
    private var lockout = false

    // Touch frames arrive on one thread per device, and sleep/wake handlers run on main: all gesture state is guarded.
    private let stateLock = NSLock()
    private var activeDevice: UnsafeMutableRawPointer?
    private var lastFrame = 0.0

    // coalesced output: only the newest value is ever applied; brightness and volume never block each other
    private let brightnessOut = Coalescer(label: "edgeslider.brightness") { Brightness.set($0) }
    private let volumeOut = Coalescer(label: "edgeslider.volume") { Volume.set($0) }
    private let actionQueue = DispatchQueue(label: "edgeslider.action", qos: .userInteractive)

    private func isBrightness(_ s: Side) -> Bool { (s == .left) != cfg.swapSides }
    private var volumeSide: Side { cfg.swapSides ? .left : .right }

    private func push(brightness: Bool, _ value: Float) {
        (brightness ? brightnessOut : volumeOut).push(value)
    }

    /// True when no finger is being tracked (safe moment to rebuild the device list).
    var isIdle: Bool { stateLock.lock(); defer { stateLock.unlock() }; return trackedID == -1 }

    /// Drops any gesture in progress and releases the pointer. Call on sleep, wake and display changes (main thread).
    func reset() {
        stateLock.lock()
        end(); trackedID = -1; corner = .none; lastTap = [:]; activeDevice = nil
        lockout = false
        stateLock.unlock()
        hud.reset()
    }

    private func perform(_ p: NSHapticFeedbackManager.FeedbackPattern) {
        DispatchQueue.main.async {
            NSHapticFeedbackManager.defaultPerformer.perform(p, performanceTime: .now)
        }
    }
    private func tickHaptic() {
        switch cfg.haptic { case .off: break; case .light: perform(.alignment); case .strong: perform(.levelChange) }
    }
    private func bumpHaptic() { if cfg.haptic != .off { perform(.levelChange) } }

    // Called on the multitouch callback thread with the single touch (nil if no finger is touching or >1 fingers)
    // `touching` = contacts in state 4; `maxSize`/`maxMajor` = the largest contact among them (palm detection).
    func update(device: UnsafeMutableRawPointer?, touch: (id: Int32, x: Float, y: Float)?, count: Int32,
                touching: Int32, maxSize: Float, maxMajor: Float) {
        stateLock.lock(); defer { stateLock.unlock() }
        let now = CFAbsoluteTimeGetCurrent()
        // a second multitouch device (second trackpad) must not hijack a gesture already in progress
        if trackedID != -1, let d = device, let a = activeDevice, d != a { return }
        activeDevice = device
        lastFrame = now
        guard cfg.enabled else { end(); trackedID = -1; return }

        // palm rejection: a palm-sized contact anywhere on the pad cancels the gesture and locks out new ones until every finger lifts
        let palmLimit = side != nil ? Palm.engaged : Palm.landing
        let palm = maxSize > palmLimit.size || maxMajor > palmLimit.major
        if palm || touching > 1 {
            lockout = true
            if palm && (side != nil || landedInEdge) { end(); landedInEdge = false }
        }
        if touching == 0 { lockout = false }
        guard let t = touch else {
            if count <= 1 { finishTap(now) }
            end(); trackedID = -1; return
        }

        // new finger: classify where it LANDED
        if t.id != trackedID {
            end()
            trackedID = t.id
            let ew = cfg.edgeWidth
            let inEdge = t.x < ew || t.x > 1 - ew
            let zoneOK = !cfg.bottomQuarterOnly || t.y < 0.25
            let solo = !lockout
            // the key-press query is only made for landings that could otherwise count
            landedInEdge = inEdge && zoneOK && solo && Palm.secondsSinceKey() >= Palm.keyGuard
            landSide = t.x < 0.5 ? .left : .right
            startX = t.x; startY = t.y; lastY = t.y; startT = now; maxMove = 0
            let inCornerRow = cfg.cornerEdge == .top ? t.y > 0.86 : t.y < 0.14
            corner = !inCornerRow || !solo ? .none
                   : (cfg.quickMute && t.x > 0.86) ? .right
                   : (cfg.switchOutput && t.x < 0.14) ? .left : .none
        }
        maxMove = max(maxMove, abs(t.x - startX), abs(t.y - startY))

        guard landedInEdge else { return }

        if side == nil {
            // not engaged yet: cancel if it drifts inward, engage after the hold delay and the vertical dead zone
            let edgeDist = landSide == .left ? t.x : 1 - t.x
            if edgeDist > cfg.edgeWidth * 1.8 { landedInEdge = false; return }
            if abs(t.y - startY) > deadZone {
                // hold delay: a finger must rest on the edge first. Moving sooner is a palm sliding past or a swipe.
                if now - startT < Double(cfg.holdDelay) { landedInEdge = false; return }
                begin(landSide, t)
            }
            return
        }

        if frozen { CGWarpMouseCursorPosition(anchor) }   // keep pointer pinned
        value = min(max(value + (t.y - lastY) * cfg.sensitivity, 0), 1)
        lastY = t.y

        let steps: Float = cfg.haptic == .light ? 10 : 20
        let tick = Int((value * steps).rounded())
        let limit = value <= 0 || value >= 1
        if limit && !atLimit { bumpHaptic() }
        else if !limit && tick != lastTick { tickHaptic() }
        atLimit = limit; lastTick = tick

        let b = isBrightness(landSide)
        hud.show(landSide, brightness: b, value)         // visual first, straight from the touch
        push(brightness: b, value)
    }

    private func begin(_ s: Side, _ t: (id: Int32, x: Float, y: Float)) {
        let b = isBrightness(s)
        // never engage on an unreadable brightness: starting from a fake 0% would blank the screen or do nothing
        guard let startValue = b ? Brightness.get() : Optional(Volume.get()) else { landedInEdge = false; return }
        side = s; lastY = t.y
        value = startValue
        let steps: Float = cfg.haptic == .light ? 10 : 20
        lastTick = Int((value * steps).rounded()); atLimit = false
        if cfg.freezeCursor {
            anchor = CGEvent(source: nil)?.location ?? .zero
            CGAssociateMouseAndMouseCursorPosition(0)
            frozen = true
        }
        bumpHaptic()                                     // "grabbed the control"
        hud.show(s, brightness: b, value)
        armFrameWatchdog()
    }

    /// If frames stop while a gesture is engaged (sleep, device drop), release the frozen pointer instead of keeping it.
    private func armFrameWatchdog() {
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 1.5) { [weak self] in
            guard let self = self else { return }
            self.stateLock.lock(); defer { self.stateLock.unlock() }
            guard self.side != nil else { return }
            if CFAbsoluteTimeGetCurrent() - self.lastFrame > 1.5 {
                log.error("no touch frames for 1.5s during a gesture, releasing")
                self.end(); self.trackedID = -1
            } else { self.armFrameWatchdog() }
        }
    }

    func end() {
        guard side != nil else { return }
        side = nil
        if frozen { CGAssociateMouseAndMouseCursorPosition(1); frozen = false }
    }

    // MARK: corner double-taps: right corner mutes, left corner switches the output device (top or bottom row, see Settings.cornerEdge)

    private func finishTap(_ now: Double) {
        guard trackedID != -1, corner != .none, maxMove < 0.06, now - startT < 0.6 else { return }
        // typing guard: a palm resting on a corner while typing is not a tap
        guard Palm.secondsSinceKey() > Palm.keyGuard else { lastTap[corner] = nil; return }
        // same-spot check: the second tap must land near the first
        guard let first = lastTap[corner], now - first.t < 0.7,
              abs(startX - first.x) < 0.12, abs(startY - first.y) < 0.12 else {
            lastTap[corner] = (now, startX, startY)
            return
        }
        lastTap[corner] = nil
        bumpHaptic()
        if corner == .right {
            let vs = volumeSide
            actionQueue.async { [self] in
                let m = Volume.toggleMute()
                hud.show(vs, brightness: false, m ? 0 : Volume.get())
            }
        } else {
            actionQueue.async { [self] in
                if let d = AudioOutput.cycle() { deviceHUD.show(d) }
            }
        }
    }
}

let controller = EdgeController()

// MARK: - Multitouch (private MultitouchSupport)

typealias MTCallback = @convention(c) (UnsafeMutableRawPointer?, UnsafeMutableRawPointer?, Int32, Double, Int32) -> Int32
typealias MTCreateList = @convention(c) () -> Unmanaged<CFArray>?
typealias MTRegister = @convention(c) (UnsafeMutableRawPointer, MTCallback) -> Void
typealias MTStart = @convention(c) (UnsafeMutableRawPointer, Int32) -> Void

private let touchStride = 96          // sizeof(MTTouch)
private let normXOffset = 32          // normalized.position.x (Float)
private let identifierOffset = 16
private let stateOffset = 20

typealias MTUnregister = @convention(c) (UnsafeMutableRawPointer, MTCallback) -> Void
typealias MTStop = @convention(c) (UnsafeMutableRawPointer) -> Void
typealias MTDimensions = @convention(c) (UnsafeMutableRawPointer, UnsafeMutablePointer<Int32>, UnsafeMutablePointer<Int32>) -> Int32

var framesSinceStart = 0

// Developer tool (`EdgeSlider --log-touches`): prints every contact in every frame to stdout as CSV so contact
// size fields can be calibrated for palm rejection. Offsets follow the community MTTouch layout and are unverified.
let logTouches = CommandLine.arguments.contains("--log-touches")
private let sizeOffset = 48, pressureOffset = 52, angleOffset = 56, majorOffset = 60, minorOffset = 64, densityOffset = 92

private func logFrame(_ data: UnsafeMutableRawPointer, count: Int32, time: Double) {
    for i in 0..<Int(count) {
        let d = data + i * touchStride
        let f = { (o: Int) in String(format: "%.4f", d.load(fromByteOffset: o, as: Float.self)) }
        let line = "\(String(format: "%.3f", time)),\(count),\(d.load(fromByteOffset: identifierOffset, as: Int32.self)),"
            + "\(d.load(fromByteOffset: stateOffset, as: Int32.self)),\(f(normXOffset)),\(f(normXOffset + 4)),"
            + "\(f(sizeOffset)),\(d.load(fromByteOffset: pressureOffset, as: Int32.self)),\(f(angleOffset)),"
            + "\(f(majorOffset)),\(f(minorOffset)),\(f(densityOffset))\n"
        fputs(line, stdout)
    }
}

let mtCallback: MTCallback = { dev, data, count, ts, _ in
    framesSinceStart &+= 1
    if logTouches, let d = data, count > 0 { logFrame(d, count: count, time: ts) }
    var touch: (id: Int32, x: Float, y: Float)? = nil
    var touching: Int32 = 0
    var maxSize: Float = 0, maxMajor: Float = 0
    if let d = data, count > 0 {
        for i in 0..<Int(count) {
            let p = d + i * touchStride
            guard p.load(fromByteOffset: stateOffset, as: Int32.self) == 4 else { continue }   // 4 = touching
            touching += 1
            maxSize = max(maxSize, p.load(fromByteOffset: sizeOffset, as: Float.self))
            maxMajor = max(maxMajor, p.load(fromByteOffset: majorOffset, as: Float.self))
            if count == 1 {
                touch = (p.load(fromByteOffset: identifierOffset, as: Int32.self),
                         p.load(fromByteOffset: normXOffset, as: Float.self),
                         p.load(fromByteOffset: normXOffset + 4, as: Float.self))
            }
        }
    }
    controller.update(device: dev, touch: touch, count: count, touching: touching, maxSize: maxSize, maxMajor: maxMajor)
    return 0
}

/// Owns the private MultitouchSupport devices. The device list is kept alive while callbacks are registered
/// (releasing it left dangling device pointers), and can be rebuilt after sleep, display changes or a reconnect.
final class MultitouchManager {
    static let shared = MultitouchManager()

    private let create: MTCreateList?, register: MTRegister?, startFn: MTStart?
    private let unregister: MTUnregister?, stopFn: MTStop?, dims: MTDimensions?
    private var devices: CFArray?
    private var active: [UnsafeMutableRawPointer] = []
    private var activeSignature: [Int] = []
    private var restartToken = 0
    private var lastRestart = 0.0

    private init() {
        let lib = dlopen("/System/Library/PrivateFrameworks/MultitouchSupport.framework/MultitouchSupport", RTLD_LAZY)
        func sym<T>(_ name: String, _ type: T.Type) -> T? {
            lib.flatMap { dlsym($0, name) }.map { unsafeBitCast($0, to: type) }
        }
        create = sym("MTDeviceCreateList", MTCreateList.self)
        register = sym("MTRegisterContactFrameCallback", MTRegister.self)
        startFn = sym("MTDeviceStart", MTStart.self)
        unregister = sym("MTUnregisterContactFrameCallback", MTUnregister.self)
        stopFn = sym("MTDeviceStop", MTStop.self)
        dims = sym("MTDeviceGetSensorSurfaceDimensions", MTDimensions.self)
    }

    private func allDevices(in list: CFArray) -> [UnsafeMutableRawPointer] {
        (0..<CFArrayGetCount(list)).compactMap { CFArrayGetValueAtIndex(list, $0).map { UnsafeMutableRawPointer(mutating: $0) } }
    }

    /// Trackpads only: a Magic Mouse is also a multitouch device (taller than wide), and its touches are not edge gestures.
    private func sensorSize(of dev: UnsafeMutableRawPointer) -> (w: Int32, h: Int32)? {
        var w: Int32 = 0, h: Int32 = 0
        guard let dims = dims, dims(dev, &w, &h) == 0, w > 0, h > 0 else { return nil }
        return (w, h)
    }

    private func trackpads(in list: CFArray) -> [UnsafeMutableRawPointer] {
        let all = allDevices(in: list)
        let pads = all.filter { sensorSize(of: $0).map { $0.w >= $0.h } ?? true }
        return pads.isEmpty ? all : pads            // never end up with no device because of the heuristic
    }

    /// Stable description of a set of trackpads (count + sensor sizes). Device pointers can't be compared:
    /// MTDeviceCreateList hands back different objects on every call, even for the same trackpad.
    private func signature(of pads: [UnsafeMutableRawPointer]) -> [Int] {
        pads.map { dev in sensorSize(of: dev).map { Int($0.w) << 16 | Int($0.h) } ?? 0 }.sorted()
    }

    /// Main thread. Returns false if no device could be started.
    @discardableResult
    func start() -> Bool {
        stop()
        guard let create = create, let register = register, let startFn = startFn,
              let list = create()?.takeRetainedValue() else { return false }
        devices = list
        active = trackpads(in: list)
        activeSignature = signature(of: active)
        for dev in active { register(dev, mtCallback); startFn(dev, 0) }
        lastRestart = CFAbsoluteTimeGetCurrent()
        log.notice("multitouch started: \(self.active.count) of \(CFArrayGetCount(list)) devices, \(framesSinceStart) frames since launch")
        return !active.isEmpty
    }

    func stop() {
        for dev in active { unregister?(dev, mtCallback); stopFn?(dev) }
        active = []; devices = nil
    }

    /// Debounced restart, for wake and display notifications (devices are often not ready right away).
    func scheduleRestart(_ reason: String, after delay: TimeInterval) {
        restartToken += 1
        let token = restartToken
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [self] in
            guard token == restartToken else { return }
            log.notice("restarting multitouch: \(reason)")
            controller.reset()
            start()
        }
    }

    /// Cheap self-heal when the user opens the panel (they may be doing it because the sliders stopped working).
    func restartIfStale() {
        guard CFAbsoluteTimeGetCurrent() - lastRestart > 60, controller.isIdle else { return }
        log.notice("restarting multitouch: panel opened")
        start()
    }

    /// Periodic check: if the set of trackpads changed (reconnect, hot-plug), rebuild.
    func checkDevices() {
        guard controller.isIdle, let create = create, let list = create()?.takeRetainedValue() else { return }
        let fresh = signature(of: trackpads(in: list))
        if fresh != activeSignature {
            log.notice("trackpad list changed (\(self.activeSignature.count) -> \(fresh.count)), restarting multitouch")
            start()
        }
    }
}

// MARK: - App / menu bar

import SwiftUI
import Combine

final class AppDelegate: NSObject, NSApplicationDelegate {
    let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    let popover = NSPopover()
    private var pausedObserver: AnyCancellable?
    private var updateObserver: AnyCancellable?
    private var activity: NSObjectProtocol?
    private var observers: [NSObjectProtocol] = []
    private var watchdog: Timer?

    /// Keeps the input alive across days: no App Nap, release the pointer on sleep, rebuild trackpad input on wake/display changes.
    private func installRecovery() {
        activity = ProcessInfo.processInfo.beginActivity(options: .userInitiatedAllowingIdleSystemSleep,
                                                         reason: "Listening for trackpad edge gestures")
        let ws = NSWorkspace.shared.notificationCenter
        observers.append(ws.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { _ in
            controller.reset()
        })
        for name in [NSWorkspace.didWakeNotification, NSWorkspace.screensDidWakeNotification] {
            observers.append(ws.addObserver(forName: name, object: nil, queue: .main) { _ in
                MultitouchManager.shared.scheduleRestart("wake", after: 1.5)
            })
        }
        observers.append(NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { _ in
            MultitouchManager.shared.scheduleRestart("display change", after: 1.0)
        })
        watchdog = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { _ in
            MultitouchManager.shared.checkDevices()
        }
    }

    /// Trackpad outline with two slider bars. A template image, so macOS tints it for light/dark menu bars.
    static func menuBarGlyph() -> NSImage {
        let img = NSImage(size: NSSize(width: 20, height: 20), flipped: true) { _ in
            let k: CGFloat = 20.0 / 24.0
            NSColor.black.setStroke(); NSColor.black.setFill()
            let frame = NSBezierPath(roundedRect: NSRect(x: 2.5 * k, y: 5 * k, width: 19 * k, height: 14 * k),
                                     xRadius: 3 * k, yRadius: 3 * k)
            frame.lineWidth = 1.6 * k; frame.stroke()
            NSBezierPath(roundedRect: NSRect(x: 5.4 * k, y: 9 * k, width: 2 * k, height: 7 * k),
                         xRadius: k, yRadius: k).fill()
            NSBezierPath(roundedRect: NSRect(x: 16.6 * k, y: 12 * k, width: 2 * k, height: 4 * k),
                         xRadius: k, yRadius: k).fill()
            return true
        }
        img.isTemplate = true
        return img
    }

    func applicationDidFinishLaunching(_ n: Notification) {
        // developer tool: render README screenshots and quit (see scripts/screenshots.sh)
        let args = CommandLine.arguments
        if let i = args.firstIndex(of: "--render-screenshots"), i + 1 < args.count {
            Screenshots.render(to: args[i + 1])
            NSApp.terminate(nil)
            return
        }

        item.button?.image = AppDelegate.menuBarGlyph()
        item.button?.setAccessibilityLabel("EdgeSlider")
        // dim the icon while EdgeSlider is paused
        pausedObserver = Settings.shared.$enabled.sink { [weak self] on in
            DispatchQueue.main.async { self?.item.button?.appearsDisabled = !on }
        }
        item.button?.target = self
        item.button?.action = #selector(togglePopover)

        let host = NSHostingController(rootView: PopoverRoot())
        host.sizingOptions = .preferredContentSize
        popover.contentViewController = host
        popover.behavior = .transient

        // updates: start Sparkle, and tint the menu bar icon while an update is waiting
        Updater.shared.start()
        updateObserver = Updater.shared.$availableVersion.sink { [weak self] v in
            DispatchQueue.main.async {
                self?.item.button?.contentTintColor = v == nil ? nil : .systemOrange
                self?.item.button?.toolTip = v.map { "EdgeSlider \($0) is available" } ?? "EdgeSlider"
            }
        }

        installRecovery()
        if !MultitouchManager.shared.start() {
            let a = NSAlert(); a.messageText = "No trackpad found"; a.runModal()
        }
    }

    @objc func togglePopover() {
        guard let b = item.button else { return }
        if popover.isShown { popover.performClose(nil) }
        else {
            MultitouchManager.shared.restartIfStale()
            popover.show(relativeTo: b.bounds, of: b, preferredEdge: .minY)
            NSApp.activate(ignoringOtherApps: true)
        }
    }
    func applicationWillTerminate(_ n: Notification) { controller.reset() }
}

// one instance only: if another copy is already running, leave it alone and quit this one
if !CommandLine.arguments.contains("--render-screenshots"),
   let id = Bundle.main.bundleIdentifier,
   NSRunningApplication.runningApplications(withBundleIdentifier: id)
       .contains(where: { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }) {
    exit(0)
}

if logTouches {
    setvbuf(stdout, nil, _IOLBF, 0)
    print("t,count,id,state,x,y,size,pressure,angle,major,minor,zdensity")
}
let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = AppDelegate()
app.delegate = delegate
app.run()
