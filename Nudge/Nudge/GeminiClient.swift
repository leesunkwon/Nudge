//
//  GeminiClient.swift
//  Nudge
//
//  Created by Codex on 6/16/26.
//

import Foundation

struct GeminiClient {
    enum GeminiError: LocalizedError {
        case missingAPIKey
        case invalidURL
        case invalidResponse
        case apiError(String)
        case emptyResponse
        case fileUploadFailed
        case fileProcessingTimeout

        var errorDescription: String? {
            switch self {
            case .missingAPIKey:
                "설정에서 Gemini API Key를 입력해 주세요."
            case .invalidURL:
                "Gemini 요청 URL을 만들 수 없습니다."
            case .invalidResponse:
                "Gemini 응답을 확인할 수 없습니다."
            case let .apiError(message):
                message
            case .emptyResponse:
                "Gemini 응답이 비어 있습니다."
            case .fileUploadFailed:
                "파일 업로드에 실패했습니다. 잠시 후 다시 시도해 주세요."
            case .fileProcessingTimeout:
                "파일 처리 시간이 오래 걸리고 있습니다. 잠시 후 다시 시도해 주세요."
            }
        }
    }

    private let settingsStore: NudgeSettingsStore
    private let session: URLSession

    init(settingsStore: NudgeSettingsStore, session: URLSession = .shared) {
        self.settingsStore = settingsStore
        self.session = session
    }

    func generateText(
        prompt: String,
        model: NudgeSettingsStore.GeminiModel? = nil
    ) async throws -> String {
        try await generateText(contents: [
            GeminiConversationContent.userText(prompt)
        ], model: model)
    }

    func generateText(
        contents: [GeminiConversationContent],
        model: NudgeSettingsStore.GeminiModel? = nil
    ) async throws -> String {
        try await generateContent(
            contents: contents.map(GeminiContent.init),
            model: model ?? settingsStore.selectedModel
        )
    }

    func analyzeFile(data: Data, mimeType: String, prompt: String) async throws -> String {
        try await generateText(contents: [
            GeminiConversationContent.userFile(
                prompt: prompt,
                data: data,
                mimeType: mimeType
            )
        ])
    }

    func uploadFile(
        url fileURL: URL,
        mimeType: String,
        displayName: String
    ) async throws -> GeminiUploadedFile {
        let apiKey = try resolveAPIKey()
        let fileData = try Data(contentsOf: fileURL)

        guard let uploadStartURL = URL(string: "https://generativelanguage.googleapis.com/upload/v1beta/files") else {
            throw GeminiError.invalidURL
        }

        var startRequest = URLRequest(url: uploadStartURL)
        startRequest.httpMethod = "POST"
        startRequest.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
        startRequest.setValue("resumable", forHTTPHeaderField: "X-Goog-Upload-Protocol")
        startRequest.setValue("start", forHTTPHeaderField: "X-Goog-Upload-Command")
        startRequest.setValue(String(fileData.count), forHTTPHeaderField: "X-Goog-Upload-Header-Content-Length")
        startRequest.setValue(mimeType, forHTTPHeaderField: "X-Goog-Upload-Header-Content-Type")
        startRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        startRequest.httpBody = try JSONEncoder().encode(GeminiFileUploadStartRequest(file: .init(displayName: displayName)))

        let (_, startResponse) = try await session.data(for: startRequest)
        guard let startHTTPResponse = startResponse as? HTTPURLResponse,
              (200..<300).contains(startHTTPResponse.statusCode),
              let uploadURLString = startHTTPResponse.value(forHTTPHeaderField: "x-goog-upload-url"),
              let uploadURL = URL(string: uploadURLString) else {
            throw GeminiError.fileUploadFailed
        }

        var uploadRequest = URLRequest(url: uploadURL)
        uploadRequest.httpMethod = "POST"
        uploadRequest.setValue(String(fileData.count), forHTTPHeaderField: "Content-Length")
        uploadRequest.setValue("0", forHTTPHeaderField: "X-Goog-Upload-Offset")
        uploadRequest.setValue("upload, finalize", forHTTPHeaderField: "X-Goog-Upload-Command")
        uploadRequest.httpBody = fileData

        let (uploadData, uploadResponse) = try await session.data(for: uploadRequest)
        guard let uploadHTTPResponse = uploadResponse as? HTTPURLResponse,
              (200..<300).contains(uploadHTTPResponse.statusCode) else {
            throw GeminiError.fileUploadFailed
        }

        let uploadedFile = try JSONDecoder().decode(GeminiFileUploadResponse.self, from: uploadData).file
        return try await waitForUploadedFile(uploadedFile, apiKey: apiKey)
    }

