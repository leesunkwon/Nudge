//
//  AppDelegate.swift
//  Nudge
//
//  Created by Codex on 6/16/26.
//

import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var overlayController: NudgeOverlayWindowController?
    private let settingsStore = NudgeSettingsStore()
    private lazy var settingsWindowController = SettingsWindowController(settingsStore: settingsStore)

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        let overlayController = NudgeOverlayWindowController(
            settingsStore: settingsStore,
            onOpenSettings: { [weak self] in
                self?.settingsWindowController.showSettings()
            }
        )
        overlayController.showOverlay()
        self.overlayController = overlayController
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}
