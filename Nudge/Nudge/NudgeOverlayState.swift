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
            CGSize(width: 300, height: 44)
        case .dragging:
            CGSize(width: 540, height: 144)
        case .hovered:
            CGSize(width: 540, height: 144)
        case .loading:
            CGSize(width: 540, height: 144)
        case .result:
            CGSize(width: 640, height: 460)
        }
    }
}