    private func generateContent(
        contents: [GeminiContent],
        model: NudgeSettingsStore.GeminiModel
    ) async throws -> String {
        let apiKey = try resolveAPIKey()

        guard let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(model.requestModelName):generateContent") else {
            throw GeminiError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(GeminiRequest(contents: contents))

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw GeminiError.invalidResponse
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            let errorResponse = try? JSONDecoder().decode(GeminiErrorResponse.self, from: data)
            throw GeminiError.apiError(errorResponse?.error.message ?? "Gemini 요청에 실패했습니다. 다시 시도해 주세요.")
        }

        let geminiResponse = try JSONDecoder().decode(GeminiResponse.self, from: data)
        guard let text = geminiResponse.candidates.first?.content.parts.first?.text,
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw GeminiError.emptyResponse
        }

        return text
    }

    private func waitForUploadedFile(
        _ file: GeminiUploadedFile,
        apiKey: String
    ) async throws -> GeminiUploadedFile {
        guard file.state != .failed else {
            throw GeminiError.fileUploadFailed
        }

        guard file.state == .processing else {
            return file
        }

        var currentFile = file
        for _ in 0..<10 {
            try await Task.sleep(nanoseconds: 1_000_000_000)
            currentFile = try await fetchUploadedFile(name: file.name, apiKey: apiKey)
            if currentFile.state == .failed {
                throw GeminiError.fileUploadFailed
            }

            if currentFile.state != .processing {
                return currentFile
            }
        }

        throw GeminiError.fileProcessingTimeout
    }

    private func fetchUploadedFile(name: String, apiKey: String) async throws -> GeminiUploadedFile {
        guard let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/\(name)") else {
            throw GeminiError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            throw GeminiError.fileUploadFailed
        }

        return try JSONDecoder().decode(GeminiUploadedFile.self, from: data)
    }

    private func resolveAPIKey() throws -> String {
        if let keychainKey = settingsStore.loadAPIKey(),
           !keychainKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return keychainKey
        }

        if let environmentKey = ProcessInfo.processInfo.environment["GEMINI_API_KEY"],
           !environmentKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return environmentKey
        }

        if let infoPlistKey = Bundle.main.object(forInfoDictionaryKey: "GeminiAPIKey") as? String,
           !infoPlistKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return infoPlistKey
        }

        throw GeminiError.missingAPIKey
    }
}

struct GeminiConversationContent {
    enum Role: String {
        case user
        case model
    }

    let role: Role
    let parts: [GeminiConversationPart]

    init(role: Role, parts: [GeminiConversationPart]) {
        self.role = role
        self.parts = parts
    }

    static func userText(_ text: String) -> GeminiConversationContent {
        GeminiConversationContent(role: .user, parts: [.text(text)])
    }

    static func modelText(_ text: String) -> GeminiConversationContent {
        GeminiConversationContent(role: .model, parts: [.text(text)])
    }

    static func userFile(prompt: String, data: Data, mimeType: String) -> GeminiConversationContent {
        GeminiConversationContent(
            role: .user,
            parts: [
                .text(prompt),
                .inlineData(data.base64EncodedString(), mimeType: mimeType)
            ]
        )
    }

