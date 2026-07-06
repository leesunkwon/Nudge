//
//  NudgeOverlayModel.swift
//  Nudge
//
//  Created by Codex on 6/16/26.
//

import Combine
import AppKit
import Foundation
import PDFKit
import UniformTypeIdentifiers

enum NudgeResultStatusKind {
    case missingAPIKey
    case networkFailure
    case unsupportedFile
    case emptyResponse
    case genericError
    case empty
}

enum NudgeFileQuestionMode: String, CaseIterable, Identifiable {
    case summary
    case analysis
    case compare
    case extract
    case feedback

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .summary:
            "요약"
        case .analysis:
            "분석"
        case .compare:
            "비교"
        case .extract:
            "추출"
        case .feedback:
            "피드백"
        }
    }

    var description: String {
        switch self {
        case .summary:
            "핵심만 빠르게 정리"
        case .analysis:
            "구조와 의미를 깊게 확인"
        case .compare:
            "차이와 공통점 정리"
        case .extract:
            "필요한 정보만 뽑기"
        case .feedback:
            "개선점과 의견 제안"
        }
    }

    var iconName: String {
        switch self {
        case .summary:
            "doc.text"
        case .analysis:
            "magnifyingglass"
        case .compare:
            "arrow.left.arrow.right"
        case .extract:
            "line.3.horizontal.decrease.circle"
        case .feedback:
            "text.bubble"
        }
    }

    var placeholder: String {
        switch self {
        case .summary:
            "요약 기준을 추가로 입력해 보세요..."
        case .analysis:
            "무엇을 중심으로 분석할까요?"
        case .compare:
            "무엇을 비교할까요?"
        case .extract:
            "어떤 정보를 추출할까요?"
        case .feedback:
            "어떤 관점의 피드백이 필요할까요?"
        }
    }
}

struct NudgeDroppedFilePreviewItem {
    let thumbnail: NSImage?
    let iconName: String
}

private enum NudgeFileProcessingError: LocalizedError {
    case pdfLimitExceeded

    var errorDescription: String? {
        switch self {
        case .pdfLimitExceeded:
            "PDF는 최대 50MB 또는 1000페이지까지 지원합니다."
        }
    }
}

@MainActor
final class NudgeOverlayModel: ObservableObject {
    @Published var state: NudgeOverlayState = .normal
    @Published var prompt = ""
    @Published var submittedPrompt = ""
    @Published var responseText = ""
    @Published var displayedResponseText = ""
    @Published var errorMessage: String?
    @Published private(set) var loadingStatusText: String?
    @Published private(set) var uploadProgress: Double?
    @Published private(set) var filePromptNoticeText: String?
    @Published private(set) var toastMessage: String?
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
    @Published private(set) var selectedFileQuestionMode: NudgeFileQuestionMode = .summary
    @Published private(set) var resultFileQuestionMode: NudgeFileQuestionMode?
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

    var fileQuestionModes: [NudgeFileQuestionMode] {
        NudgeFileQuestionMode.allCases
    }

    var filePromptPlaceholder: String {
        selectedFileQuestionMode.placeholder
    }

    var isCancellableLoading: Bool {
        isLoading && requestTask != nil
    }

    var currentModelStatusText: String {
        switch settingsStore.selectedModel {
        case .auto:
            guard responseProviderTitle.hasPrefix("Gemini · 자동 · ") else {
                return "자동"
            }

            return responseProviderTitle.replacingOccurrences(of: "Gemini · ", with: "")
        case .fast, .advanced:
            return settingsStore.selectedModel.title
        }
    }

    private let geminiClient: GeminiClient
    private let settingsStore: NudgeSettingsStore
    private let totalExtractedTextCharacterLimit = 300_000
    private let longTextPromptThreshold = 1_000
    private let largeFileByteThreshold: Int64 = 5 * 1024 * 1024
    private let inlineDataByteThreshold: Int64 = 14 * 1024 * 1024
    private let maxPDFByteCount: Int64 = 50 * 1024 * 1024
    private let maxPDFPageCount = 1_000
    private var conversationHistory: [GeminiConversationContent] = []
    private var pendingDroppedFiles: [DroppedFileContext] = []
    private var resultDroppedFileURL: URL?
    private var activeFileConversationModel: NudgeSettingsStore.GeminiModel?
    private var lastRequest: LastRequest?
    private var loadingCancelState: NudgeOverlayState = .normal
    private var requestTask: Task<Void, Never>?
    private var typingTask: Task<Void, Never>?
    private var toastTask: Task<Void, Never>?
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
        loadingStatusText = "답변 생성 중"
        loadingCancelState = shouldKeepResultPanelOpen ? .result : .normal
        state = shouldKeepResultPanelOpen ? .result : .loading

