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
    @Published var displayedResponseText = ""
    @Published var errorMessage: String?
    @Published var isLoading = false
    @Published private(set) var dragPromptIconName = "doc.badge.arrow.up"
    @Published private(set) var dragPromptText = "파일을 놓아주세요"
    @Published private(set) var droppedFileName = ""
    @Published private(set) var droppedFileDisplayName = ""
    @Published private(set) var droppedFileSizeText = ""
    @Published private(set) var droppedFilePreviewIconName = "doc"
    @Published private(set) var droppedFilePreviewThumbnail: NSImage?
    @Published private(set) var droppedFileKindLabel = ""
    @Published private(set) var canOpenDroppedFile = false

    private let geminiClient: GeminiClient
    private let settingsStore: NudgeSettingsStore
    private var conversationHistory: [GeminiConversationContent] = []
    private var pendingDroppedFile: DroppedFileContext?
    private var resultDroppedFileURL: URL?
    private var lastRequest: LastRequest?
    private var typingTask: Task<Void, Never>?
    var onOpenSettings: (() -> Void)?

    init(
        settingsStore: NudgeSettingsStore,
        geminiClient: GeminiClient
    ) {
        self.settingsStore = settingsStore
        self.geminiClient = geminiClient
    }

    func submitPrompt() {
        let trimmedPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPrompt.isEmpty, !isLoading else { return }

        let shouldKeepResultPanelOpen = state == .result
        submittedPrompt = trimmedPrompt
        prompt = ""
        resetResponseOutput()
        errorMessage = nil
        isLoading = true
        state = shouldKeepResultPanelOpen ? .result : .loading

        Task {
            do {
                let baseHistory = conversationHistory
                let userContent = GeminiConversationContent.userText(trimmedPrompt)
                let contents = buildRequestContents(baseHistory: baseHistory, userContent: userContent)
                let response = try await geminiClient.generateText(contents: contents)
                conversationHistory.append(userContent)
                conversationHistory.append(GeminiConversationContent.modelText(response))
                lastRequest = .text(prompt: trimmedPrompt, baseHistory: baseHistory)
                responseText = response
                displayedResponseText = ""
                errorMessage = nil
            } catch {
                responseText = ""
                displayedResponseText = ""
                errorMessage = error.localizedDescription
            }

            isLoading = false
            state = .result
            if errorMessage == nil {
                startTypingResponse(responseText)
            }
        }
    }

    func beginDragging(url: URL) {
        guard !isLoading, state != .result else { return }
        prompt = ""
        cancelTypingResponse()
        errorMessage = nil
        updateDragPresentation(for: url)
        state = .dragging
    }

    func cancelDragging() {
        guard state == .dragging else { return }
        state = .normal
    }

    func submitDroppedFile(at url: URL) {
        guard !isLoading else { return }

        guard let payloadKind = dropFilePayloadKind(for: url) else {
            showUnsupportedDrop()
            return
        }

        let displayName = url.lastPathComponent.isEmpty ? "파일" : url.lastPathComponent
        pendingDroppedFile = DroppedFileContext(
            url: url,
            displayName: displayName,
            payloadKind: payloadKind
        )
        droppedFileName = pendingDroppedFile?.displayName ?? ""
        updateDroppedFilePreview(url: url, displayName: displayName, payloadKind: payloadKind)
        submittedPrompt = droppedFileName
        prompt = ""
        resetResponseOutput()
        errorMessage = nil
        state = .filePrompt
    }

    func submitFilePrompt() {
        guard !isLoading, let droppedFile = pendingDroppedFile else { return }

        let trimmedPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalPrompt = droppedFile.payloadKind.requestPrompt(
            settingsStore: settingsStore,
            userQuestion: trimmedPrompt.isEmpty ? settingsStore.emptyFileQuestionPrompt : trimmedPrompt
        )
        submittedPrompt = "\(droppedFile.displayName) - \(finalPrompt)"
        prompt = ""
        resetResponseOutput()
        errorMessage = nil
        isLoading = true
        conversationHistory.removeAll()
        state = .loading

        Task {
            do {
                let fileRequest = try loadFileRequest(from: droppedFile, prompt: finalPrompt)
                let fileContent = GeminiConversationContent.userFile(
                    prompt: fileRequest.prompt,
                    data: fileRequest.data,
                    mimeType: fileRequest.mimeType
                )
                let baseHistory = conversationHistory
                let response = try await geminiClient.generateText(
                    contents: buildRequestContents(baseHistory: baseHistory, userContent: fileContent)
                )
                conversationHistory.append(fileContent)
                conversationHistory.append(GeminiConversationContent.modelText(response))
                lastRequest = .file(context: droppedFile, prompt: finalPrompt, baseHistory: baseHistory)
                resultDroppedFileURL = droppedFile.url
                canOpenDroppedFile = true
                responseText = response
                displayedResponseText = ""
                errorMessage = nil
            } catch {
                responseText = ""
                displayedResponseText = ""
                errorMessage = error.localizedDescription
            }

            isLoading = false
            state = .result
            if errorMessage == nil {
                startTypingResponse(responseText)
            }
        }
    }

    func cancelFilePrompt() {
        guard state == .filePrompt else { return }
        clearDroppedFileState()
        prompt = ""
        state = .normal
    }

    func closeResult() {
        cancelTypingResponse()
        responseText = ""
        displayedResponseText = ""
        errorMessage = nil
        submittedPrompt = ""
        prompt = ""
        isLoading = false
        conversationHistory.removeAll()
        clearDroppedFileState()
        lastRequest = nil
        state = .normal
    }

    func copyResponseToPasteboard() {
        let textToCopy = errorMessage ?? responseText
        guard !textToCopy.isEmpty else { return }

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(textToCopy, forType: .string)
    }

    func saveResponseAsTextFile() {
        let textToSave = errorMessage ?? responseText
        guard !textToSave.isEmpty else { return }

        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [.plainText]
        savePanel.canCreateDirectories = true
        savePanel.nameFieldStringValue = defaultSaveFileName()
        savePanel.begin { response in
            guard response == .OK, let url = savePanel.url else { return }
            try? textToSave.write(to: url, atomically: true, encoding: .utf8)
        }
    }

    func shareResponse() {
        let textToShare = errorMessage ?? responseText
        guard !textToShare.isEmpty,
              let contentView = NSApp.keyWindow?.contentView ?? NSApp.mainWindow?.contentView else { return }

        let picker = NSSharingServicePicker(items: [textToShare])
        picker.show(relativeTo: contentView.bounds, of: contentView, preferredEdge: .minY)
    }

    func openDroppedFile() {
        guard let resultDroppedFileURL else { return }
        NSWorkspace.shared.open(resultDroppedFileURL)
    }

    func regenerateLastResponse() {
        guard !isLoading, let lastRequest else { return }

        resetResponseOutput()
        errorMessage = nil
        isLoading = true
        state = .result

        Task {
            do {
                switch lastRequest {
                case let .text(prompt, baseHistory):
                    submittedPrompt = prompt
                    let userContent = GeminiConversationContent.userText(prompt)
                    let response = try await geminiClient.generateText(
                        contents: buildRequestContents(baseHistory: baseHistory, userContent: userContent)
                    )
                    conversationHistory = baseHistory + [userContent, GeminiConversationContent.modelText(response)]
                    responseText = response
                case let .file(context, prompt, baseHistory):
                    submittedPrompt = "\(context.displayName) - \(prompt)"
                    let fileRequest = try loadFileRequest(from: context, prompt: prompt)
                    let fileContent = GeminiConversationContent.userFile(
                        prompt: fileRequest.prompt,
                        data: fileRequest.data,
                        mimeType: fileRequest.mimeType
                    )
                    let response = try await geminiClient.generateText(
                        contents: buildRequestContents(baseHistory: baseHistory, userContent: fileContent)
                    )
                    conversationHistory = baseHistory + [fileContent, GeminiConversationContent.modelText(response)]
                    resultDroppedFileURL = context.url
                    canOpenDroppedFile = true
                    responseText = response
                }

                displayedResponseText = ""
                errorMessage = nil
            } catch {
                responseText = ""
                displayedResponseText = ""
                errorMessage = error.localizedDescription
            }

            isLoading = false
            if errorMessage == nil {
                startTypingResponse(responseText)
            }
        }
    }

    func openSettings() {
        onOpenSettings?()
    }

    private func resetResponseOutput() {
        cancelTypingResponse()
        responseText = ""
        displayedResponseText = ""
    }

    private func buildRequestContents(
        baseHistory: [GeminiConversationContent],
        userContent: GeminiConversationContent
    ) -> [GeminiConversationContent] {
        let systemPrompt = settingsStore.textSystemPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !systemPrompt.isEmpty else {
            return baseHistory + [userContent]
        }

        return [
            GeminiConversationContent.userText("시스템 지침:\n\(systemPrompt)")
        ] + baseHistory + [userContent]
    }

    private func cancelTypingResponse() {
        typingTask?.cancel()
        typingTask = nil
    }

    private func startTypingResponse(_ text: String) {
        cancelTypingResponse()
        displayedResponseText = ""
        guard !text.isEmpty else { return }

        typingTask = Task { @MainActor [weak self] in
            var typedText = ""

            for character in text {
                guard !Task.isCancelled else { return }

                typedText.append(character)
                self?.displayedResponseText = typedText

                let delay: UInt64 = character == "\n" ? 12_000_000 : 5_000_000
                try? await Task.sleep(nanoseconds: delay)
            }

            self?.typingTask = nil
        }
    }

    private func loadFileRequest(from context: DroppedFileContext, prompt: String) throws -> DropFileRequest {
        let didStartAccessing = context.url.startAccessingSecurityScopedResource()
        defer {
            if didStartAccessing {
                context.url.stopAccessingSecurityScopedResource()
            }
        }

        return DropFileRequest(
            data: try Data(contentsOf: context.url),
            mimeType: context.payloadKind.mimeType,
            prompt: prompt
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

    private func updateDragPresentation(for url: URL) {
        guard let payloadKind = dropFilePayloadKind(for: url) else {
            dragPromptIconName = "exclamationmark.triangle"
            dragPromptText = "지원하지 않는 파일입니다"
            return
        }

        dragPromptIconName = payloadKind.iconName
        dragPromptText = payloadKind.dropPromptText
    }

    private func showUnsupportedDrop() {
        dragPromptIconName = "exclamationmark.triangle"
        dragPromptText = "지원하지 않는 파일입니다"
        state = .dragging

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { [weak self] in
            guard let self, state == .dragging else { return }
            state = .normal
        }
    }

    private func clearDroppedFileState() {
        pendingDroppedFile = nil
        resultDroppedFileURL = nil
        droppedFileName = ""
        droppedFileDisplayName = ""
        droppedFileSizeText = ""
        droppedFilePreviewIconName = "doc"
        droppedFilePreviewThumbnail = nil
        droppedFileKindLabel = ""
        canOpenDroppedFile = false
    }

    private func updateDroppedFilePreview(
        url: URL,
        displayName: String,
        payloadKind: DropFilePayloadKind
    ) {
        droppedFileDisplayName = displayName
        droppedFileSizeText = fileSizeText(for: url)
        droppedFilePreviewIconName = payloadKind.previewIconName
        droppedFileKindLabel = payloadKind.kindLabel

        switch payloadKind {
        case .image:
            droppedFilePreviewThumbnail = NSImage(contentsOf: url)
        case .pdf:
            droppedFilePreviewThumbnail = nil
        }
    }

    private func fileSizeText(for url: URL) -> String {
        let byteCount = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) ?? 0
        guard byteCount > 0 else { return "크기 알 수 없음" }

        return ByteCountFormatter.string(fromByteCount: byteCount, countStyle: .file)
    }

    private func defaultSaveFileName() -> String {
        let baseName = submittedPrompt.isEmpty ? "Nudge Response" : submittedPrompt
        let sanitizedName = baseName
            .components(separatedBy: CharacterSet(charactersIn: "/\\:?%*|\"<>"))
            .joined(separator: "-")
        return "\(String(sanitizedName.prefix(48))).txt"
    }
}

