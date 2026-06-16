//
//  NudgeOverlayView.swift
//  Nudge
//
//  Created by Codex on 6/16/26.
//

import SwiftUI

struct NudgeOverlayView: View {
    let state: NudgeOverlayState
    @State private var prompt = ""

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
                        .foregroundStyle(.white)
                        .padding(.horizontal, 18)
                        .frame(height: 48)
                        .background(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .fill(Color.white.opacity(0.1))
                        )
                        .onSubmit {}
                }
                .padding(.horizontal, 28)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(.spring(response: 0.34, dampingFraction: 0.78), value: state)
    }
}