        requestTask?.cancel()
        requestTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                if isFileConversationActive {
                    let requestModel = resolvedModelForFileFollowUp(prompt: trimmedPrompt)
                    updateResponseProviderTitle(using: requestModel)
                    let baseHistory = conversationHistory
                    let userContent = GeminiConversationContent.userText(trimmedPrompt)
                    let response = try await geminiClient.generateText(
                        contents: buildRequestContents(baseHistory: baseHistory, userContent: userContent),
                        model: requestModel
                    )
                    conversationHistory.append(userContent)
                    conversationHistory.append(GeminiConversationContent.modelText(response))
                    lastRequest = .fileFollowUp(prompt: trimmedPrompt, baseHistory: baseHistory, model: requestModel)
                    responseText = response
                } else {
                    let requestModel = resolvedModelForTextPrompt(trimmedPrompt)
                    updateResponseProviderTitle(using: requestModel)
                    let baseHistory = conversationHistory
                    let userContent = GeminiConversationContent.userText(trimmedPrompt)
                    let response = try await geminiClient.generateText(
                        contents: buildRequestContents(baseHistory: baseHistory, userContent: userContent),
                        model: requestModel
                    )
                    conversationHistory.append(userContent)
                    conversationHistory.append(GeminiConversationContent.modelText(response))
                    lastRequest = .text(prompt: trimmedPrompt, baseHistory: baseHistory, model: requestModel)
                    responseText = response
                }

