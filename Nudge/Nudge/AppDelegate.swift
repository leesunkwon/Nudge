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

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        let overlayController = NudgeOverlayWindowController()
        overlayController.showOverlay()
        self.overlayController = overlayController
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}
