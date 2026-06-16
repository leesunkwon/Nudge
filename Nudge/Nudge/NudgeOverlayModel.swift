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

        let displayName = url.lastPathComponent.isEmpty ? "파일" : url.lastPathComponent
        submittedPrompt = displayName
        prompt = ""
        responseText = ""
        errorMessage = nil
        isLoading = true
        conversationHistory.removeAll()
        state = .loading

        Task {
            do {
                let filePayload = try loadDropFilePayload(from: url)
                let response = try await geminiClient.analyzeFile(
                    data: filePayload.data,
                    mimeType: filePayload.mimeType,
                    prompt: filePayload.analysisPrompt
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

    private func loadDropFilePayload(from url: URL) throws -> DropFilePayload {
        guard let payloadKind = dropFilePayloadKind(for: url) else {
            throw DropAnalysisError.unsupportedFile
        }

        let didStartAccessing = url.startAccessingSecurityScopedResource()
        defer {
            if didStartAccessing {
                url.stopAccessingSecurityScopedResource()
            }
        }

        return DropFilePayload(
            data: try Data(contentsOf: url),
            mimeType: payloadKind.mimeType,
            analysisPrompt: payloadKind.analysisPrompt
        )
    }

    private func dropFilePayloadKind(for url: URL) -> DropFilePayloadKind? {
        let pathExtension = url.pathExtension.lowercased()

        if let type = UTType(filenameExtension: pathExtension),
           type.conforms(to: .pdf) {
            return .pdf
        }

        if fallbackDocumentMimeType(for: pathExtension) == "application/pdf" {
            return .pdf
        }

        if let type = UTType(filenameExtension: pathExtension),
           type.conforms(to: .image) {
            guard let mimeType = type.preferredMIMEType ?? fallbackImageMimeType(for: pathExtension) else {
                return nil
            }

            return .image(mimeType: mimeType)
        }

        if let mimeType = fallbackImageMimeType(for: pathExtension) {
            return .image(mimeType: mimeType)
        }

        return nil
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

    private func fallbackDocumentMimeType(for pathExtension: String) -> String? {
        switch pathExtension {
        case "pdf":
            "application/pdf"
        default:
            nil
        }
    }
}

private struct DropFilePayload {
    let data: Data
    let mimeType: String
    let analysisPrompt: String
}

private enum DropFilePayloadKind {
    case image(mimeType: String)
    case pdf

    var mimeType: String {
        switch self {
        case let .image(mimeType):
            mimeType
        case .pdf:
            "application/pdf"
        }
    }

    var analysisPrompt: String {
        switch self {
        case .image:
            "이 이미지를 한국어로 자세히 분석해 주세요. 핵심 내용, 눈에 띄는 요소, 필요한 후속 작업을 간결하게 정리해 주세요."
        case .pdf:
            "이 PDF 문서를 한국어로 자세히 분석해 주세요. 핵심 요약, 주요 주장이나 내용, 표와 차트에서 읽을 수 있는 정보, 필요한 후속 작업을 간결하게 정리해 주세요."
        }
    }
}

private enum DropAnalysisError: LocalizedError {
    case unsupportedFile

    var errorDescription: String? {
        switch self {
        case .unsupportedFile:
            "현재는 이미지와 PDF 파일만 분석할 수 있습니다. JPG, PNG, WebP, HEIC 이미지 또는 PDF를 드롭해 주세요."
        }
    }
}
