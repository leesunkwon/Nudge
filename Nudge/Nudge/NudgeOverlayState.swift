//
//  NudgeOverlayState.swift
//  Nudge
//
//  Created by Codex on 6/16/26.
//

import Foundation

enum NudgeOverlayState {
    case normal
    case hovered

    var size: CGSize {
        switch self {
        case .normal:
            CGSize(width: 280, height: 42)
        case .hovered:
            CGSize(width: 380, height: 104)
        }
    }
}
