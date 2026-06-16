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
    private let hoverActivationPadding: CGFloat = 18
    private var localMouseMonitor: Any?
    private var globalMouseMonitor: Any?
    private var overlayState: NudgeOverlayState = .normal

    private lazy var panel: NSPanel = {
        let panel = NudgeOverlayPanel(
            contentRect: NSRect(origin: .zero, size: overlayState.size),
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

        let rootView = NudgeOverlayView(state: overlayState)
            .frame(width: overlayState.size.width, height: overlayState.size.height)

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
        positionPanel(animated: false)
        panel.orderFrontRegardless()
        installMouseMonitors()
    }

    func setMousePassthroughEnabled(_ isEnabled: Bool) {
        panel.ignoresMouseEvents = isEnabled
    }

    private func positionPanel(animated: Bool) {
        guard let screen = NSScreen.main else { return }
        let frame = targetFrame(for: overlayState, on: screen)

        if animated {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.28
                context.allowsImplicitAnimation = true
                panel.animator().setFrame(frame, display: true)
            }
        } else {
            panel.setFrame(frame, display: true)
        }
    }

    @objc private func screenParametersDidChange(_ notification: Notification) {
        positionPanel(animated: false)
    }

    private func installMouseMonitors() {
        removeMouseMonitors()

        localMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved]) { [weak self] event in
            Task { @MainActor [weak self] in
                self?.updateHoverState(for: NSEvent.mouseLocation)
            }
            return event
        }

        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved]) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.updateHoverState(for: NSEvent.mouseLocation)
            }
        }
    }

    private func removeMouseMonitors() {
        if let localMouseMonitor {
            NSEvent.removeMonitor(localMouseMonitor)
            self.localMouseMonitor = nil
        }

        if let globalMouseMonitor {
            NSEvent.removeMonitor(globalMouseMonitor)
            self.globalMouseMonitor = nil
        }
    }

    private func updateHoverState(for mouseLocation: NSPoint) {
        let nextState: NudgeOverlayState = hoverFrame.contains(mouseLocation) ? .hovered : .normal
        guard nextState != overlayState else { return }

        overlayState = nextState
        panel.ignoresMouseEvents = nextState == .normal
        if nextState == .hovered {
            panel.makeKey()
        } else {
            panel.resignKey()
        }

        let rootView = NudgeOverlayView(state: nextState)
            .frame(width: nextState.size.width, height: nextState.size.height)
        panel.contentView = NSHostingView(rootView: rootView)

        positionPanel(animated: true)
    }

    private var hoverFrame: NSRect {
        switch overlayState {
        case .normal:
            panel.frame.insetBy(dx: -hoverActivationPadding, dy: -hoverActivationPadding)
        case .hovered:
            panel.frame
        }
    }

    private func targetFrame(for state: NudgeOverlayState, on screen: NSScreen) -> NSRect {
        let size = state.size

        return NSRect(
            x: screen.frame.midX - size.width / 2,
            y: screen.frame.maxY - size.height,
            width: size.width,
            height: size.height
        )
    }
}

private final class NudgeOverlayPanel: NSPanel {
    override var canBecomeKey: Bool {
        true
    }

    override var canBecomeMain: Bool {
        false
    }
}