                displayedResponseText = ""
                errorMessage = nil
            } catch where isCancellationError(error) {
                return
            } catch {
                setError(error)
            }

            isLoading = false
            loadingStatusText = nil
            requestTask = nil
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
        clearDroppedFileState()
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
        conversationHistory.removeAll()
        activeFileConversationModel = nil
        state = .filePrompt
    }

    func submitFilePrompt() {
        guard !isLoading, !pendingDroppedFiles.isEmpty else { return }
        guard filePromptBlockingMessage(for: pendingDroppedFiles) == nil else {
            filePromptNoticeText = NudgeFileProcessingError.pdfLimitExceeded.localizedDescription
            return
        }

        let trimmedPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalPrompt = requestPrompt(
            for: pendingDroppedFiles,
            settingsStore: settingsStore,
            mode: selectedFileQuestionMode,
            userQuestion: trimmedPrompt
        )
        let fileSummary = droppedFileDisplayName.isEmpty ? droppedFileName : droppedFileDisplayName
        let originalPrompt = prompt
        let fileQuestionMode = selectedFileQuestionMode
        submittedPrompt = "\(fileSummary) - \(finalPrompt)"
        resetResponseOutput()
        errorMessage = nil
        isLoading = true
        resultFileQuestionMode = fileQuestionMode
        let requestModel = resolvedModelForFileContexts(pendingDroppedFiles)
        updateResponseProviderTitle(using: requestModel)
        conversationHistory.removeAll()
        activeFileConversationModel = nil
        let willUseFilesAPI = shouldUseFilesAPI(for: pendingDroppedFiles)
        uploadProgress = willUseFilesAPI ? 0 : nil
        loadingStatusText = willUseFilesAPI ? "파일 업로드 중 0%" : "파일 읽는 중"
        loadingCancelState = .filePrompt
        state = .loading

        requestTask?.cancel()
        requestTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let droppedFiles = pendingDroppedFiles
                let fileRequests = try await loadFileRequests(from: droppedFiles, prompt: finalPrompt)
                loadingStatusText = "Gemini 분석 중"
                uploadProgress = nil
                let fileContent = GeminiConversationContent.userFileParts(
                    prompt: finalPrompt,
                    fileParts: fileRequests.flatMap(\.parts)
                )
                let baseHistory = conversationHistory
                let response = try await geminiClient.generateText(
                    contents: buildRequestContents(baseHistory: baseHistory, userContent: fileContent),
                    model: requestModel
                )
                conversationHistory.append(fileContent)
                conversationHistory.append(GeminiConversationContent.modelText(response))
                activeFileConversationModel = requestModel
                lastRequest = .file(
                    contexts: droppedFiles,
                    prompt: finalPrompt,
                    mode: fileQuestionMode,
                    baseHistory: baseHistory,
                    model: requestModel
                )
                resultDroppedFileURL = droppedFiles.first?.url
                canOpenDroppedFile = true
                loadingStatusText = "답변 정리 중"
                responseText = response
                displayedResponseText = ""
                errorMessage = nil
                prompt = ""
            } catch where isCancellationError(error) {
                prompt = originalPrompt
                return
            } catch {
                setError(error)
            }

            isLoading = false
            loadingStatusText = nil
            uploadProgress = nil
            requestTask = nil
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

    func cancelCurrentRequest() {
        guard isLoading else { return }
        requestTask?.cancel()
        requestTask = nil
        isLoading = false
        loadingStatusText = nil
        uploadProgress = nil
        resetResponseOutput()

        state = loadingCancelState
    }

    func cancelAndResetForPause() {
        requestTask?.cancel()
        requestTask = nil
        cancelTypingResponse()
        dismissToast()
        pendingDroppedFiles.removeAll()
        prompt = ""
        submittedPrompt = ""
        responseText = ""
        displayedResponseText = ""
        errorMessage = nil
        loadingStatusText = nil
        uploadProgress = nil
        filePromptNoticeText = nil
        toastMessage = nil
        resultStatusKind = nil
        isLoading = false
        loadingCancelState = .normal
        responseProviderTitle = "Gemini"
        conversationHistory.removeAll()
        activeFileConversationModel = nil
        clearDroppedFileState()
        lastRequest = nil
        state = .normal
    }

    func selectFileQuestionMode(_ mode: NudgeFileQuestionMode) {
        guard state == .filePrompt, !isLoading else { return }
        selectedFileQuestionMode = mode
    }

    func closeResult() {
        requestTask?.cancel()
        requestTask = nil
        cancelTypingResponse()
        dismissToast()
        responseText = ""
        displayedResponseText = ""
        errorMessage = nil
        resultStatusKind = nil
        submittedPrompt = ""
        prompt = ""
        isLoading = false
        loadingStatusText = nil
        uploadProgress = nil
        responseProviderTitle = "Gemini"
        conversationHistory.removeAll()
        activeFileConversationModel = nil
        clearDroppedFileState()
        lastRequest = nil
        state = .normal
    }

    func copyResponseToPasteboard() {
        let textToCopy = errorMessage ?? responseText
        guard !textToCopy.isEmpty else { return }

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(textToCopy, forType: .string)
        showToast("복사되었습니다")
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
        loadingStatusText = nil
        loadingCancelState = .result
        state = .result

        requestTask?.cancel()
        requestTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                switch lastRequest {
                case let .text(prompt, baseHistory, model):
                    submittedPrompt = prompt
                    updateResponseProviderTitle(using: model)
                    loadingStatusText = "답변 생성 중"
                    let userContent = GeminiConversationContent.userText(prompt)
                    let response = try await geminiClient.generateText(
                        contents: buildRequestContents(baseHistory: baseHistory, userContent: userContent),
                        model: model
                    )
                    conversationHistory = baseHistory + [userContent, GeminiConversationContent.modelText(response)]
                    responseText = response
                case let .fileFollowUp(prompt, baseHistory, model):
                    submittedPrompt = prompt
                    updateResponseProviderTitle(using: model)
                    loadingStatusText = "답변 생성 중"
                    let userContent = GeminiConversationContent.userText(prompt)
                    let response = try await geminiClient.generateText(
                        contents: buildRequestContents(baseHistory: baseHistory, userContent: userContent),
                        model: model
                    )
                    conversationHistory = baseHistory + [userContent, GeminiConversationContent.modelText(response)]
                    responseText = response
                case let .file(contexts, prompt, mode, baseHistory, model):
                    let displayName = displayName(for: contexts)
                    submittedPrompt = "\(displayName) - \(prompt)"
                    resultFileQuestionMode = mode
                    updateResponseProviderTitle(using: model)
                    let willUseFilesAPI = shouldUseFilesAPI(for: contexts)
                    uploadProgress = willUseFilesAPI ? 0 : nil
                    loadingStatusText = willUseFilesAPI ? "파일 업로드 중 0%" : "파일 읽는 중"
                    let fileRequests = try await loadFileRequests(from: contexts, prompt: prompt)
                    loadingStatusText = "Gemini 분석 중"
                    uploadProgress = nil
                    let fileContent = GeminiConversationContent.userFileParts(
                        prompt: prompt,
                        fileParts: fileRequests.flatMap(\.parts)
                    )
                    let response = try await geminiClient.generateText(
                        contents: buildRequestContents(baseHistory: baseHistory, userContent: fileContent),
                        model: model
                    )
                    conversationHistory = baseHistory + [fileContent, GeminiConversationContent.modelText(response)]
                    activeFileConversationModel = model
                    resultDroppedFileURL = contexts.first?.url
                    canOpenDroppedFile = true
                    loadingStatusText = "답변 정리 중"
                    responseText = response
                }

                displayedResponseText = ""
                errorMessage = nil
            } catch where isCancellationError(error) {
                return
            } catch {
                setError(error)
            }

            isLoading = false
            loadingStatusText = nil
            uploadProgress = nil
            requestTask = nil
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

    private func resolvedModelForTextPrompt(_ prompt: String) -> NudgeSettingsStore.GeminiModel {
        switch settingsStore.selectedModel {
        case .auto:
            return prompt.count >= longTextPromptThreshold ? .advanced : .fast
        case .fast, .advanced:
            return settingsStore.selectedModel
        }
    }

    private func resolvedModelForFileFollowUp(prompt: String) -> NudgeSettingsStore.GeminiModel {
        switch settingsStore.selectedModel {
        case .auto:
            return activeFileConversationModel ?? resolvedModelForTextPrompt(prompt)
        case .fast, .advanced:
            return settingsStore.selectedModel
        }
    }

    private func resolvedModelForFileContexts(_ contexts: [DroppedFileContext]) -> NudgeSettingsStore.GeminiModel {
        switch settingsStore.selectedModel {
        case .auto:
            let shouldUseAdvanced = contexts.count > 1
                || contexts.contains { $0.payloadKind.prefersAdvancedModel }
                || totalFileByteCount(for: contexts) >= largeFileByteThreshold
            return shouldUseAdvanced ? .advanced : .fast
        case .fast, .advanced:
            return settingsStore.selectedModel
        }
    }

    private func updateResponseProviderTitle(using model: NudgeSettingsStore.GeminiModel) {
        if settingsStore.selectedModel == .auto {
            responseProviderTitle = "Gemini · 자동 · \(model.title) 사용"
        } else {
            responseProviderTitle = "Gemini · \(model.title)"
        }
    }

    private func resetResponseOutput() {
        cancelTypingResponse()
        responseText = ""
        displayedResponseText = ""
        loadingStatusText = nil
        uploadProgress = nil
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
            case .fileUploadFailed, .fileProcessingTimeout:
                return .genericError
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

    private func isCancellationError(_ error: Error) -> Bool {
        if error is CancellationError {
            return true
        }

        if let urlError = error as? URLError,
           urlError.code == .cancelled {
            return true
        }

        return (error as NSError).code == NSUserCancelledError
    }

    private func buildRequestContents(
        baseHistory: [GeminiConversationContent],
        userContent: GeminiConversationContent
    ) -> [GeminiConversationContent] {
        let systemInstructions = [
            settingsStore.textSystemPrompt,
            settingsStore.responseTone.instruction
        ]
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }
        .joined(separator: "\n\n")

        guard !systemInstructions.isEmpty else {
            return baseHistory + [userContent]
        }

        return [
            GeminiConversationContent.userText("시스템 지침:\n\(systemInstructions)")
        ] + baseHistory + [userContent]
    }

    private func cancelTypingResponse() {
        typingTask?.cancel()
        typingTask = nil
    }

    private func showToast(_ message: String) {
        toastTask?.cancel()
        toastMessage = message

        toastTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 1_450_000_000)
            guard !Task.isCancelled else { return }
            self?.toastMessage = nil
            self?.toastTask = nil
        }
    }

    private func dismissToast() {
        toastTask?.cancel()
        toastTask = nil
        toastMessage = nil
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

    private func loadFileRequests(from contexts: [DroppedFileContext], prompt: String) async throws -> [DropFileRequest] {
        var remainingTextCharacterLimit = totalExtractedTextCharacterLimit
        let shouldUploadMediaFiles = shouldUseFilesAPI(for: contexts)
        let totalUploadBytes = shouldUploadMediaFiles ? totalFilesAPIUploadByteCount(for: contexts) : 0
        var completedUploadBytes: Int64 = 0
        var requests: [DropFileRequest] = []

        for context in contexts {
            let currentFileByteCount = fileByteCount(for: context.url)
            let completedUploadBytesBeforeCurrentFile = completedUploadBytes
            let request = try await loadFileRequest(
                from: context,
                prompt: prompt,
                remainingTextCharacterLimit: &remainingTextCharacterLimit,
                shouldUploadMediaFiles: shouldUploadMediaFiles,
                onUploadProgress: { [weak self] progress in
                    guard totalUploadBytes > 0 else { return }
                    let currentUploadedBytes = Int64(Double(currentFileByteCount) * progress)
                    let totalProgress = Double(completedUploadBytesBeforeCurrentFile + currentUploadedBytes) / Double(totalUploadBytes)
                    Task { @MainActor in
                        self?.updateUploadProgress(totalProgress)
                    }
                }
            )
            requests.append(request)
            if shouldUploadMediaFiles, context.payloadKind.isFilesAPIUploadCandidate {
                completedUploadBytes += currentFileByteCount
                updateUploadProgress(Double(completedUploadBytes) / Double(max(totalUploadBytes, 1)))
            }
        }

        return requests
    }

    private func loadFileRequest(
        from context: DroppedFileContext,
        prompt: String,
        remainingTextCharacterLimit: inout Int,
        shouldUploadMediaFiles: Bool,
        onUploadProgress: @escaping (Double) -> Void
    ) async throws -> DropFileRequest {
        let didStartAccessing = context.url.startAccessingSecurityScopedResource()
        defer {
            if didStartAccessing {
                context.url.stopAccessingSecurityScopedResource()
            }
        }

        switch context.payloadKind {
        case let .image(mimeType):
            if shouldUploadMediaFiles {
                let uploadedFile = try await geminiClient.uploadFile(
                    url: context.url,
                    mimeType: mimeType,
                    displayName: context.displayName,
                    onProgress: onUploadProgress
                )
                return DropFileRequest(parts: [
                    .fileData(uri: uploadedFile.uri, mimeType: uploadedFile.mimeType)
                ])
            }

            return DropFileRequest(parts: [
                .inlineData(try Data(contentsOf: context.url).base64EncodedString(), mimeType: mimeType)
            ])
        case .pdf:
            try validatePDFLimits(for: context)
            if shouldUploadMediaFiles {
                let uploadedFile = try await geminiClient.uploadFile(
                    url: context.url,
                    mimeType: "application/pdf",
                    displayName: context.displayName,
                    onProgress: onUploadProgress
                )
                return DropFileRequest(parts: [
                    .fileData(uri: uploadedFile.uri, mimeType: uploadedFile.mimeType)
                ])
            }

            return DropFileRequest(parts: [
                .inlineData(try Data(contentsOf: context.url).base64EncodedString(), mimeType: "application/pdf")
            ])
        case .text, .code:
            let extractionLimit = min(NudgeFileTextExtractor.perFileCharacterLimit, remainingTextCharacterLimit)
            return try textDropFileRequest(from: context, remainingTextCharacterLimit: &remainingTextCharacterLimit) {
                try NudgeFileTextExtractor.extractPlainText(from: context.url, limit: extractionLimit)
            }
        case let .office(kind):
            let extractionLimit = min(NudgeFileTextExtractor.perFileCharacterLimit, remainingTextCharacterLimit)
            return try textDropFileRequest(from: context, remainingTextCharacterLimit: &remainingTextCharacterLimit) {
                try NudgeFileTextExtractor.extractOfficeText(from: context.url, kind: kind, limit: extractionLimit)
            }
        }
    }

    private func textDropFileRequest(
        from context: DroppedFileContext,
        remainingTextCharacterLimit: inout Int,
        extract: () throws -> NudgeExtractedFileText
    ) throws -> DropFileRequest {
        guard remainingTextCharacterLimit > 0 else {
            return DropFileRequest(parts: [
                .text("""
                [파일: \(context.displayName)]
                파일 타입: \(context.payloadKind.kindLabel)
                내용은 전체 요청 크기 제한으로 포함되지 않았습니다.
                """)
            ])
        }

        let extractedText = try extract()
        remainingTextCharacterLimit = max(0, remainingTextCharacterLimit - extractedText.text.count)
        let truncationNotice = extractedText.isTruncated ? "\n\n참고: 이 파일은 길이가 길어 일부 내용만 포함되었습니다." : ""

        return DropFileRequest(parts: [
            .text("""
            [파일: \(context.displayName)]
            파일 타입: \(context.payloadKind.kindLabel)
            추출 내용:
            \(extractedText.text)\(truncationNotice)
            """)
        ])
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

        if let officeKind = officeDocumentKind(for: pathExtension) {
            return .office(kind: officeKind)
        }

        if codeFileExtensions.contains(pathExtension) {
            return .code(fileExtension: pathExtension)
        }

        if textFileExtensions.contains(pathExtension) {
            return .text(fileExtension: pathExtension)
        }

        if let type = UTType(filenameExtension: pathExtension),
           type.conforms(to: .text) {
            return .text(fileExtension: pathExtension)
        }

        return nil
    }

    private var textFileExtensions: Set<String> {
        ["txt", "md"]
    }

    private var codeFileExtensions: Set<String> {
        ["swift", "kt", "js", "ts", "tsx", "jsx", "py", "java", "c", "cpp", "h", "hpp", "json", "xml", "html", "css", "yml", "yaml"]
    }

    private func officeDocumentKind(for pathExtension: String) -> NudgeOfficeDocumentKind? {
        switch pathExtension {
        case "docx":
            .word
        case "pptx":
            .powerPoint
        case "xlsx":
            .excel
        default:
            nil
        }
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
            clearDroppedFileState()
            dragPromptIconName = "exclamationmark.triangle"
            dragPromptText = "지원하지 않는 파일입니다"
            return
        }

        updateDroppedFilesPreview(contexts)
        dragPromptIconName = dragIconName(for: contexts)
        dragPromptText = dropPromptText(for: contexts)
    }

    private func showUnsupportedDrop(displayName: String) {
        clearDroppedFileState()
        prompt = ""
        submittedPrompt = displayName
        responseProviderTitle = "Nudge"
        resetResponseOutput()
        errorMessage = "현재는 이미지, PDF, 문서, 텍스트, 코드 파일을 지원합니다."
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
        selectedFileQuestionMode = .summary
        resultFileQuestionMode = nil
        filePromptNoticeText = nil
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
        selectedFileQuestionMode = contexts.count > 1 ? .compare : .summary
        filePromptNoticeText = filePromptNotice(for: contexts)
    }

    private func fileSizeText(for url: URL) -> String {
        let byteCount = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) ?? 0
        guard byteCount > 0 else { return "크기 알 수 없음" }

        return ByteCountFormatter.string(fromByteCount: byteCount, countStyle: .file)
    }

    private func totalFileSizeText(for contexts: [DroppedFileContext]) -> String {
        let totalSize = totalFileByteCount(for: contexts)

        guard totalSize > 0 else { return "크기 알 수 없음" }
        return ByteCountFormatter.string(fromByteCount: totalSize, countStyle: .file)
    }

    private func totalFileByteCount(for contexts: [DroppedFileContext]) -> Int64 {
        contexts.reduce(Int64(0)) { partialResult, context in
            partialResult + fileByteCount(for: context.url)
        }
    }

    private func fileByteCount(for url: URL) -> Int64 {
        (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) ?? 0
    }

    private func shouldUseFilesAPI(for contexts: [DroppedFileContext]) -> Bool {
        totalFileByteCount(for: contexts) > inlineDataByteThreshold
    }

    private func totalFilesAPIUploadByteCount(for contexts: [DroppedFileContext]) -> Int64 {
        contexts.reduce(Int64(0)) { partialResult, context in
            guard context.payloadKind.isFilesAPIUploadCandidate else { return partialResult }
            return partialResult + fileByteCount(for: context.url)
        }
    }

    private func updateUploadProgress(_ progress: Double) {
        let clampedProgress = min(1, max(0, progress))
        uploadProgress = clampedProgress
        loadingStatusText = "파일 업로드 중 \(Int((clampedProgress * 100).rounded()))%"
    }

    private func filePromptBlockingMessage(for contexts: [DroppedFileContext]) -> String? {
        contexts.first { context in
            guard case .pdf = context.payloadKind else { return false }
            return (try? validatePDFLimits(for: context)) == nil
        }.map { _ in
            NudgeFileProcessingError.pdfLimitExceeded.localizedDescription
        }
    }

    private func filePromptNotice(for contexts: [DroppedFileContext]) -> String? {
        if let blockingMessage = filePromptBlockingMessage(for: contexts) {
            return blockingMessage
        }

        if shouldUseFilesAPI(for: contexts),
           contexts.contains(where: { $0.payloadKind.isFilesAPIUploadCandidate }) {
            return "큰 파일입니다. 업로드 후 분석합니다."
        }

        return nil
    }

    private func validatePDFLimits(for context: DroppedFileContext) throws {
        guard case .pdf = context.payloadKind else { return }
        guard fileByteCount(for: context.url) <= maxPDFByteCount else {
            throw NudgeFileProcessingError.pdfLimitExceeded
        }

        if let document = PDFDocument(url: context.url),
           document.pageCount > maxPDFPageCount {
            throw NudgeFileProcessingError.pdfLimitExceeded
        }
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
        let kinds = Set(contexts.map { $0.payloadKind.collectionKind })
        guard kinds.count == 1, let kind = kinds.first else {
            return .mixed
        }

        return kind
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
        mode: NudgeFileQuestionMode,
        userQuestion: String
    ) -> String {
        guard contexts.count > 1 else {
            return contexts[0].payloadKind.requestPrompt(
                settingsStore: settingsStore,
                mode: mode,
                userQuestion: userQuestion
            )
        }

        let question = userQuestion.trimmingCharacters(in: .whitespacesAndNewlines)
        let kind = collectionKind(for: contexts)
        let fallbackQuestion = question.isEmpty ? mode.defaultQuestion(for: kind) : question
        let basePrompt: String

        switch kind {
        case .image:
            basePrompt = settingsStore.imageAnalysisPrompt
        case .pdf:
            basePrompt = settingsStore.pdfAnalysisPrompt
        case .code:
            basePrompt = "코드 파일의 구조, 핵심 동작, 개선할 점을 한국어로 분석해 주세요."
        case .text:
            basePrompt = "텍스트 파일의 핵심 내용과 중요한 포인트를 한국어로 정리해 주세요."
        case .word, .powerPoint, .excel:
            basePrompt = "문서 내용을 한국어로 분석해 핵심 요약, 주요 내용, 필요한 후속 작업을 정리해 주세요."
        case .mixed:
            basePrompt = "여러 종류의 파일 내용을 함께 분석해 핵심 요약, 공통점, 차이점, 필요한 후속 작업을 정리해 주세요."
        }

        return [
            "여러 파일을 함께 분석해 주세요. 파일 간 공통점, 차이점, 연결되는 맥락이 있으면 함께 정리해 주세요.",
            basePrompt,
            mode.instruction(for: kind),
            "사용자 요청: \(fallbackQuestion)"
        ]
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }
        .joined(separator: "\n\n")
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
    let parts: [GeminiConversationPart]
}

