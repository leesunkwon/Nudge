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
                "Gemini API 키가 설정되지 않았습니다. Secrets.xcconfig의 GEMINI_API_KEY 값을 확인해 주세요."
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

    private let model = "gemini-3.5-flash"
    private let session: URLSession

    nonisolated init(session: URLSession = .shared) {
        self.session = session
    }

    func generateText(prompt: String) async throws -> String {
        try await generateText(contents: [
            GeminiConversationContent(role: .user, text: prompt)
        ])
    }

    func generateText(contents: [GeminiConversationContent]) async throws -> String {
        let apiKey = try resolveAPIKey()

        guard let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent") else {
            throw GeminiError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(GeminiRequest(contents: contents.map(GeminiContent.init)))

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
    let text: String
}

private struct GeminiRequest: Encodable {
    let contents: [GeminiContent]
}

private struct GeminiContent: Codable {
    let role: String?
    let parts: [GeminiPart]

    init(role: String? = nil, parts: [GeminiPart]) {
        self.role = role
        self.parts = parts
    }

    init(conversationContent: GeminiConversationContent) {
        self.role = conversationContent.role.rawValue
        self.parts = [
            GeminiPart(text: conversationContent.text)
        ]
    }
}

private struct GeminiPart: Codable {
    let text: String
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
