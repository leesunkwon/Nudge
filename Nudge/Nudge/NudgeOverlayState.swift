//
//  NudgeOverlayState.swift
//  Nudge
//
//  Created by Codex on 6/16/26.
//

import Foundation

enum NudgeOverlayState {
    case normal
    case dragging
    case hovered
    case loading
    case result

    var size: CGSize {
        switch self {
        case .normal:
            CGSize(width: 280, height: 42)
        case .dragging:
            CGSize(width: 360, height: 104)
        case .hovered:
            CGSize(width: 380, height: 104)
        case .loading:
            CGSize(width: 380, height: 104)
        case .result:
            CGSize(width: 460, height: 320)
        }
    }
}
