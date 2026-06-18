//
//  NudgeThemePalette.swift
//  Nudge
//
//  Created by Codex on 6/18/26.
//

import SwiftUI

struct NudgeThemePalette {
    let surfaceColor: Color
    let surfaceOpacity: Double
    let topMaskOpacity: Double
    let strokeColor: Color
    let strokeOpacity: Double
    let inputFillOpacity: Double
    let buttonFillOpacity: Double
    let progressTrackOpacity: Double
    let glowColors: [Color]
    let subtleGlowColors: [Color]
    let settingsBackgroundColors: [Color]

    var glowGradient: LinearGradient {
        LinearGradient(colors: glowColors, startPoint: .leading, endPoint: .trailing)
    }

    var progressGradient: LinearGradient {
        LinearGradient(colors: glowColors, startPoint: .leading, endPoint: .trailing)
    }

    var subtleGlowGradient: LinearGradient {
        LinearGradient(colors: subtleGlowColors, startPoint: .leading, endPoint: .trailing)
    }

    var settingsBackgroundGradient: LinearGradient {
        LinearGradient(colors: settingsBackgroundColors, startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

extension NudgeSettingsStore.NotchTheme {
    var palette: NudgeThemePalette {
        switch self {
        case .nudgeDefault:
            NudgeThemePalette(
                surfaceColor: .black,
                surfaceOpacity: 0.95,
                topMaskOpacity: 0.95,
                strokeColor: .white,
                strokeOpacity: 0.08,
                inputFillOpacity: 0.12,
                buttonFillOpacity: 0.10,
                progressTrackOpacity: 0.10,
                glowColors: [
                    Color(red: 0.25, green: 0.73, blue: 1.0),
                    Color(red: 0.57, green: 0.45, blue: 1.0),
                    Color(red: 1.0, green: 0.42, blue: 0.78),
                    Color(red: 1.0, green: 0.64, blue: 0.36)
                ],
                subtleGlowColors: [
                    Color(red: 0.35, green: 0.78, blue: 1.0),
                    Color(red: 0.95, green: 0.48, blue: 0.94),
                    Color(red: 1.0, green: 0.74, blue: 0.36)
                ],
                settingsBackgroundColors: [
                    .black,
                    Color(red: 0.05, green: 0.04, blue: 0.08),
                    Color(red: 0.02, green: 0.02, blue: 0.03)
                ]
            )
        case .geminiGlow:
            NudgeThemePalette(
                surfaceColor: Color(red: 0.015, green: 0.015, blue: 0.035),
                surfaceOpacity: 0.96,
                topMaskOpacity: 0.96,
                strokeColor: Color(red: 0.64, green: 0.72, blue: 1.0),
                strokeOpacity: 0.12,
                inputFillOpacity: 0.14,
                buttonFillOpacity: 0.12,
                progressTrackOpacity: 0.11,
                glowColors: [
                    Color(red: 0.12, green: 0.58, blue: 1.0),
                    Color(red: 0.38, green: 0.42, blue: 1.0),
                    Color(red: 0.78, green: 0.28, blue: 1.0),
                    Color(red: 1.0, green: 0.28, blue: 0.68)
                ],
                subtleGlowColors: [
                    Color(red: 0.20, green: 0.70, blue: 1.0),
                    Color(red: 0.62, green: 0.36, blue: 1.0),
                    Color(red: 1.0, green: 0.34, blue: 0.76)
                ],
                settingsBackgroundColors: [
                    Color(red: 0.01, green: 0.01, blue: 0.03),
                    Color(red: 0.035, green: 0.025, blue: 0.10),
                    Color(red: 0.055, green: 0.01, blue: 0.08)
                ]
            )
        case .mono:
            NudgeThemePalette(
                surfaceColor: Color(red: 0.025, green: 0.025, blue: 0.026),
                surfaceOpacity: 0.96,
                topMaskOpacity: 0.96,
                strokeColor: .white,
                strokeOpacity: 0.10,
                inputFillOpacity: 0.10,
                buttonFillOpacity: 0.09,
                progressTrackOpacity: 0.10,
                glowColors: [
                    Color.white.opacity(0.92),
                    Color(red: 0.72, green: 0.74, blue: 0.78),
                    Color.white.opacity(0.82)
                ],
                subtleGlowColors: [
                    Color.white.opacity(0.70),
                    Color(red: 0.58, green: 0.60, blue: 0.64),
                    Color.white.opacity(0.62)
                ],
                settingsBackgroundColors: [
                    .black,
                    Color(red: 0.035, green: 0.035, blue: 0.038),
                    Color(red: 0.012, green: 0.012, blue: 0.014)
                ]
            )
        case .glass:
            NudgeThemePalette(
                surfaceColor: Color(red: 0.035, green: 0.045, blue: 0.060),
                surfaceOpacity: 0.72,
                topMaskOpacity: 0.80,
                strokeColor: Color(red: 0.86, green: 0.93, blue: 1.0),
                strokeOpacity: 0.18,
                inputFillOpacity: 0.16,
                buttonFillOpacity: 0.14,
                progressTrackOpacity: 0.13,
                glowColors: [
                    Color(red: 0.58, green: 0.86, blue: 1.0),
                    Color(red: 0.72, green: 0.64, blue: 1.0),
                    Color(red: 1.0, green: 0.66, blue: 0.92)
                ],
                subtleGlowColors: [
                    Color(red: 0.70, green: 0.90, blue: 1.0),
                    Color(red: 0.82, green: 0.72, blue: 1.0),
                    Color(red: 1.0, green: 0.72, blue: 0.90)
                ],
                settingsBackgroundColors: [
                    Color(red: 0.015, green: 0.020, blue: 0.028),
                    Color(red: 0.035, green: 0.052, blue: 0.070),
                    Color(red: 0.010, green: 0.012, blue: 0.018)
                ]
            )
        }
    }
}