private struct DroppedFileContext {
    let url: URL
    let displayName: String
    let payloadKind: DropFilePayloadKind
}

private enum LastRequest {
    case text(prompt: String, baseHistory: [GeminiConversationContent], model: NudgeSettingsStore.GeminiModel)
    case fileFollowUp(prompt: String, baseHistory: [GeminiConversationContent], model: NudgeSettingsStore.GeminiModel)
    case file(
        contexts: [DroppedFileContext],
        prompt: String,
        mode: NudgeFileQuestionMode,
        baseHistory: [GeminiConversationContent],
        model: NudgeSettingsStore.GeminiModel
    )
}

private enum DropFileCollectionKind {
    case image
    case pdf
    case text
    case code
    case word
    case powerPoint
    case excel
    case mixed

    var kindLabel: String {
        switch self {
        case .image:
            "이미지"
        case .pdf:
            "PDF"
        case .text:
            "텍스트"
        case .code:
            "코드"
        case .word:
            "Word"
        case .powerPoint:
            "PowerPoint"
        case .excel:
            "Excel"
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
        case .text:
            "doc.plaintext"
        case .code:
            "curlybraces"
        case .word:
            "doc.text"
        case .powerPoint:
            "rectangle.on.rectangle"
        case .excel:
            "tablecells"
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
        case .text:
            "doc.plaintext"
        case .code:
            "curlybraces"
        case .word:
            "doc.text"
        case .powerPoint:
            "rectangle.on.rectangle"
        case .excel:
            "tablecells"
        case .mixed:
            "square.stack.3d.up"
        }
    }
}

