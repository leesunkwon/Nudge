//
//  NudgeOverlayView.swift
//  Nudge
//
//  Created by Codex on 6/16/26.
//

import SwiftUI

struct NudgeOverlayView: View {
    @ObservedObject var model: NudgeOverlayModel
    @State private var prompt = ""

    private var state: NudgeOverlayState {
        model.state
    }

    var body: some View {
        ZStack {
            overlaySurface

            if state == .hovered {
                VStack(spacing: 0) {
                    Spacer(minLength: 74)

                    TextField("Ask Gemini anything...", text: $prompt)
                        .textFieldStyle(.plain)
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.94))
                        .tint(Color(red: 0.46, green: 0.78, blue: 1.0))
                        .padding(.horizontal, 22)
                        .frame(height: 58)
                        .background(inputBackground)
                        .onSubmit {}

                    Spacer(minLength: 36)
                }
                .padding(.horizontal, 42)
                .transition(
                    .asymmetric(
                        insertion: .opacity
                            .combined(with: .scale(scale: 0.94, anchor: .top)),
                        removal: .opacity
                            .combined(with: .scale(scale: 0.98, anchor: .top))
                    )
                )
            }
        }
        .animation(.interactiveSpring(response: 0.5, dampingFraction: 0.86, blendDuration: 0.12), value: state)
    }

    @ViewBuilder
    private var overlaySurface: some View {
        if state == .normal {
            NudgeUnifiedSurfaceShape(cornerRadius: 20)
                .fill(Color.black.opacity(0.94))
                .overlay {
                    NudgeUnifiedSurfaceShape(cornerRadius: 20)
                        .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
                }
        } else {
            NudgeUnifiedSurfaceShape(cornerRadius: 46)
                .fill(Color.black.opacity(0.96))
                .overlay {
                    NudgeUnifiedSurfaceShape(cornerRadius: 46)
                        .strokeBorder(Color.white.opacity(0.06), lineWidth: 1)
                }
                .overlay(alignment: .bottom) {
                    LinearGradient(
                        colors: [
                            Color.clear,
                            Color(red: 0.4, green: 0.72, blue: 1.0).opacity(0.14)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 72)
                    .clipShape(NudgeUnifiedSurfaceShape(cornerRadius: 46))
                }
        }
    }

    private var inputBackground: some View {
        RoundedRectangle(cornerRadius: 20, style: .continuous)
            .fill(Color.white.opacity(0.12))
            .overlay {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.2), lineWidth: 1)
            }
            .overlay(alignment: .bottom) {
                Capsule(style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.45, green: 0.76, blue: 1.0).opacity(0.8),
                                Color(red: 0.68, green: 0.54, blue: 1.0).opacity(0.7)
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(height: 2)
                    .padding(.horizontal, 18)
                    .padding(.bottom, 1)
            }
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
