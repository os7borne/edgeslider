import Cocoa
import CoreAudio

// MARK: - Settings

let deadZone: Float = 0.035      // vertical travel (fraction of pad height) before the control engages

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

/// Posts a system media key press (next=17, previous=18).
func sendMediaKey(_ key: Int) {
    for down in [true, false] {
        let flags = NSEvent.ModifierFlags(rawValue: down ? 0xa00 : 0xb00)
        let data1 = (key << 16) | ((down ? 0xa : 0xb) << 8)
        NSEvent.otherEvent(with: .systemDefined, location: .zero, modifierFlags: flags, timestamp: 0,
                           windowNumber: 0, context: nil, subtype: 8, data1: data1, data2: -1)?
            .cgEvent?.post(tap: .cghidEventTap)
    }
}

// MARK: - Brightness (DisplayServices, private)

enum Brightness {
    typealias GetFn = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32
    typealias SetFn = @convention(c) (CGDirectDisplayID, Float) -> Int32
    static let lib = dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_LAZY)
    static let getFn: GetFn? = lib.flatMap { dlsym($0, "DisplayServicesGetBrightness") }.map { unsafeBitCast($0, to: GetFn.self) }
    static let setFn: SetFn? = lib.flatMap { dlsym($0, "DisplayServicesSetBrightness") }.map { unsafeBitCast($0, to: SetFn.self) }
    static func get() -> Float {
        var v: Float = 0
        _ = getFn?(CGMainDisplayID(), &v)
        return v
    }
    static func set(_ value: Float) { _ = setFn?(CGMainDisplayID(), min(max(value, 0), 1)) }
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
    private let window: NSWindow
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
        window = NSWindow(contentRect: NSRect(origin: .zero, size: size),
                          styleMask: .borderless, backing: .buffered, defer: false)
        window.level = .screenSaver
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.ignoresMouseEvents = true
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]

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

        if !visible || side != shownSide {
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
    private var bottomStrip = false
    private var mediaFired = false
    private var cornerCandidate = false
    private var lastCornerTap: Double = 0

    // coalesced output: only the newest value is ever applied
    private let applyQueue = DispatchQueue(label: "edgeslider.apply", qos: .userInteractive)
    private let lock = NSLock()
    private var pending: (Bool, Float)?

    private func isBrightness(_ s: Side) -> Bool { (s == .left) != cfg.swapSides }
    private var volumeSide: Side { cfg.swapSides ? .left : .right }

    private func push(brightness: Bool, _ value: Float) {
        lock.lock(); let busy = pending != nil; pending = (brightness, value); lock.unlock()
        if busy { return }
        applyQueue.async { [self] in
            lock.lock(); let p = pending; pending = nil; lock.unlock()
            guard let (isB, v) = p else { return }
            if isB { Brightness.set(v) } else { Volume.set(v) }
        }
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
    func update(touch: (id: Int32, x: Float, y: Float)?, count: Int32) {
        let now = CFAbsoluteTimeGetCurrent()
        guard cfg.enabled else { end(); trackedID = -1; return }
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
            landedInEdge = inEdge && zoneOK
            landSide = t.x < 0.5 ? .left : .right
            startX = t.x; startY = t.y; lastY = t.y; startT = now; maxMove = 0
            mediaFired = false
            bottomStrip = cfg.mediaStrip && t.y < 0.10 && !inEdge
            cornerCandidate = cfg.quickMute && t.x > 0.86 && t.y > 0.86
        }
        maxMove = max(maxMove, abs(t.x - startX), abs(t.y - startY))

        if bottomStrip { handleMedia(t); return }
        guard landedInEdge else { return }

        if side == nil {
            // not engaged yet: cancel if it drifts inward, engage after vertical dead zone
            let edgeDist = landSide == .left ? t.x : 1 - t.x
            if edgeDist > cfg.edgeWidth * 1.8 { landedInEdge = false; return }
            if abs(t.y - startY) > deadZone { begin(landSide, t) }
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
        side = s; lastY = t.y
        let b = isBrightness(s)
        value = b ? Brightness.get() : Volume.get()
        let steps: Float = cfg.haptic == .light ? 10 : 20
        lastTick = Int((value * steps).rounded()); atLimit = false
        if cfg.freezeCursor {
            anchor = CGEvent(source: nil)?.location ?? .zero
            CGAssociateMouseAndMouseCursorPosition(0)
            frozen = true
        }
        bumpHaptic()                                     // "grabbed the control"
        hud.show(s, brightness: b, value)
    }

    func end() {
        guard side != nil else { return }
        side = nil
        if frozen { CGAssociateMouseAndMouseCursorPosition(1); frozen = false }
    }

    // MARK: media strip: horizontal swipe along the bottom edge

    private func handleMedia(_ t: (id: Int32, x: Float, y: Float)) {
        guard !mediaFired else { return }
        let dx = t.x - startX
        if abs(dx) > 0.22 && abs(t.y - startY) < 0.2 {
            mediaFired = true                            // once per swipe
            sendMediaKey(dx > 0 ? 17 : 18)               // next / previous
            bumpHaptic()
        }
    }

    // MARK: quick mute: double-tap the top-right corner

    private func finishTap(_ now: Double) {
        guard trackedID != -1, cornerCandidate, maxMove < 0.025, now - startT < 0.25 else { return }
        if now - lastCornerTap < 0.45 {
            lastCornerTap = 0
            bumpHaptic()
            let vs = volumeSide
            applyQueue.async { [self] in
                let m = Volume.toggleMute()
                hud.show(vs, brightness: false, m ? 0 : Volume.get())
            }
        } else {
            lastCornerTap = now
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

let mtCallback: MTCallback = { _, data, count, _, _ in
    var touch: (id: Int32, x: Float, y: Float)? = nil
    if count == 1, let d = data {
        let state = d.load(fromByteOffset: stateOffset, as: Int32.self)
        if state == 4 {  // touching
            touch = (d.load(fromByteOffset: identifierOffset, as: Int32.self),
                     d.load(fromByteOffset: normXOffset, as: Float.self),
                     d.load(fromByteOffset: normXOffset + 4, as: Float.self))
        }
    }
    controller.update(touch: touch, count: count)
    return 0
}

func startMultitouch() -> Bool {
    guard let lib = dlopen("/System/Library/PrivateFrameworks/MultitouchSupport.framework/MultitouchSupport", RTLD_LAZY),
          let c = dlsym(lib, "MTDeviceCreateList"), let r = dlsym(lib, "MTRegisterContactFrameCallback"),
          let s = dlsym(lib, "MTDeviceStart") else { return false }
    let create = unsafeBitCast(c, to: MTCreateList.self)
    let register = unsafeBitCast(r, to: MTRegister.self)
    let start = unsafeBitCast(s, to: MTStart.self)
    guard let list = create()?.takeRetainedValue() else { return false }
    for i in 0..<CFArrayGetCount(list) {
        let dev = UnsafeMutableRawPointer(mutating: CFArrayGetValueAtIndex(list, i))!
        register(dev, mtCallback)
        start(dev, 0)
    }
    return CFArrayGetCount(list) > 0
}

// MARK: - App / menu bar

import SwiftUI
import Combine

final class AppDelegate: NSObject, NSApplicationDelegate {
    let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    let popover = NSPopover()
    private var pausedObserver: AnyCancellable?
    private var updateObserver: AnyCancellable?

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

        if !startMultitouch() {
            let a = NSAlert(); a.messageText = "No trackpad found"; a.runModal()
        }
    }

    @objc func togglePopover() {
        guard let b = item.button else { return }
        if popover.isShown { popover.performClose(nil) }
        else {
            popover.show(relativeTo: b.bounds, of: b, preferredEdge: .minY)
            NSApp.activate(ignoringOtherApps: true)
        }
    }
    func applicationWillTerminate(_ n: Notification) { controller.end() }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = AppDelegate()
app.delegate = delegate
app.run()
