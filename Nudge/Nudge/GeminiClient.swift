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
            }
        }
    }

    private let settingsStore: NudgeSettingsStore
    private let session: URLSession

    init(settingsStore: NudgeSettingsStore, session: URLSession = .shared) {
        self.settingsStore = settingsStore
        self.session = session
    }

    func generateText(prompt: String) async throws -> String {
        try await generateText(contents: [
            GeminiConversationContent.userText(prompt)
        ])
    }

    func generateText(contents: [GeminiConversationContent]) async throws -> String {
        try await generateContent(contents: contents.map(GeminiContent.init))
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

    private func generateContent(contents: [GeminiContent]) async throws -> String {
        let apiKey = try resolveAPIKey()

        let model = settingsStore.selectedModel.rawValue
        guard let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent") else {
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

}

enum GeminiConversationPart {
    case text(String)
    case inlineData(String, mimeType: String)
}

private struct GeminiRequest: Encodable {
    let contents: [GeminiContent]
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

    nonisolated init(text: String) {
        self.text = text
        self.inlineData = nil
    }

    nonisolated init(inlineData: GeminiInlineData) {
        self.text = nil
        self.inlineData = inlineData
    }

    nonisolated init(conversationPart: GeminiConversationPart) {
        switch conversationPart {
        case let .text(text):
            self.init(text: text)
        case let .inlineData(data, mimeType):
            self.init(inlineData: GeminiInlineData(mimeType: mimeType, data: data))
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