private extension NudgeFileQuestionMode {
    func instruction(for kind: DropFileCollectionKind) -> String {
        switch self {
        case .summary:
            return "분석 목적: 파일의 핵심 내용을 짧고 명확하게 요약해 주세요. 중요한 결론과 사용자가 바로 이해해야 할 포인트를 우선해 주세요."
        case .analysis:
            return "분석 목적: 파일의 구조, 의미, 중요한 패턴, 놓치기 쉬운 포인트를 깊게 분석해 주세요. 필요한 경우 근거를 함께 정리해 주세요."
        case .compare:
            if kind == .mixed {
                return "분석 목적: 여러 파일 또는 파일 안의 주요 요소를 비교해 공통점, 차이점, 연결되는 맥락을 정리해 주세요."
            }

            return "분석 목적: 파일 안의 주요 요소를 비교해 차이점, 공통점, 우선순위가 드러나게 정리해 주세요."
        case .extract:
            switch kind {
            case .image:
                return "분석 목적: 이미지에서 읽을 수 있는 텍스트, 핵심 객체, 중요한 시각 정보를 추출해 정리해 주세요."
            case .pdf, .word, .powerPoint, .excel:
                return "분석 목적: 문서에서 핵심 문장, 표, 수치, 액션 아이템, 결정 사항처럼 재사용 가능한 정보를 추출해 주세요."
            case .code:
                return "분석 목적: 코드에서 핵심 함수, 의존성, 위험 지점, 개선 포인트를 추출해 주세요."
            case .text, .mixed:
                return "분석 목적: 파일에서 중요한 키워드, 항목, 액션 아이템, 재사용 가능한 정보를 추출해 주세요."
            }
        case .feedback:
            switch kind {
            case .image:
                return "분석 목적: 디자인, 구도, 색감, 가독성, 사용자 인상 관점에서 개선점과 피드백을 제안해 주세요."
            case .code:
                return "분석 목적: 코드 품질, 구조, 안정성, 유지보수성 관점에서 개선 피드백을 제안해 주세요."
            default:
                return "분석 목적: 문서 구성, 명확성, 설득력, 누락된 부분, 개선 방향을 중심으로 피드백을 제안해 주세요."
            }
        }
    }

