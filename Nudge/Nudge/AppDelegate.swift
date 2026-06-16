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
    private var statusItem: NSStatusItem?
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
        installStatusItem()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    private func installStatusItem() {
        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            button.image = NSImage(
                systemSymbolName: "sparkles",
                accessibilityDescription: "Nudge 설정"
            )
            button.imagePosition = .imageOnly
            button.target = self
            button.action = #selector(openSettingsFromStatusItem)
            button.toolTip = "Nudge 설정"
        }

        self.statusItem = statusItem
    }

    @objc private func openSettingsFromStatusItem() {
        settingsWindowController.showSettings()
    }
}
