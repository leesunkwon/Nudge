//
//  NudgeOverlayView.swift
//  Nudge
//
//  Created by Codex on 6/16/26.
//

import SwiftUI

struct NudgeOverlayView: View {
    @ObservedObject var model: NudgeOverlayModel
    @ObservedObject var settingsStore: NudgeSettingsStore
    @State private var isInputVisible = false

    private var state: NudgeOverlayState {
        model.state
    }

    private var isShowingLoadingGlow: Bool {
        state == .loading || (state == .result && model.isLoading)
    }

    var body: some View {
        ZStack(alignment: .top) {
            NudgeUnifiedSurfaceShape(cornerRadius: state == .normal ? 21 : 30)
                .fill(Color.black.opacity(0.95))
                .overlay {
                    ZStack {
                        NudgeUnifiedSurfaceShape(cornerRadius: state == .normal ? 21 : 30)
                            .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)

                        if state == .dragging {
                            NudgeUnifiedSurfaceShape(cornerRadius: 30)
                                .strokeBorder(
                                    appleIntelligenceGradient,
                                    style: StrokeStyle(lineWidth: 1.4, dash: [8, 8])
                                )
                                .opacity(0.82)
                                .padding(8)
                        }

                        if isShowingLoadingGlow {
                            NudgeBreathingGlowView(
                                shape: NudgeUnifiedSurfaceShape(cornerRadius: state == .loading ? 30 : 32),
                                intensity: (state == .loading ? 0.34 : 0.38) * settingsStore.glowIntensity.multiplier
                            )
                            .padding(state == .loading ? 3 : 0)
                            .allowsHitTesting(false)
                        }
                    }
                }

            Rectangle()
                .fill(Color.black.opacity(0.95))
                .frame(height: 32)
                .allowsHitTesting(false)

            if isShowingLoadingGlow {
                NudgeTopBreathingGlowStrip()
                    .frame(height: 32)
                    .opacity(settingsStore.glowIntensity.multiplier)
                    .allowsHitTesting(false)
            }

            switch state {
            case .dragging:
                draggingView
            case .filePrompt:
                filePromptView
            case .hovered:
                promptInputView
            case .loading:
                loadingView
            case .result:
                resultView
            case .normal:
                EmptyView()
            }
        }
        .animation(settingsStore.animationSpeed.swiftUIAnimation, value: state)
        .onChange(of: state) { _, newState in
            updateInputVisibility(for: newState)
        }
    }

    private func updateInputVisibility(for state: NudgeOverlayState) {
        switch state {
        case .normal, .dragging, .filePrompt, .loading, .result:
            isInputVisible = false
        case .hovered:
            isInputVisible = false
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) {
                guard self.state == .hovered else { return }
                withAnimation(.easeOut(duration: 0.16)) {
                    isInputVisible = true
                }
            }
        }
    }

    private var promptInputView: some View {
        VStack(spacing: 0) {
            Spacer()
                .frame(height: 64)

            gradientPromptField(
                placeholder: "무엇이든 물어보세요...",
                fontSize: 17,
                isDisabled: false
            )
        }
        .padding(.horizontal, 30)
        .opacity(isInputVisible ? 1 : 0)
        .transition(.opacity)
    }

    private var draggingView: some View {
        VStack(spacing: 0) {
            Spacer()
                .frame(height: 64)

            HStack(spacing: 10) {
                Image(systemName: model.dragPromptIconName)
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(appleIntelligenceGradient)

                Text(model.dragPromptText)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.86))
            }
            .padding(.horizontal, 20)
            .frame(height: 46)
            .frame(maxWidth: .infinity)
            .background(inputBackground)
        }
        .padding(.horizontal, 30)
        .transition(.opacity)
    }

    private var filePromptView: some View {
        VStack(spacing: 0) {
            Spacer()
                .frame(height: 60)

            HStack(spacing: 12) {
                filePreviewTile

                VStack(alignment: .leading, spacing: 5) {
                    Text(model.droppedFileDisplayName)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.9))
                        .lineLimit(1)
                        .truncationMode(.middle)

                    HStack(spacing: 6) {
                        Text(model.droppedFileKindLabel)
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(appleIntelligenceGradient)

                        Circle()
                            .fill(Color.white.opacity(0.25))
                            .frame(width: 3, height: 3)

                        Text(model.droppedFileSizeText)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Color.white.opacity(0.52))
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 4)
            .frame(height: 48)

            HStack(spacing: 12) {
                gradientPromptField(
                    placeholder: "\(model.droppedFileDisplayName)에게 물어보기...",
                    fontSize: 16,
                    isDisabled: false
                )
                .frame(maxWidth: .infinity)

                Button {
                    model.cancelFilePrompt()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .bold))
                        .frame(width: 32, height: 46)
                        .background {
                            Circle()
                                .fill(Color.white.opacity(0.13))
                                .overlay {
                                    Circle()
                                        .strokeBorder(Color.white.opacity(0.14), lineWidth: 1)
                                }
                        }
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.white.opacity(0.84))
                .help("Cancel")
                .fixedSize()
            }
            .padding(.top, 12)
        }
        .padding(.horizontal, 30)
        .transition(.opacity)
    }

    private var filePreviewTile: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.white.opacity(0.10))
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
                }

            if let thumbnail = model.droppedFilePreviewThumbnail {
                Image(nsImage: thumbnail)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 48, height: 48)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            } else {
                Image(systemName: model.droppedFilePreviewIconName)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(appleIntelligenceGradient)
            }
        }
        .frame(width: 48, height: 48)
        .clipped()
    }

    private var loadingView: some View {
        VStack(spacing: 0) {
            Spacer()
                .frame(height: 64)

            NudgeBreathingGlowCapsule(intensity: settingsStore.glowIntensity.multiplier)
            .frame(height: 46)
        }
        .padding(.horizontal, 30)
        .transition(.opacity)
    }

    private var resultView: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(model.responseProviderTitle)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.9))

                    Text(model.submittedPrompt)
                        .font(.system(size: 12, weight: .medium))
                        .lineLimit(1)
                        .foregroundStyle(Color.white.opacity(0.48))
                }

                Spacer()

                HStack(spacing: 8) {
                    resultActionsMenu

                    headerIconButton(systemName: "doc.on.doc") {
                        model.copyResponseToPasteboard()
                    }
                    .help("Copy")

                    headerIconButton(systemName: "xmark") {
                        model.closeResult()
                    }
                    .help("Close")
                }
                .fixedSize()
            }

            ScrollView {
                if model.isLoading {
                    resultLoadingView
                } else if let errorMessage = model.errorMessage {
                    Text(errorMessage)
                        .font(.system(size: 14, weight: .regular))
                        .lineSpacing(4)
                        .textSelection(.enabled)
                        .foregroundStyle(Color(red: 1.0, green: 0.56, blue: 0.56))
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    NudgeMarkdownText(markdown: model.displayedResponseText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .scrollIndicators(.hidden)

            followUpInputView
        }
        .padding(.horizontal, 30)
        .padding(.top, 28)
        .padding(.bottom, 24)
        .transition(.opacity)
    }

    private var resultLoadingView: some View {
        Color.clear
            .frame(maxWidth: .infinity, minHeight: 240)
    }

    private var followUpInputView: some View {
        gradientPromptField(
            placeholder: model.isLoading ? "" : "이어서 물어보세요...",
            fontSize: 15,
            isDisabled: model.isLoading
        )
        .opacity(model.isLoading ? 0.62 : 1)
    }

    private var resultActionsMenu: some View {
        Menu {
            Button("텍스트 파일로 저장") {
                model.saveResponseAsTextFile()
            }

            Button("공유") {
                model.shareResponse()
            }

            Button("원본 파일 열기") {
                model.openDroppedFile()
            }
            .disabled(!model.canOpenDroppedFile)

            Divider()

            Button("설정") {
                model.openSettings()
            }

            Button("다시 생성") {
                model.regenerateLastResponse()
            }
            .disabled(model.isLoading)
        } label: {
            headerIconLabel(systemName: "ellipsis")
        }
        .buttonStyle(.plain)
        .fixedSize()
        .help("More")
    }

    private func headerIconButton(
        systemName: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            headerIconLabel(systemName: systemName)
        }
        .buttonStyle(.plain)
    }

    private func headerIconLabel(systemName: String) -> some View {
        Image(systemName: systemName)
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(Color.white.opacity(0.86))
            .frame(width: 30, height: 30)
            .background {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.white.opacity(0.10))
                    .overlay {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
                    }
            }
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var inputBackground: some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(Color.white.opacity(0.12))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
            }
    }

    private func gradientPromptField(
        placeholder: String,
        fontSize: CGFloat,
        isDisabled: Bool
    ) -> some View {
        ZStack(alignment: .leading) {
            if model.prompt.isEmpty {
                Text(placeholder)
                    .font(.system(size: fontSize, weight: .medium))
                    .foregroundStyle(appleIntelligenceGradient)
                    .lineLimit(1)
                    .allowsHitTesting(false)
            }

            TextField("", text: $model.prompt)
                .textFieldStyle(.plain)
                .font(.system(size: fontSize, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.92))
                .tint(Color(red: 0.46, green: 0.78, blue: 1.0))
                .disabled(isDisabled)
                .onSubmit {
                    if state == .filePrompt {
                        model.submitFilePrompt()
                    } else {
                        model.submitPrompt()
                    }
                }
        }
        .padding(.horizontal, 18)
        .frame(height: 46)
        .background(inputBackground)
    }

    private var appleIntelligenceGradient: LinearGradient {
        LinearGradient(
            colors: [
                Color(red: 0.25, green: 0.73, blue: 1.0),
                Color(red: 0.57, green: 0.45, blue: 1.0),
                Color(red: 1.0, green: 0.42, blue: 0.78),
                Color(red: 1.0, green: 0.64, blue: 0.36)
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
    }
}

private struct NudgeUnifiedSurfaceShape: InsettableShape {
    var cornerRadius: CGFloat
    var insetAmount: CGFloat = 0

    var animatableData: CGFloat {
        get { cornerRadius }
        set { cornerRadius = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let insetRect = rect.insetBy(dx: insetAmount, dy: insetAmount)
        let radius = min(cornerRadius, insetRect.width / 2, insetRect.height)
        let minX = insetRect.minX
        let maxX = insetRect.maxX
        let minY = insetRect.minY
        let maxY = insetRect.maxY

        var path = Path()
        path.move(to: CGPoint(x: minX, y: minY))
        path.addLine(to: CGPoint(x: maxX, y: minY))
        path.addLine(to: CGPoint(x: maxX, y: maxY - radius))
        path.addQuadCurve(
            to: CGPoint(x: maxX - radius, y: maxY),
            control: CGPoint(x: maxX, y: maxY)
        )
        path.addLine(to: CGPoint(x: minX + radius, y: maxY))
        path.addQuadCurve(
            to: CGPoint(x: minX, y: maxY - radius),
            control: CGPoint(x: minX, y: maxY)
        )
        path.addLine(to: CGPoint(x: minX, y: minY))
        path.closeSubpath()

        return path
    }

    func inset(by amount: CGFloat) -> some InsettableShape {
        var shape = self
        shape.insetAmount += amount
        return shape
    }
}

private struct NudgeBreathingGlowView<GlowShape: InsettableShape>: View {
    let shape: GlowShape
    let intensity: Double

    var body: some View {
        TimelineView(.animation) { context in
            let phase = context.date.timeIntervalSinceReferenceDate
            let breath = (sin(phase * 1.45) + 1) / 2
            let drift = (sin(phase * 0.72) + 1) / 2

            shape
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.25, green: 0.74, blue: 1.0).opacity(0.25 + breath * 0.18),
                            Color(red: 0.62, green: 0.45, blue: 1.0).opacity(0.30 + breath * 0.20),
                            Color(red: 1.0, green: 0.40, blue: 0.80).opacity(0.22 + breath * 0.18),
                            Color(red: 1.0, green: 0.65, blue: 0.34).opacity(0.18 + breath * 0.14)
                        ],
                        startPoint: UnitPoint(x: -0.20 + drift * 0.34, y: 0.05),
                        endPoint: UnitPoint(x: 0.86 + drift * 0.30, y: 1.0)
                    )
                )
                .scaleEffect(1.0 + breath * 0.018)
                .blur(radius: 18 + breath * 7)
                .opacity(intensity)
                .blendMode(.screen)
                .overlay {
                    shape
                        .strokeBorder(
                            LinearGradient(
                                colors: [
                                    Color(red: 0.35, green: 0.78, blue: 1.0).opacity(0.20 + breath * 0.28),
                                    Color(red: 0.95, green: 0.48, blue: 0.94).opacity(0.28 + breath * 0.22),
                                    Color(red: 1.0, green: 0.74, blue: 0.36).opacity(0.16 + breath * 0.18)
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            ),
                            lineWidth: 1.1 + breath * 0.6
                        )
                        .opacity(0.54)
                        .blendMode(.screen)
                }
        }
    }
}

