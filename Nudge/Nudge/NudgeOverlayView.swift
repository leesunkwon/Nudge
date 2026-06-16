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
        ZStack(alignment: .top) {
            NudgeUnifiedSurfaceShape(cornerRadius: state == .normal ? 20 : 26)
                .fill(Color.black.opacity(0.95))
                .overlay {
                    NudgeUnifiedSurfaceShape(cornerRadius: state == .normal ? 20 : 26)
                        .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
                }

            if state == .hovered {
                VStack(spacing: 0) {
                    Spacer()
                        .frame(height: 46)

                    TextField("Ask Gemini anything...", text: $prompt)
                        .textFieldStyle(.plain)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.92))
                        .tint(Color(red: 0.46, green: 0.78, blue: 1.0))
                        .padding(.horizontal, 16)
                        .frame(height: 38)
                        .background(inputBackground)
                        .onSubmit {}
                }
                .padding(.horizontal, 18)
                .transition(.opacity)
            }
        }
        .animation(.interactiveSpring(response: 0.42, dampingFraction: 0.9, blendDuration: 0.08), value: state)
    }

    private var inputBackground: some View {
        RoundedRectangle(cornerRadius: 15, style: .continuous)
            .fill(Color.white.opacity(0.12))
            .overlay {
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
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