private struct DropFileRequest {
    let data: Data
    let mimeType: String
    let prompt: String
}

private struct DroppedFileContext {
    let url: URL
    let displayName: String
    let payloadKind: DropFilePayloadKind
}

private enum LastRequest {
    case text(prompt: String, baseHistory: [GeminiConversationContent])
    case file(context: DroppedFileContext, prompt: String, baseHistory: [GeminiConversationContent])
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

    func requestPrompt(settingsStore: NudgeSettingsStore, userQuestion: String) -> String {
        let question = userQuestion.trimmingCharacters(in: .whitespacesAndNewlines)
        let fallbackQuestion = question.isEmpty ? NudgeSettingsStore.Defaults.emptyFileQuestionPrompt : question

        switch self {
        case .image:
            return [settingsStore.imageAnalysisPrompt, "사용자 요청: \(fallbackQuestion)"]
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .joined(separator: "\n\n")
        case .pdf:
            return [settingsStore.pdfAnalysisPrompt, "사용자 요청: \(fallbackQuestion)"]
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .joined(separator: "\n\n")
        }
    }

    var dropPromptText: String {
        switch self {
        case .image:
            "이미지를 놓아주세요"
        case .pdf:
            "PDF를 놓아주세요"
        }
    }

    var iconName: String {
        switch self {
        case .image:
            "photo.badge.arrow.down"
        case .pdf:
            "doc.text.magnifyingglass"
        }
    }

    var previewIconName: String {
        switch self {
        case .image:
            "photo"
        case .pdf:
            "doc.text.magnifyingglass"
        }
    }

    var kindLabel: String {
        switch self {
        case .image:
            "이미지"
        case .pdf:
            "PDF"
        }
    }
}