private struct NudgeBreathingGlowCapsule: View {
    let intensity: Double

    var body: some View {
        TimelineView(.animation) { context in
            let phase = context.date.timeIntervalSinceReferenceDate
            let breath = (sin(phase * 1.75) + 1) / 2
            let drift = (sin(phase * 0.95) + 1) / 2

            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white.opacity(0.08 + breath * 0.03))
                .overlay {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color(red: 0.23, green: 0.76, blue: 1.0).opacity(0.20),
                                    Color(red: 0.62, green: 0.45, blue: 1.0).opacity(0.28 + breath * 0.14),
                                    Color(red: 1.0, green: 0.42, blue: 0.80).opacity(0.22 + breath * 0.12),
                                    Color(red: 1.0, green: 0.68, blue: 0.34).opacity(0.18)
                                ],
                                startPoint: UnitPoint(x: -0.25 + drift * 0.44, y: 0.5),
                                endPoint: UnitPoint(x: 0.84 + drift * 0.36, y: 0.5)
                            )
                        )
                        .blur(radius: 13 + breath * 3)
                        .blendMode(.screen)
                        .padding(.horizontal, 14)
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.12 + breath * 0.10), lineWidth: 1)
                }
                .scaleEffect(x: 0.985 + breath * 0.015, y: 0.96 + breath * 0.04)
                .opacity(intensity)
                .animation(nil, value: breath)
        }
    }
}

private struct NudgeTopBreathingGlowStrip: View {
    var body: some View {
        TimelineView(.animation) { context in
            let phase = context.date.timeIntervalSinceReferenceDate
            let breath = (sin(phase * 1.45) + 1) / 2
            let drift = (sin(phase * 0.72) + 1) / 2

            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.25, green: 0.74, blue: 1.0).opacity(0.16 + breath * 0.10),
                            Color(red: 0.62, green: 0.45, blue: 1.0).opacity(0.18 + breath * 0.13),
                            Color(red: 1.0, green: 0.40, blue: 0.80).opacity(0.14 + breath * 0.10),
                            Color(red: 1.0, green: 0.65, blue: 0.34).opacity(0.12 + breath * 0.08)
                        ],
                        startPoint: UnitPoint(x: -0.16 + drift * 0.30, y: 0.5),
                        endPoint: UnitPoint(x: 0.88 + drift * 0.28, y: 0.5)
                    )
                )
                .blur(radius: 18 + breath * 5)
                .opacity(0.82)
                .blendMode(.screen)
                .clipped()
        }
    }
}
