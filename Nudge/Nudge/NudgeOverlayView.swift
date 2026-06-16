//
//  NudgeOverlayView.swift
//  Nudge
//
//  Created by Codex on 6/16/26.
//

import SwiftUI

struct NudgeOverlayView: View {
    @ObservedObject var model: NudgeOverlayModel
    @State private var isInputVisible = false

    private var state: NudgeOverlayState {
        model.state
    }

    var body: some View {
        ZStack(alignment: .top) {
            NudgeUnifiedSurfaceShape(cornerRadius: state == .normal ? 20 : 26)
                .fill(Color.black.opacity(0.95))
                .overlay {
                    NudgeUnifiedSurfaceShape(cornerRadius: state == .normal ? 20 : 26)
                        .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
                }

            switch state {
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
        .animation(.interactiveSpring(response: 0.42, dampingFraction: 0.9, blendDuration: 0.08), value: state)
        .onChange(of: state) { _, newState in
            updateInputVisibility(for: newState)
        }
    }

    private func updateInputVisibility(for state: NudgeOverlayState) {
        switch state {
        case .normal, .loading, .result:
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
                .frame(height: 46)

            gradientPromptField(
                placeholder: "무엇이든 물어보세요...",
                fontSize: 15,
                isDisabled: false
            )
        }
        .padding(.horizontal, 18)
        .opacity(isInputVisible ? 1 : 0)
        .transition(.opacity)
    }

    private var loadingView: some View {
        VStack(spacing: 0) {
            Spacer()
                .frame(height: 46)

            HStack(spacing: 10) {
                ProgressView()
                    .controlSize(.small)
                    .tint(Color.white.opacity(0.9))

                Text("Thinking")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.8))

                Spacer()
            }
            .padding(.horizontal, 16)
            .frame(height: 38)
            .background(inputBackground)
        }
        .padding(.horizontal, 18)
        .transition(.opacity)
    }

    private var resultView: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Gemini")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.9))

                    Text(model.submittedPrompt)
                        .font(.system(size: 11, weight: .medium))
                        .lineLimit(1)
                        .foregroundStyle(Color.white.opacity(0.48))
                }

                Spacer()

                Button {
                    model.copyResponseToPasteboard()
                } label: {
                    Image(systemName: "doc.on.doc")
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.white.opacity(0.7))
                .help("Copy")

                Button {
                    model.closeResult()
                } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.white.opacity(0.7))
                .help("Close")
            }

            ScrollView {
                if model.isLoading {
                    resultLoadingView
                } else {
                    Text(resultMessage)
                        .font(.system(size: 14, weight: .regular))
                        .lineSpacing(4)
                        .textSelection(.enabled)
                        .foregroundStyle(resultTextColor)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .scrollIndicators(.hidden)

            followUpInputView
        }
        .padding(.horizontal, 22)
        .padding(.top, 22)
        .padding(.bottom, 18)
        .transition(.opacity)
    }

    private var resultLoadingView: some View {
        HStack(spacing: 10) {
            ProgressView()
                .controlSize(.small)
                .tint(Color.white.opacity(0.9))

            Text("Thinking")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.78))

            Spacer()
        }
        .frame(maxWidth: .infinity, minHeight: 120, alignment: .center)
    }

    private var followUpInputView: some View {
        gradientPromptField(
            placeholder: model.isLoading ? "Gemini가 생각하는 중..." : "이어서 물어보세요...",
            fontSize: 14,
            isDisabled: model.isLoading
        )
        .opacity(model.isLoading ? 0.62 : 1)
    }

    private var resultMessage: String {
        model.errorMessage ?? model.responseText
    }

    private var resultTextColor: Color {
        model.errorMessage == nil ? Color.white.opacity(0.88) : Color(red: 1.0, green: 0.56, blue: 0.56)
    }

    private var inputBackground: some View {
        RoundedRectangle(cornerRadius: 15, style: .continuous)
            .fill(Color.white.opacity(0.12))
            .overlay {
                RoundedRectangle(cornerRadius: 15, style: .continuous)
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
                    model.submitPrompt()
                }
        }
        .padding(.horizontal, 16)
        .frame(height: 38)
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