    func defaultQuestion(for kind: DropFileCollectionKind) -> String {
        switch self {
        case .summary:
            return "핵심만 요약해 주세요."
        case .analysis:
            return "중요한 구조와 의미를 중심으로 분석해 주세요."
        case .compare:
            return kind == .mixed ? "파일들을 비교해 공통점과 차이점을 정리해 주세요." : "주요 요소를 비교해 정리해 주세요."
        case .extract:
            switch kind {
            case .image:
                return "이미지에서 중요한 정보와 읽을 수 있는 텍스트를 추출해 주세요."
            case .code:
                return "코드에서 핵심 흐름, 위험 지점, 개선 포인트를 추출해 주세요."
            default:
                return "중요한 정보, 액션 아이템, 표나 수치가 있으면 추출해 주세요."
            }
        case .feedback:
            return "개선할 점과 구체적인 피드백을 제안해 주세요."
        }
    }
}

private enum DropFilePayloadKind {
    case image(mimeType: String)
    case pdf
    case text(fileExtension: String)
    case code(fileExtension: String)
    case office(kind: NudgeOfficeDocumentKind)

    func requestPrompt(
        settingsStore: NudgeSettingsStore,
        mode: NudgeFileQuestionMode,
        userQuestion: String
    ) -> String {
        let question = userQuestion.trimmingCharacters(in: .whitespacesAndNewlines)
        let fallbackQuestion = question.isEmpty ? mode.defaultQuestion(for: collectionKind) : question

        switch self {
        case .image:
            return [settingsStore.imageAnalysisPrompt, mode.instruction(for: collectionKind), "사용자 요청: \(fallbackQuestion)"]
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .joined(separator: "\n\n")
        case .pdf:
            return [settingsStore.pdfAnalysisPrompt, mode.instruction(for: collectionKind), "사용자 요청: \(fallbackQuestion)"]
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .joined(separator: "\n\n")
        case .text:
            return ["텍스트 파일의 내용을 바탕으로 분석해 주세요.", mode.instruction(for: collectionKind), "사용자 요청: \(fallbackQuestion)"]
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .joined(separator: "\n\n")
        case .code:
            return ["코드 파일의 내용을 바탕으로 구조, 동작, 개선점을 분석해 주세요.", mode.instruction(for: collectionKind), "사용자 요청: \(fallbackQuestion)"]
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .joined(separator: "\n\n")
        case .office:
            return ["문서에서 추출한 텍스트를 바탕으로 분석해 주세요.", mode.instruction(for: collectionKind), "사용자 요청: \(fallbackQuestion)"]
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
        case .text:
            "텍스트 파일을 놓아주세요"
        case .code:
            "코드 파일을 놓아주세요"
        case let .office(kind):
            switch kind {
            case .word:
                "Word 문서를 놓아주세요"
            case .powerPoint:
                "프레젠테이션을 놓아주세요"
            case .excel:
                "스프레드시트를 놓아주세요"
            }
        }
    }

