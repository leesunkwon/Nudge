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
            RoundedRectangle(cornerRadius: state == .normal ? 21 : 34, style: .continuous)
                .fill(Color.black.opacity(0.92))
                .overlay {
                    RoundedRectangle(cornerRadius: state == .normal ? 21 : 34, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
                }

            if state == .hovered {
                VStack(spacing: 12) {
                    TextField("Ask Gemini anything...", text: $prompt)
                        .textFieldStyle(.plain)
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.94))
                        .tint(Color(red: 0.46, green: 0.78, blue: 1.0))
                        .padding(.horizontal, 20)
                        .frame(height: 54)
                        .background(inputBackground)
                        .onSubmit {}
                }
                .padding(.horizontal, 28)
                .transition(
                    .asymmetric(
                        insertion: .opacity
                            .combined(with: .scale(scale: 0.94, anchor: .top))
                            .combined(with: .move(edge: .top)),
                        removal: .opacity
                            .combined(with: .scale(scale: 0.98, anchor: .top))
                    )
                )
            }
        }
        .animation(.interactiveSpring(response: 0.5, dampingFraction: 0.86, blendDuration: 0.12), value: state)
    }

    private var inputBackground: some View {
        RoundedRectangle(cornerRadius: 20, style: .continuous)
            .fill(Color.white.opacity(0.18))
            .overlay {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.28), lineWidth: 1)
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
