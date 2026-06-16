//
//  NudgeOverlayModel.swift
//  Nudge
//
//  Created by Codex on 6/16/26.
//

import Combine
import Foundation

@MainActor
final class NudgeOverlayModel: ObservableObject {
    @Published var state: NudgeOverlayState = .normal
}
