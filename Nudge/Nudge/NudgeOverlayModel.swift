//
//  NudgeOverlayModel.swift
//  Nudge
//
//  Created by Codex on 6/16/26.
//

import Combine
import AppKit
import Foundation

@MainActor
final class NudgeOverlayModel: ObservableObject {
    @Published var state: NudgeOverlayState = .normal
    @Published var prompt = ""
    @Published var submittedPrompt = ""
    @Published var responseText = ""
    @Published var errorMessage: String?
    @Published var isLoading = false

    private let geminiClient: GeminiClient

    init(geminiClient: GeminiClient = GeminiClient()) {
        self.geminiClient = geminiClient
    }

    func submitPrompt() {
        let trimmedPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPrompt.isEmpty, !isLoading else { return }

        let shouldKeepResultPanelOpen = state == .result
        submittedPrompt = trimmedPrompt
        prompt = ""
        responseText = ""
        errorMessage = nil
        isLoading = true
        state = shouldKeepResultPanelOpen ? .result : .loading

        Task {
            do {
                let response = try await geminiClient.generateText(prompt: trimmedPrompt)
                responseText = response
                errorMessage = nil
            } catch {
                responseText = ""
                errorMessage = error.localizedDescription
            }

            isLoading = false
            state = .result
        }
    }

    func closeResult() {
        responseText = ""
        errorMessage = nil
        submittedPrompt = ""
        isLoading = false
        state = .normal
    }

    func copyResponseToPasteboard() {
        let textToCopy = errorMessage ?? responseText
        guard !textToCopy.isEmpty else { return }

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(textToCopy, forType: .string)
    }
}
