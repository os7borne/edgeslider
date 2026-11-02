// SPDX-License-Identifier: GPL-3.0-or-later
// EdgeSlider, Copyright (C) 2026 Osborne Saldanha. See LICENSE.

import Cocoa
import Sparkle

/// Thin wrapper around Sparkle. The feed URL and public key live in Info.plist (see build.sh).
///
/// Scheduled checks are "gentle": when an update turns up while you aren't looking, EdgeSlider doesn't pop a
/// window. It tints the menu bar icon and shows an "Install" banner in the panel instead.
final class Updater: NSObject, ObservableObject, SPUUpdaterDelegate, SPUStandardUserDriverDelegate {
    static let shared = Updater()

    /// Version string of an update that is waiting for the user, if any.
    @Published var availableVersion: String?

    private var controller: SPUStandardUpdaterController!

    override init() {
        super.init()
        controller = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: self, userDriverDelegate: self)
    }

    func start() { controller.startUpdater() }

    func checkForUpdates() {
        NSApp.activate(ignoringOtherApps: true)      // EdgeSlider is a menu bar app: bring Sparkle's window forward
        controller.checkForUpdates(nil)
    }

    var automaticChecks: Bool {
        get { controller.updater.automaticallyChecksForUpdates }
        set { objectWillChange.send(); controller.updater.automaticallyChecksForUpdates = newValue }
    }

    // MARK: SPUStandardUserDriverDelegate (gentle reminders)

    var supportsGentleScheduledUpdateReminders: Bool { true }

    func standardUserDriverShouldHandleShowingScheduledUpdate(_ update: SUAppcastItem, andInImmediateFocus immediateFocus: Bool) -> Bool {
        immediateFocus
    }

    func standardUserDriverWillHandleShowingUpdate(_ handleShowingUpdate: Bool, forUpdate update: SUAppcastItem, state: SPUUserUpdateState) {
        if !handleShowingUpdate {
            DispatchQueue.main.async { self.availableVersion = update.displayVersionString }
        }
    }

    func standardUserDriverDidReceiveUserAttention(forUpdate update: SUAppcastItem) {
        DispatchQueue.main.async { self.availableVersion = nil }
    }

    func standardUserDriverWillFinishUpdateSession() {
        DispatchQueue.main.async { self.availableVersion = nil }
    }
}
