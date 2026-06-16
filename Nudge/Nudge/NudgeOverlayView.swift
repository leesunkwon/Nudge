//
//  NudgeOverlayView.swift
//  Nudge
//
//  Created by Codex on 6/16/26.
//

import SwiftUI

struct NudgeOverlayView: View {
    var body: some View {
        Capsule(style: .continuous)
            .fill(Color.black.opacity(0.92))
            .overlay {
                Capsule(style: .continuous)
                    .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
            }
            .accessibilityHidden(true)
    }
}
