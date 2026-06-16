//
//  NudgeOverlayWindowController.swift
//  Nudge
//
//  Created by Codex on 6/16/26.
//

import AppKit
import SwiftUI

@MainActor
final class NudgeOverlayWindowController: NSObject {
    private let normalSize = NSSize(width: 280, height: 42)

    private lazy var panel: NSPanel = {
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: normalSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        panel.backgroundColor = .clear
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = true
        panel.isMovable = false
        panel.isOpaque = false
        panel.level = .statusBar
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true

        let rootView = NudgeOverlayView()
            .frame(width: normalSize.width, height: normalSize.height)

        panel.contentView = NSHostingView(rootView: rootView)

        return panel
    }()

    override init() {
        super.init()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenParametersDidChange),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    func showOverlay() {
        positionPanel()
        panel.orderFrontRegardless()
    }

    func setMousePassthroughEnabled(_ isEnabled: Bool) {
        panel.ignoresMouseEvents = isEnabled
    }

    private func positionPanel() {
        guard let screen = NSScreen.main else { return }

        panel.setFrame(
            NSRect(
                x: screen.frame.midX - normalSize.width / 2,
                y: screen.frame.maxY - normalSize.height,
                width: normalSize.width,
                height: normalSize.height
            ),
            display: true
        )
    }

    @objc private func screenParametersDidChange(_ notification: Notification) {
        positionPanel()
    }
}
