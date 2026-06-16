//
//  NudgeOverlayModel.swift
//  Nudge
//
//  Created by Codex on 6/16/26.
//

import Combine
import AppKit
import Foundation
import UniformTypeIdentifiers

@MainActor
final class NudgeOverlayModel: ObservableObject {
    @Published var state: NudgeOverlayState = .normal
    @Published var prompt = ""
    @Published var submittedPrompt = ""
    @Published var responseText = ""
    @Published var errorMessage: String?
    @Published var isLoading = false

    private let geminiClient: GeminiClient
    private var conversationHistory: [GeminiConversationContent] = []

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
                let requestContents = conversationHistory + [
                    GeminiConversationContent(role: .user, text: trimmedPrompt)
                ]
                let response = try await geminiClient.generateText(contents: requestContents)
                conversationHistory.append(GeminiConversationContent(role: .user, text: trimmedPrompt))
                conversationHistory.append(GeminiConversationContent(role: .model, text: response))
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

    func beginDragging() {
        guard !isLoading, state != .result else { return }
        prompt = ""
        errorMessage = nil
        state = .dragging
    }

    func cancelDragging() {
        guard state == .dragging else { return }
        state = .normal
    }

    func submitDroppedFile(at url: URL) {
        guard !isLoading else { return }

        let displayName = url.lastPathComponent.isEmpty ? "이미지" : url.lastPathComponent
        submittedPrompt = displayName
        prompt = ""
        responseText = ""
        errorMessage = nil
        isLoading = true
        conversationHistory.removeAll()
        state = .loading

        Task {
            do {
                let imagePayload = try loadImagePayload(from: url)
                let response = try await geminiClient.analyzeImage(
                    data: imagePayload.data,
                    mimeType: imagePayload.mimeType,
                    prompt: "이 이미지를 한국어로 자세히 분석해 주세요. 핵심 내용, 눈에 띄는 요소, 필요한 후속 작업을 간결하게 정리해 주세요."
                )
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
        prompt = ""
        isLoading = false
        conversationHistory.removeAll()
        state = .normal
    }

    func copyResponseToPasteboard() {
        let textToCopy = errorMessage ?? responseText
        guard !textToCopy.isEmpty else { return }

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(textToCopy, forType: .string)
    }

    private func loadImagePayload(from url: URL) throws -> ImagePayload {
        guard let mimeType = imageMimeType(for: url) else {
            throw DropAnalysisError.unsupportedFile
        }

        let didStartAccessing = url.startAccessingSecurityScopedResource()
        defer {
            if didStartAccessing {
                url.stopAccessingSecurityScopedResource()
            }
        }

        return ImagePayload(data: try Data(contentsOf: url), mimeType: mimeType)
    }

    private func imageMimeType(for url: URL) -> String? {
        let pathExtension = url.pathExtension.lowercased()
        if let type = UTType(filenameExtension: pathExtension),
           type.conforms(to: .image) {
            return type.preferredMIMEType ?? fallbackImageMimeType(for: pathExtension)
        }

        return fallbackImageMimeType(for: pathExtension)
    }

    private func fallbackImageMimeType(for pathExtension: String) -> String? {
        switch pathExtension {
        case "jpg", "jpeg":
            "image/jpeg"
        case "png":
            "image/png"
        case "webp":
            "image/webp"
        case "heic":
            "image/heic"
        case "heif":
            "image/heif"
        default:
            nil
        }
    }
}

private struct ImagePayload {
    let data: Data
    let mimeType: String
}

private enum DropAnalysisError: LocalizedError {
    case unsupportedFile

    var errorDescription: String? {
        switch self {
        case .unsupportedFile:
            "현재는 이미지 파일만 분석할 수 있습니다. JPG, PNG, WebP, HEIC 이미지를 드롭해 주세요."
        }
    }
}
