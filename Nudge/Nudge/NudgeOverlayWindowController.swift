//
//  NudgeOverlayWindowController.swift
//  Nudge
//
//  Created by Codex on 6/16/26.
//

import AppKit
import Combine
import SwiftUI

@MainActor
final class NudgeOverlayWindowController: NSObject {
    private let hoverActivationPadding: CGFloat = 18
    private let hoverRetentionPadding = NSSize(width: 42, height: 54)
    private let hoverCollapseDelay: TimeInterval = 0.45
    private let hoverContentRevealDelay: TimeInterval = 0.08
    private let hoverStateCheckInterval: TimeInterval = 0.12
    private let frameAnimationDuration: TimeInterval = 0.36
    private var pendingCollapseWorkItem: DispatchWorkItem?
    private var hoverStateCheckTimer: Timer?
    private var localMouseMonitor: Any?
    private var globalMouseMonitor: Any?
    private var cancellables = Set<AnyCancellable>()
    private var overlayState: NudgeOverlayState = .normal
    private let overlayModel = NudgeOverlayModel()

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

        let containerView = NSView(frame: NSRect(origin: .zero, size: overlayState.size))
        containerView.autoresizesSubviews = true

        let rootView = NudgeOverlayView(model: overlayModel)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        let hostingView = FixedSizeHostingView(rootView: rootView)
        hostingView.frame = containerView.bounds
        hostingView.autoresizingMask = [.width, .height]
        hostingView.sizingOptions = []
        containerView.addSubview(hostingView)
        panel.contentView = containerView

        return panel
    }()

    override init() {
        super.init()

        observeOverlayStateChanges()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenParametersDidChange),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
    }

    deinit {
        hoverStateCheckTimer?.invalidate()
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
                context.duration = overlayState == .hovered ? 0.46 : frameAnimationDuration
                context.allowsImplicitAnimation = true
                context.timingFunction = overlayState == .hovered ? .nudgeExpand : .nudgeCollapse
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
        switch overlayState {
        case .normal:
            guard activationFrame.contains(mouseLocation) else { return }
            pendingCollapseWorkItem?.cancel()
            transition(to: .hovered)
        case .hovered:
            if retentionFrame.contains(mouseLocation) {
                pendingCollapseWorkItem?.cancel()
                pendingCollapseWorkItem = nil
            } else {
                scheduleHoverCollapse()
            }
        case .loading, .result:
            pendingCollapseWorkItem?.cancel()
        }
    }

    private func scheduleHoverCollapse() {
        guard pendingCollapseWorkItem == nil else { return }

        let workItem = DispatchWorkItem { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                pendingCollapseWorkItem = nil
                if !retentionFrame.contains(NSEvent.mouseLocation) {
                    transition(to: .normal)
                }
            }
        }

        pendingCollapseWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + hoverCollapseDelay, execute: workItem)
    }

    private func transition(to nextState: NudgeOverlayState) {
        guard nextState != overlayState else { return }

        overlayState = nextState
        panel.ignoresMouseEvents = nextState == .normal
        if nextState == .hovered {
            panel.makeKey()
            startHoverStateCheckTimer()
            positionPanel(animated: true)
            DispatchQueue.main.asyncAfter(deadline: .now() + hoverContentRevealDelay) { [weak self] in
                Task { @MainActor [weak self] in
                    guard let self, overlayState == .hovered else { return }
                    withAnimation(.interactiveSpring(response: 0.42, dampingFraction: 0.9, blendDuration: 0.08)) {
                        self.overlayModel.state = .hovered
                    }
                }
            }
        } else {
            stopHoverStateCheckTimer()
            withAnimation(.interactiveSpring(response: 0.42, dampingFraction: 0.9, blendDuration: 0.08)) {
                overlayModel.state = nextState
            }
            panel.resignKey()
            positionPanel(animated: true)
        }
    }

    private func observeOverlayStateChanges() {
        overlayModel.$state
            .sink { [weak self] nextState in
                Task { @MainActor [weak self] in
                    self?.syncPanel(to: nextState)
                }
            }
            .store(in: &cancellables)
    }

    private func syncPanel(to nextState: NudgeOverlayState) {
        guard nextState != overlayState else { return }

        overlayState = nextState
        pendingCollapseWorkItem?.cancel()
        pendingCollapseWorkItem = nil
        panel.ignoresMouseEvents = nextState == .normal

        if nextState == .normal {
            stopHoverStateCheckTimer()
            panel.resignKey()
        } else {
            panel.makeKey()
        }

        if nextState == .hovered {
            startHoverStateCheckTimer()
        }

        positionPanel(animated: true)
    }

    private func startHoverStateCheckTimer() {
        guard hoverStateCheckTimer == nil else { return }

        let timer = Timer(timeInterval: hoverStateCheckInterval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, overlayState == .hovered else { return }
                updateHoverState(for: NSEvent.mouseLocation)
            }
        }

        RunLoop.main.add(timer, forMode: .common)
        hoverStateCheckTimer = timer
    }

    private func stopHoverStateCheckTimer() {
        hoverStateCheckTimer?.invalidate()
        hoverStateCheckTimer = nil
    }

    private var activationFrame: NSRect {
        panel.frame.insetBy(dx: -hoverActivationPadding, dy: -hoverActivationPadding)
    }

    private var retentionFrame: NSRect {
        panel.frame.insetBy(dx: -hoverRetentionPadding.width, dy: -hoverRetentionPadding.height)
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

private final class FixedSizeHostingView<Content: View>: NSHostingView<Content> {
    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: NSView.noIntrinsicMetric)
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        invalidateIntrinsicContentSize()
    }
}

private extension CAMediaTimingFunction {
    static var nudgeExpand: CAMediaTimingFunction {
        CAMediaTimingFunction(controlPoints: 0.25, 0.1, 0.25, 1.0)
    }

    static var nudgeCollapse: CAMediaTimingFunction {
        CAMediaTimingFunction(controlPoints: 0.33, 0.0, 0.2, 1.0)
    }
}
