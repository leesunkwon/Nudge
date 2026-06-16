//
//  SettingsWindowController.swift
//  Nudge
//
//  Created by Codex on 6/16/26.
//

import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController: NSWindowController {
    private let settingsStore: NudgeSettingsStore

    init(settingsStore: NudgeSettingsStore) {
        self.settingsStore = settingsStore

        let rootView = SettingsView(settingsStore: settingsStore)
        let hostingController = NSHostingController(rootView: rootView)
        let window = NSWindow(contentViewController: hostingController)
        window.title = "Nudge 설정"
        window.setContentSize(NSSize(width: 640, height: 680))
        window.minSize = NSSize(width: 560, height: 560)
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.isReleasedWhenClosed = false
        window.center()

        super.init(window: window)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    func showSettings() {
        window?.center()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