    var isFilesAPIUploadCandidate: Bool {
        switch self {
        case .image, .pdf:
            true
        case .text, .code, .office:
            false
        }
    }

    var iconName: String {
        switch self {
        case .image:
            "photo.badge.arrow.down"
        case .pdf:
            "doc.text.magnifyingglass"
        case .text:
            "doc.plaintext"
        case .code:
            "curlybraces"
        case let .office(kind):
            switch kind {
            case .word:
                "doc.text"
            case .powerPoint:
                "rectangle.on.rectangle"
            case .excel:
                "tablecells"
            }
        }
    }

    var previewIconName: String {
        switch self {
        case .image:
            "photo"
        case .pdf:
            "doc.text.magnifyingglass"
        case .text:
            "doc.plaintext"
        case .code:
            "curlybraces"
        case let .office(kind):
            switch kind {
            case .word:
                "doc.text"
            case .powerPoint:
                "rectangle.on.rectangle"
            case .excel:
                "tablecells"
            }
        }
    }

    var kindLabel: String {
        switch self {
        case .image:
            "이미지"
        case .pdf:
            "PDF"
        case .text:
            "텍스트"
        case .code:
            "코드"
        case let .office(kind):
            switch kind {
            case .word:
                "Word"
            case .powerPoint:
                "PowerPoint"
            case .excel:
                "Excel"
            }
        }
    }

    var prefersAdvancedModel: Bool {
        switch self {
        case .image, .text:
            false
        case .pdf, .code, .office:
            true
        }
    }

    var collectionKind: DropFileCollectionKind {
        switch self {
        case .image:
            .image
        case .pdf:
            .pdf
        case .text:
            .text
        case .code:
            .code
        case let .office(kind):
            switch kind {
            case .word:
                .word
            case .powerPoint:
                .powerPoint
            case .excel:
                .excel
            }
        }
    }
}
