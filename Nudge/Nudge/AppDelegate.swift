//
//  AppDelegate.swift
//  Nudge
//
//  Created by Codex on 6/16/26.
//

import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var overlayController: NudgeOverlayWindowController?
    private var statusItem: NSStatusItem?
    private let statusMenu = NSMenu()
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
        statusMenu.delegate = self

        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            button.image = NSImage(
                systemSymbolName: "sparkles",
                accessibilityDescription: "Nudge"
            )
            button.imagePosition = .imageOnly
            button.toolTip = "Nudge"
        }
        statusItem.menu = statusMenu

        self.statusItem = statusItem
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        rebuildStatusMenu()
    }

    private func rebuildStatusMenu() {
        statusMenu.removeAllItems()

        let titleItem = NSMenuItem(title: "Nudge", action: nil, keyEquivalent: "")
        titleItem.isEnabled = false
        statusMenu.addItem(titleItem)

        let modelTitle = overlayController?.isPaused == true
            ? "상태: 일시 중지됨"
            : "현재 모델: \(overlayController?.currentModelStatusText ?? settingsStore.selectedModel.title)"
        let modelItem = NSMenuItem(title: modelTitle, action: nil, keyEquivalent: "")
        modelItem.isEnabled = false
        statusMenu.addItem(modelItem)

        statusMenu.addItem(.separator())

        if overlayController?.isPaused == true {
            statusMenu.addItem(menuItem(title: "다시 시작", action: #selector(resumeNudgeFromStatusItem)))
        } else {
            statusMenu.addItem(menuItem(title: "일시 중지", action: #selector(pauseNudgeFromStatusItem)))
        }

        statusMenu.addItem(.separator())
        statusMenu.addItem(menuItem(title: "설정...", action: #selector(openSettingsFromStatusItem)))
        statusMenu.addItem(menuItem(title: "종료", action: #selector(terminateFromStatusItem)))
    }

    private func menuItem(title: String, action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    @objc private func pauseNudgeFromStatusItem() {
        overlayController?.pauseOverlay()
    }

    @objc private func resumeNudgeFromStatusItem() {
        overlayController?.resumeOverlay()
    }

    @objc private func openSettingsFromStatusItem() {
        settingsWindowController.showSettings()
    }

    @objc private func terminateFromStatusItem() {
        NSApplication.shared.terminate(nil)
    }
}
