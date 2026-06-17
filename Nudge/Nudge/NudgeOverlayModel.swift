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

enum NudgeResultStatusKind {
    case missingAPIKey
    case networkFailure
    case unsupportedFile
    case appleUnavailable
    case emptyResponse
    case genericError
    case empty
}

struct NudgeFileAnalysisTemplate: Identifiable {
    let title: String
    let prompt: String

    var id: String {
        title
    }
}

struct NudgeDroppedFilePreviewItem {
    let thumbnail: NSImage?
    let iconName: String
}

@MainActor
final class NudgeOverlayModel: ObservableObject {
    @Published var state: NudgeOverlayState = .normal
    @Published var prompt = ""
    @Published var submittedPrompt = ""
    @Published var responseText = ""
    @Published var displayedResponseText = ""
    @Published var errorMessage: String?
    @Published private(set) var resultStatusKind: NudgeResultStatusKind?
    @Published var isLoading = false
    @Published private(set) var responseProviderTitle = "Gemini"
    @Published private(set) var dragPromptIconName = "doc.badge.arrow.up"
    @Published private(set) var dragPromptText = "파일을 놓아주세요"
    @Published private(set) var droppedFileName = ""
    @Published private(set) var droppedFileDisplayName = ""
    @Published private(set) var droppedFileSizeText = ""
    @Published private(set) var droppedFilePreviewIconName = "doc"
    @Published private(set) var droppedFilePreviewThumbnail: NSImage?
    @Published private(set) var droppedFilePreviewThumbnails: [NSImage] = []
    @Published private(set) var droppedFilePreviewIconNames: [String] = []
    @Published private(set) var droppedFilePreviewItems: [NudgeDroppedFilePreviewItem] = []
    @Published private(set) var droppedFileKindLabel = ""
    @Published private(set) var droppedFileCount = 0
    @Published private(set) var fileAnalysisTemplates: [NudgeFileAnalysisTemplate] = []
    @Published private(set) var selectedFileAnalysisTemplateID: String?
    @Published private(set) var canOpenDroppedFile = false

    var isFileResult: Bool {
        canOpenDroppedFile && !droppedFileDisplayName.isEmpty
    }

    var hasMultipleDroppedFiles: Bool {
        droppedFileCount > 1
    }

    var activeResultStatusKind: NudgeResultStatusKind? {
        if let resultStatusKind {
            return resultStatusKind
        }

        guard state == .result,
              !isLoading,
              errorMessage == nil,
              responseText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              displayedResponseText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }

