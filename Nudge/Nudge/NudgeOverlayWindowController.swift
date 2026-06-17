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
    private let topEdgeBleed: CGFloat = 14
    private let hoverRetentionPadding = NSSize(width: 42, height: 54)
    private let hoverStateCheckInterval: TimeInterval = 0.12
    private var pendingCollapseWorkItem: DispatchWorkItem?
    private var hoverStateCheckTimer: Timer?
    private var localMouseMonitor: Any?
    private var globalMouseMonitor: Any?
    private var cancellables = Set<AnyCancellable>()
    private var overlayState: NudgeOverlayState = .normal
    private let settingsStore: NudgeSettingsStore
    private let onOpenSettings: () -> Void
    private let overlayModel: NudgeOverlayModel

    private lazy var panel: NSPanel = {
        let initialFrame = windowFrame(for: overlayState.size)
        let panel = NudgeOverlayPanel(
            contentRect: NSRect(origin: .zero, size: initialFrame.size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        panel.backgroundColor = .clear
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = false
        panel.isMovable = false
        panel.isOpaque = false
        panel.level = .statusBar
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true

        let containerView = NudgeDragDestinationView(frame: initialFrame)
        containerView.onDragEntered = { [weak self] urls in
            Task { @MainActor [weak self] in
                self?.overlayModel.beginDragging(urls: urls)
            }
        }
        containerView.onDragUpdated = { [weak self] urls in
            Task { @MainActor [weak self] in
                self?.overlayModel.beginDragging(urls: urls)
            }
        }
        containerView.onDragExited = { [weak self] in
            Task { @MainActor [weak self] in
                self?.overlayModel.cancelDragging()
            }
        }
        containerView.onFileDropped = { [weak self] urls in
            Task { @MainActor [weak self] in
                self?.overlayModel.submitDroppedFiles(at: urls)
            }
        }
        containerView.autoresizesSubviews = true

        let rootView = NudgeOverlayView(model: overlayModel, settingsStore: settingsStore)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        let hostingView = FixedSizeHostingView(rootView: rootView)
        hostingView.frame = containerView.bounds
        hostingView.autoresizingMask = [.width, .height]
        hostingView.sizingOptions = []
        containerView.addSubview(hostingView)
        panel.contentView = containerView

        return panel
    }()

    init(settingsStore: NudgeSettingsStore, onOpenSettings: @escaping () -> Void) {
        self.settingsStore = settingsStore
        self.onOpenSettings = onOpenSettings
        self.overlayModel = NudgeOverlayModel(
            settingsStore: settingsStore,
            geminiClient: GeminiClient(settingsStore: settingsStore)
        )

        super.init()

        overlayModel.onOpenSettings = onOpenSettings
        observeOverlayStateChanges()
        observeSettingsChanges()

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
                context.duration = overlayState == .hovered || overlayState == .dragging || overlayState == .filePrompt
                    ? settingsStore.animationSpeed.expandDuration
                    : settingsStore.animationSpeed.frameDuration
                context.allowsImplicitAnimation = true
                context.timingFunction = overlayState == .hovered || overlayState == .dragging || overlayState == .filePrompt ? .nudgeExpand : .nudgeCollapse
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
        case .dragging, .filePrompt:
            pendingCollapseWorkItem?.cancel()
        case .hovered:
            if settingsStore.keepsHoverOpenWhileTyping && !overlayModel.prompt.isEmpty {
                pendingCollapseWorkItem?.cancel()
                pendingCollapseWorkItem = nil
                return
            }

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
                if settingsStore.keepsHoverOpenWhileTyping && !overlayModel.prompt.isEmpty {
                    return
                }

                if !retentionFrame.contains(NSEvent.mouseLocation) {
                    transition(to: .normal)
                }
            }
        }

        pendingCollapseWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + settingsStore.hoverCollapseDelay, execute: workItem)
    }

    private func transition(to nextState: NudgeOverlayState) {
        guard nextState != overlayState else { return }

        overlayState = nextState
        panel.ignoresMouseEvents = false
        if nextState == .hovered {
            panel.makeKey()
            startHoverStateCheckTimer()
            withAnimation(settingsStore.animationSpeed.swiftUIAnimation) {
                overlayModel.state = .hovered
            }
            positionPanel(animated: true)
        } else {
            stopHoverStateCheckTimer()
            withAnimation(settingsStore.animationSpeed.swiftUIAnimation) {
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

    private func observeSettingsChanges() {
        settingsStore.objectWillChange
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    if overlayState != .normal {
                        positionPanel(animated: false)
                    }
                }
            }
            .store(in: &cancellables)
    }

    private func syncPanel(to nextState: NudgeOverlayState) {
        guard nextState != overlayState else { return }

        overlayState = nextState
        pendingCollapseWorkItem?.cancel()
        pendingCollapseWorkItem = nil
        panel.ignoresMouseEvents = false

        if nextState == .normal {
            stopHoverStateCheckTimer()
            panel.resignKey()
        } else {
            panel.makeKey()
        }

        if nextState == .hovered {
            startHoverStateCheckTimer()
        } else {
            stopHoverStateCheckTimer()
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
        panel.frame.insetBy(dx: -settingsStore.hoverActivationPadding, dy: -settingsStore.hoverActivationPadding)
    }

    private var retentionFrame: NSRect {
        panel.frame.insetBy(dx: -hoverRetentionPadding.width, dy: -hoverRetentionPadding.height)
    }

    private func targetFrame(for state: NudgeOverlayState, on screen: NSScreen) -> NSRect {
        let windowSize = windowFrame(for: state.size).size

        return NSRect(
            x: screen.frame.midX - windowSize.width / 2,
            y: screen.frame.maxY - state.size.height,
            width: windowSize.width,
            height: windowSize.height
        )
    }

    private func windowFrame(for stateSize: CGSize) -> NSRect {
        NSRect(
            x: 0,
            y: 0,
            width: stateSize.width,
            height: stateSize.height + topEdgeBleed
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

private extension Animation {
    static var nudgeSurfaceResize: Animation {
        .timingCurve(0.25, 0.1, 0.25, 1.0, duration: 0.34)
    }
}

private final class NudgeDragDestinationView: NSView {
    var onDragEntered: (([URL]) -> Void)?
    var onDragUpdated: (([URL]) -> Void)?
    var onDragExited: (() -> Void)?
    var onFileDropped: (([URL]) -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        registerForDraggedTypes([.fileURL])
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        registerForDraggedTypes([.fileURL])
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        let fileURLs = fileURLs(from: sender.draggingPasteboard)
        guard !fileURLs.isEmpty else {
            return []
        }

        onDragEntered?(fileURLs)
        return .copy
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        let fileURLs = fileURLs(from: sender.draggingPasteboard)
        guard !fileURLs.isEmpty else {
            return []
        }

        onDragUpdated?(fileURLs)
        return .copy
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        onDragExited?()
    }

    override func draggingEnded(_ sender: NSDraggingInfo) {
        guard let destinationWindow = sender.draggingDestinationWindow else {
            onDragExited?()
            return
        }

        if !destinationWindow.frame.contains(NSEvent.mouseLocation) {
            onDragExited?()
        }
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let fileURLs = fileURLs(from: sender.draggingPasteboard)
        guard !fileURLs.isEmpty else {
            onDragExited?()
            return false
        }

        onFileDropped?(fileURLs)
        return true
    }

    private func fileURLs(from pasteboard: NSPasteboard) -> [URL] {
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL] {
            return urls
        }

        guard let fileURLString = pasteboard.string(forType: .fileURL) else {
            return []
        }

        return URL(string: fileURLString).map { [$0] } ?? []
    }
}