    static func userFiles(prompt: String, files: [(data: Data, mimeType: String)]) -> GeminiConversationContent {
        GeminiConversationContent(
            role: .user,
            parts: [.text(prompt)] + files.map { file in
                .inlineData(file.data.base64EncodedString(), mimeType: file.mimeType)
            }
        )
    }

    static func userFileParts(prompt: String, fileParts: [GeminiConversationPart]) -> GeminiConversationContent {
        GeminiConversationContent(
            role: .user,
            parts: [.text(prompt)] + fileParts
        )
    }
}

enum GeminiConversationPart {
    case text(String)
    case inlineData(String, mimeType: String)
    case fileData(uri: String, mimeType: String)
}

struct GeminiUploadedFile: Decodable {
    enum State: String, Decodable {
        case active = "ACTIVE"
        case processing = "PROCESSING"
        case failed = "FAILED"
        case unknown

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            let rawValue = try container.decode(String.self)
            self = State(rawValue: rawValue) ?? .unknown
        }
    }

    let name: String
    let uri: String
    let mimeType: String
    let state: State

    enum CodingKeys: String, CodingKey {
        case name
        case uri
        case mimeType
        case state
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        uri = try container.decode(String.self, forKey: .uri)
        mimeType = try container.decode(String.self, forKey: .mimeType)
        state = try container.decodeIfPresent(State.self, forKey: .state) ?? .active
    }
}

private struct GeminiRequest: Encodable {
    let contents: [GeminiContent]
}

private struct GeminiFileUploadStartRequest: Encodable {
    struct File: Encodable {
        let displayName: String
    }

    let file: File
}

private struct GeminiFileUploadResponse: Decodable {
    let file: GeminiUploadedFile
}

private struct GeminiContent: Codable {
    let role: String?
    let parts: [GeminiPart]

    nonisolated init(role: String? = nil, parts: [GeminiPart]) {
        self.role = role
        self.parts = parts
    }

    nonisolated init(conversationContent: GeminiConversationContent) {
        self.role = conversationContent.role.rawValue
        self.parts = conversationContent.parts.map(GeminiPart.init)
    }
}

private struct GeminiPart: Codable {
    let text: String?
    let inlineData: GeminiInlineData?
    let fileData: GeminiFileData?

    nonisolated init(text: String) {
        self.text = text
        self.inlineData = nil
        self.fileData = nil
    }

    nonisolated init(inlineData: GeminiInlineData) {
        self.text = nil
        self.inlineData = inlineData
        self.fileData = nil
    }

    nonisolated init(fileData: GeminiFileData) {
        self.text = nil
        self.inlineData = nil
        self.fileData = fileData
    }

    nonisolated init(conversationPart: GeminiConversationPart) {
        switch conversationPart {
        case let .text(text):
            self.init(text: text)
        case let .inlineData(data, mimeType):
            self.init(inlineData: GeminiInlineData(mimeType: mimeType, data: data))
        case let .fileData(uri, mimeType):
            self.init(fileData: GeminiFileData(mimeType: mimeType, fileURI: uri))
        }
    }
}

private struct GeminiInlineData: Codable {
    let mimeType: String
    let data: String

    nonisolated init(mimeType: String, data: String) {
        self.mimeType = mimeType
        self.data = data
    }
}

private struct GeminiFileData: Codable {
    let mimeType: String
    let fileURI: String

    enum CodingKeys: String, CodingKey {
        case mimeType
        case fileURI = "fileUri"
    }
}

private struct GeminiResponse: Decodable {
    let candidates: [GeminiCandidate]
}

private struct GeminiCandidate: Decodable {
    let content: GeminiContent
}

private struct GeminiErrorResponse: Decodable {
    let error: GeminiAPIError
}

private struct GeminiAPIError: Decodable {
    let message: String
}