        return .empty
    }

    var canRetryLastRequest: Bool {
        lastRequest != nil && !isLoading
    }

    private let geminiClient: GeminiClient
    private let appleFoundationModelClient = AppleFoundationModelClient()
    private let settingsStore: NudgeSettingsStore
    private var conversationHistory: [GeminiConversationContent] = []
    private var textConversationHistory: [AITextConversationMessage] = []
    private var pendingDroppedFiles: [DroppedFileContext] = []
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
                if isFileConversationActive {
                    responseProviderTitle = NudgeSettingsStore.AIProvider.gemini.title
                    let baseHistory = conversationHistory
                    let userContent = GeminiConversationContent.userText(trimmedPrompt)
                    let response = try await geminiClient.generateText(
                        contents: buildRequestContents(baseHistory: baseHistory, userContent: userContent)
                    )
                    conversationHistory.append(userContent)
                    conversationHistory.append(GeminiConversationContent.modelText(response))
                    lastRequest = .fileFollowUp(prompt: trimmedPrompt, baseHistory: baseHistory)
                    responseText = response
                } else {
                    let provider = settingsStore.aiProvider
                    responseProviderTitle = provider.title
                    let baseHistory = textConversationHistory
                    let userMessage = AITextConversationMessage.user(trimmedPrompt)
                    let messages = buildTextMessages(baseHistory: baseHistory, userMessage: userMessage)
                    let response = try await generateTextResponse(provider: provider, messages: messages)
                    textConversationHistory.append(userMessage)
                    textConversationHistory.append(.assistant(response))
                    lastRequest = .text(prompt: trimmedPrompt, provider: provider, baseHistory: baseHistory)
                    responseText = response
                }

                displayedResponseText = ""
                errorMessage = nil
            } catch {
                setError(error)
            }

            isLoading = false
            state = .result
            if errorMessage == nil {
                startTypingResponse(responseText)
            }
        }
    }

    func beginDragging(urls: [URL]) {
        guard !isLoading, state != .result else { return }
        prompt = ""
        cancelTypingResponse()
        errorMessage = nil
        resultStatusKind = nil
        updateDragPresentation(for: urls)
        state = .dragging
    }

    func cancelDragging() {
        guard state == .dragging else { return }
        state = .normal
    }

    func submitDroppedFiles(at urls: [URL]) {
        guard !isLoading else { return }
        let fileURLs = urls.filter { $0.isFileURL }
        guard !fileURLs.isEmpty else {
            showUnsupportedDrop(displayName: "지원하지 않는 파일")
            return
        }

        let contexts = droppedFileContexts(for: fileURLs)
        guard contexts.count == fileURLs.count else {
            showUnsupportedDrop(displayName: unsupportedDropDisplayName(for: fileURLs))
            return
        }

        pendingDroppedFiles = contexts
        droppedFileName = contexts.first?.displayName ?? ""
        updateDroppedFilesPreview(contexts)
        submittedPrompt = droppedFileDisplayName
        prompt = ""
        resetResponseOutput()
        errorMessage = nil
        resultStatusKind = nil
        textConversationHistory.removeAll()
        state = .filePrompt
    }

    func submitFilePrompt() {
        guard !isLoading, !pendingDroppedFiles.isEmpty else { return }

        let trimmedPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalPrompt = requestPrompt(
            for: pendingDroppedFiles,
            settingsStore: settingsStore,
            userQuestion: trimmedPrompt.isEmpty ? settingsStore.emptyFileQuestionPrompt : trimmedPrompt
        )
        let fileSummary = droppedFileDisplayName.isEmpty ? droppedFileName : droppedFileDisplayName
        submittedPrompt = "\(fileSummary) - \(finalPrompt)"
        prompt = ""
        resetResponseOutput()
        errorMessage = nil
        isLoading = true
        responseProviderTitle = NudgeSettingsStore.AIProvider.gemini.title
        textConversationHistory.removeAll()
        conversationHistory.removeAll()
        state = .loading

        Task {
            do {
                let droppedFiles = pendingDroppedFiles
                let fileRequests = try loadFileRequests(from: droppedFiles, prompt: finalPrompt)
                let fileContent = GeminiConversationContent.userFiles(
                    prompt: finalPrompt,
                    files: fileRequests.map { ($0.data, $0.mimeType) }
                )
                let baseHistory = conversationHistory
                let response = try await geminiClient.generateText(
                    contents: buildRequestContents(baseHistory: baseHistory, userContent: fileContent)
                )
                conversationHistory.append(fileContent)
                conversationHistory.append(GeminiConversationContent.modelText(response))
                lastRequest = .file(contexts: droppedFiles, prompt: finalPrompt, baseHistory: baseHistory)
                resultDroppedFileURL = droppedFiles.first?.url
                canOpenDroppedFile = true
                responseText = response
                displayedResponseText = ""
                errorMessage = nil
            } catch {
                setError(error)
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

    func applyFileAnalysisTemplate(_ template: NudgeFileAnalysisTemplate) {
        guard state == .filePrompt, !isLoading else { return }
        selectedFileAnalysisTemplateID = template.id
        prompt = template.prompt
    }

    func closeResult() {
        cancelTypingResponse()
        responseText = ""
        displayedResponseText = ""
        errorMessage = nil
        resultStatusKind = nil
        submittedPrompt = ""
        prompt = ""
        isLoading = false
        responseProviderTitle = NudgeSettingsStore.AIProvider.gemini.title
        conversationHistory.removeAll()
        textConversationHistory.removeAll()
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
                case let .text(prompt, provider, baseHistory):
                    submittedPrompt = prompt
                    responseProviderTitle = provider.title
                    let userMessage = AITextConversationMessage.user(prompt)
                    let response = try await generateTextResponse(
                        provider: provider,
                        messages: buildTextMessages(baseHistory: baseHistory, userMessage: userMessage)
                    )
                    textConversationHistory = baseHistory + [userMessage, .assistant(response)]
                    responseText = response
                case let .fileFollowUp(prompt, baseHistory):
                    submittedPrompt = prompt
                    responseProviderTitle = NudgeSettingsStore.AIProvider.gemini.title
                    let userContent = GeminiConversationContent.userText(prompt)
                    let response = try await geminiClient.generateText(
                        contents: buildRequestContents(baseHistory: baseHistory, userContent: userContent)
                    )
                    conversationHistory = baseHistory + [userContent, GeminiConversationContent.modelText(response)]
                    responseText = response
                case let .file(contexts, prompt, baseHistory):
                    let displayName = displayName(for: contexts)
                    submittedPrompt = "\(displayName) - \(prompt)"
                    responseProviderTitle = NudgeSettingsStore.AIProvider.gemini.title
                    let fileRequests = try loadFileRequests(from: contexts, prompt: prompt)
                    let fileContent = GeminiConversationContent.userFiles(
                        prompt: prompt,
                        files: fileRequests.map { ($0.data, $0.mimeType) }
                    )
                    let response = try await geminiClient.generateText(
                        contents: buildRequestContents(baseHistory: baseHistory, userContent: fileContent)
                    )
                    conversationHistory = baseHistory + [fileContent, GeminiConversationContent.modelText(response)]
                    resultDroppedFileURL = contexts.first?.url
                    canOpenDroppedFile = true
                    responseText = response
                }

                displayedResponseText = ""
                errorMessage = nil
            } catch {
                setError(error)
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

    private var isFileConversationActive: Bool {
        canOpenDroppedFile && !conversationHistory.isEmpty
    }

    private func resetResponseOutput() {
        cancelTypingResponse()
        responseText = ""
        displayedResponseText = ""
        resultStatusKind = nil
    }

    private func setError(_ error: Error) {
        responseText = ""
        displayedResponseText = ""
        errorMessage = error.localizedDescription
        resultStatusKind = statusKind(for: error)
    }

    private func statusKind(for error: Error) -> NudgeResultStatusKind {
        if let geminiError = error as? GeminiClient.GeminiError {
            switch geminiError {
            case .missingAPIKey:
                return .missingAPIKey
            case .emptyResponse:
                return .emptyResponse
            case .apiError:
                return .genericError
            case .invalidURL, .invalidResponse:
                return .genericError
            }
        }

        if let appleError = error as? AppleFoundationModelClient.AppleFoundationModelError {
            switch appleError {
            case .unavailable:
                return .appleUnavailable
            case .emptyResponse:
                return .emptyResponse
            }
        }

        if let urlError = error as? URLError {
            switch urlError.code {
            case .notConnectedToInternet,
                 .cannotFindHost,
                 .cannotConnectToHost,
                 .networkConnectionLost,
                 .timedOut,
                 .dnsLookupFailed,
                 .internationalRoamingOff,
                 .dataNotAllowed,
                 .secureConnectionFailed:
                return .networkFailure
            default:
                break
            }
        }

        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain {
            return .networkFailure
        }

        return .genericError
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

    private func buildTextMessages(
        baseHistory: [AITextConversationMessage],
        userMessage: AITextConversationMessage
    ) -> [AITextConversationMessage] {
        let systemPrompt = settingsStore.textSystemPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !systemPrompt.isEmpty else {
            return baseHistory + [userMessage]
        }

        return [.system(systemPrompt)] + baseHistory + [userMessage]
    }

    private func generateTextResponse(
        provider: NudgeSettingsStore.AIProvider,
        messages: [AITextConversationMessage]
    ) async throws -> String {
        switch provider {
        case .gemini:
            return try await geminiClient.generateText(messages: messages)
        case .appleIntelligence:
            return try await appleFoundationModelClient.generateText(messages: messages)
        }
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

    private func loadFileRequests(from contexts: [DroppedFileContext], prompt: String) throws -> [DropFileRequest] {
        try contexts.map { try loadFileRequest(from: $0, prompt: prompt) }
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

    private func droppedFileContexts(for urls: [URL]) -> [DroppedFileContext] {
        urls.compactMap { url in
            guard let payloadKind = dropFilePayloadKind(for: url) else { return nil }
            return DroppedFileContext(
                url: url,
                displayName: url.lastPathComponent.isEmpty ? "파일" : url.lastPathComponent,
                payloadKind: payloadKind
            )
        }
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

    private func updateDragPresentation(for urls: [URL]) {
        let fileURLs = urls.filter { $0.isFileURL }
        let contexts = droppedFileContexts(for: fileURLs)

        guard !fileURLs.isEmpty, contexts.count == fileURLs.count else {
            dragPromptIconName = "exclamationmark.triangle"
            dragPromptText = "지원하지 않는 파일입니다"
            return
        }

        dragPromptIconName = dragIconName(for: contexts)
        dragPromptText = dropPromptText(for: contexts)
    }

    private func showUnsupportedDrop(displayName: String) {
        clearDroppedFileState()
        prompt = ""
        submittedPrompt = displayName
        responseProviderTitle = "Nudge"
        resetResponseOutput()
        errorMessage = "현재는 이미지와 PDF 파일을 우선 지원합니다."
        resultStatusKind = .unsupportedFile
        state = .result
    }

    private func clearDroppedFileState() {
        pendingDroppedFiles = []
        resultDroppedFileURL = nil
        droppedFileName = ""
        droppedFileDisplayName = ""
        droppedFileSizeText = ""
        droppedFilePreviewIconName = "doc"
        droppedFilePreviewThumbnail = nil
        droppedFilePreviewThumbnails = []
        droppedFilePreviewIconNames = []
        droppedFilePreviewItems = []
        droppedFileKindLabel = ""
        droppedFileCount = 0
        fileAnalysisTemplates = []
        selectedFileAnalysisTemplateID = nil
        canOpenDroppedFile = false
    }

    private func updateDroppedFilesPreview(_ contexts: [DroppedFileContext]) {
        droppedFileCount = contexts.count
        droppedFileDisplayName = displayName(for: contexts)
        droppedFileSizeText = totalFileSizeText(for: contexts)
        droppedFileKindLabel = collectionKind(for: contexts).kindLabel
        droppedFilePreviewIconName = collectionKind(for: contexts).previewIconName
        droppedFilePreviewIconNames = contexts.prefix(3).map(\.payloadKind.previewIconName)
        droppedFilePreviewItems = contexts.prefix(3).map { context in
            let thumbnail: NSImage?
            if case .image = context.payloadKind {
                thumbnail = NSImage(contentsOf: context.url)
            } else {
                thumbnail = nil
            }

            return NudgeDroppedFilePreviewItem(
                thumbnail: thumbnail,
                iconName: context.payloadKind.previewIconName
            )
        }
        droppedFilePreviewThumbnails = contexts
            .prefix(3)
            .compactMap { context in
                guard case .image = context.payloadKind else { return nil }
                return NSImage(contentsOf: context.url)
            }
        droppedFilePreviewThumbnail = droppedFilePreviewThumbnails.first
        fileAnalysisTemplates = analysisTemplates(for: contexts)
    }

    private func fileSizeText(for url: URL) -> String {
        let byteCount = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) ?? 0
        guard byteCount > 0 else { return "크기 알 수 없음" }

        return ByteCountFormatter.string(fromByteCount: byteCount, countStyle: .file)
    }

    private func totalFileSizeText(for contexts: [DroppedFileContext]) -> String {
        let totalSize = contexts.reduce(Int64(0)) { partialResult, context in
            let fileSize = (try? context.url.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) ?? 0
            return partialResult + fileSize
        }

        guard totalSize > 0 else { return "크기 알 수 없음" }
        return ByteCountFormatter.string(fromByteCount: totalSize, countStyle: .file)
    }

    private func displayName(for contexts: [DroppedFileContext]) -> String {
        guard contexts.count > 1 else {
            return contexts.first?.displayName ?? "파일"
        }

        return "\(collectionKind(for: contexts).kindLabel) \(contexts.count)개"
    }

    private func unsupportedDropDisplayName(for urls: [URL]) -> String {
        guard urls.count > 1 else {
            return urls.first?.lastPathComponent.isEmpty == false ? urls[0].lastPathComponent : "지원하지 않는 파일"
        }

        return "지원하지 않는 파일 \(urls.count)개"
    }

    private func collectionKind(for contexts: [DroppedFileContext]) -> DropFileCollectionKind {
        let hasImage = contexts.contains { context in
            if case .image = context.payloadKind { return true }
            return false
        }
        let hasPDF = contexts.contains { context in
            if case .pdf = context.payloadKind { return true }
            return false
        }

        switch (hasImage, hasPDF) {
        case (true, true):
            return .mixed
        case (true, false):
            return .image
        case (false, true):
            return .pdf
        default:
            return .mixed
        }
    }

    private func dragIconName(for contexts: [DroppedFileContext]) -> String {
        if contexts.count == 1 {
            return contexts[0].payloadKind.iconName
        }

        return collectionKind(for: contexts).dragIconName
    }

    private func dropPromptText(for contexts: [DroppedFileContext]) -> String {
        if contexts.count == 1 {
            return contexts[0].payloadKind.dropPromptText
        }

        return "\(collectionKind(for: contexts).kindLabel) \(contexts.count)개를 놓아주세요"
    }

    private func requestPrompt(
        for contexts: [DroppedFileContext],
        settingsStore: NudgeSettingsStore,
        userQuestion: String
    ) -> String {
        guard contexts.count > 1 else {
            return contexts[0].payloadKind.requestPrompt(settingsStore: settingsStore, userQuestion: userQuestion)
        }

        let question = userQuestion.trimmingCharacters(in: .whitespacesAndNewlines)
        let fallbackQuestion = question.isEmpty ? NudgeSettingsStore.Defaults.emptyFileQuestionPrompt : question
        let kind = collectionKind(for: contexts)
        let basePrompt: String

        switch kind {
        case .image:
            basePrompt = settingsStore.imageAnalysisPrompt
        case .pdf:
            basePrompt = settingsStore.pdfAnalysisPrompt
        case .mixed:
            basePrompt = [settingsStore.imageAnalysisPrompt, settingsStore.pdfAnalysisPrompt]
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .joined(separator: "\n\n")
        }

        return [
            "여러 파일을 함께 분석해 주세요. 파일 간 공통점, 차이점, 연결되는 맥락이 있으면 함께 정리해 주세요.",
            basePrompt,
            "사용자 요청: \(fallbackQuestion)"
        ]
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }
        .joined(separator: "\n\n")
    }

    private func analysisTemplates(for contexts: [DroppedFileContext]) -> [NudgeFileAnalysisTemplate] {
        switch collectionKind(for: contexts) {
        case .image:
            return [
                NudgeFileAnalysisTemplate(title: "설명", prompt: "이미지의 주요 피사체와 장면을 간단히 설명해줘"),
                NudgeFileAnalysisTemplate(title: "분위기", prompt: "이미지의 분위기, 색감, 감정적 인상을 정리해줘"),
                NudgeFileAnalysisTemplate(title: "OCR", prompt: "이미지에서 읽을 수 있는 텍스트를 추출하고 정리해줘"),
                NudgeFileAnalysisTemplate(title: "디자인 피드백", prompt: "디자인 관점에서 구도, 색감, 가독성, 개선점을 피드백해줘")
            ]
        case .pdf:
            return [
                NudgeFileAnalysisTemplate(title: "요약", prompt: "PDF의 핵심 내용을 요약해줘"),
                NudgeFileAnalysisTemplate(title: "목차", prompt: "PDF의 목차와 문서 구조를 정리해줘"),
                NudgeFileAnalysisTemplate(title: "액션 아이템", prompt: "PDF에서 실행해야 할 액션 아이템을 뽑아줘"),
                NudgeFileAnalysisTemplate(title: "표 추출", prompt: "PDF 안의 표나 수치 정보를 찾아 정리해줘")
            ]
        case .mixed:
            return [
                NudgeFileAnalysisTemplate(title: "요약", prompt: "여러 파일의 핵심 내용을 종합해서 요약해줘"),
                NudgeFileAnalysisTemplate(title: "비교", prompt: "파일들을 서로 비교해서 중요한 차이를 정리해줘"),
                NudgeFileAnalysisTemplate(title: "공통점", prompt: "파일들 사이의 공통점을 찾아 정리해줘"),
                NudgeFileAnalysisTemplate(title: "차이점", prompt: "파일들 사이의 차이점을 중심으로 정리해줘")
            ]
        }
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
    case text(
        prompt: String,
        provider: NudgeSettingsStore.AIProvider,
        baseHistory: [AITextConversationMessage]
    )
    case fileFollowUp(prompt: String, baseHistory: [GeminiConversationContent])
    case file(contexts: [DroppedFileContext], prompt: String, baseHistory: [GeminiConversationContent])
}

private enum DropFileCollectionKind {
    case image
    case pdf
    case mixed

    var kindLabel: String {
        switch self {
        case .image:
            "이미지"
        case .pdf:
            "PDF"
        case .mixed:
            "파일"
        }
    }

    var dragIconName: String {
        switch self {
        case .image:
            "photo.stack"
        case .pdf:
            "doc.text.magnifyingglass"
        case .mixed:
            "square.stack.3d.up"
        }
    }

    var previewIconName: String {
        switch self {
        case .image:
            "photo.stack"
        case .pdf:
            "doc.text.magnifyingglass"
        case .mixed:
            "square.stack.3d.up"
        }
    }
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
