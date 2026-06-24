//
//  NudgeSettingsStore.swift
//  Nudge
//
//  Created by Codex on 6/16/26.
//

import Combine
import Foundation
import SwiftUI

@MainActor
final class NudgeSettingsStore: ObservableObject {
    enum GeminiModel: String, CaseIterable, Identifiable {
        case auto = "auto"
        case fast = "gemini-3.1-flash-lite"
        case advanced = "gemini-3.1-pro-preview"

        var id: String { rawValue }

        var title: String {
            switch self {
            case .auto:
                "자동"
            case .fast:
                "빠름"
            case .advanced:
                "고급"
            }
        }

        var modelName: String {
            if self == .auto {
                return "상황에 따라 자동 선택"
            }

            return rawValue
        }

        var requestModelName: String {
            switch self {
            case .auto:
                GeminiModel.fast.rawValue
            case .fast, .advanced:
                rawValue
            }
        }

        var description: String {
            switch self {
            case .auto:
                "질문과 파일 조건에 맞춰 모델 선택"
            case .fast:
                "빠른 응답과 일반 질문에 적합"
            case .advanced:
                "복잡한 분석, 코드, 긴 문서 처리에 적합"
            }
        }

        static func storedValue(_ rawValue: String?) -> GeminiModel {
            switch rawValue {
            case GeminiModel.auto.rawValue:
                .auto
            case GeminiModel.advanced.rawValue:
                .advanced
            case GeminiModel.fast.rawValue:
                .fast
            default:
                .auto
            }
        }
    }

    enum AnimationSpeed: String, CaseIterable, Identifiable {
        case smooth
        case fast

        var id: String { rawValue }

        var title: String {
            switch self {
            case .smooth:
                "부드럽게"
            case .fast:
                "빠르게"
            }
        }

        var frameDuration: TimeInterval {
            switch self {
            case .smooth:
                0.36
            case .fast:
                0.22
            }
        }

        var expandDuration: TimeInterval {
            switch self {
            case .smooth:
                0.46
            case .fast:
                0.30
            }
        }

        var swiftUIAnimation: Animation {
            switch self {
            case .smooth:
                .timingCurve(0.25, 0.1, 0.25, 1.0, duration: 0.34)
            case .fast:
                .timingCurve(0.25, 0.1, 0.25, 1.0, duration: 0.22)
            }
        }
    }

    enum GlowIntensity: String, CaseIterable, Identifiable {
        case low
        case normal
        case high

        var id: String { rawValue }

        var title: String {
            switch self {
            case .low:
                "낮음"
            case .normal:
                "기본"
            case .high:
                "높음"
            }
        }

        var multiplier: Double {
            switch self {
            case .low:
                0.62
            case .normal:
                1.0
            case .high:
                1.32
            }
        }
    }

    enum NotchTheme: String, CaseIterable, Identifiable {
        case nudgeDefault
        case geminiGlow
        case mono
        case glass

        var id: String { rawValue }

        var title: String {
            switch self {
            case .nudgeDefault:
                "Nudge 기본"
            case .geminiGlow:
                "Gemini Glow"
            case .mono:
                "Mono"
            case .glass:
                "Glass"
            }
        }

        var description: String {
            switch self {
            case .nudgeDefault:
                "블랙 표면과 은은한 멀티컬러 글로우"
            case .geminiGlow:
                "더 선명한 블루/퍼플/핑크 그라데이션"
            case .mono:
                "블랙/화이트 중심의 차분한 단색 스타일"
            case .glass:
                "반투명 유리 질감과 약한 stroke 중심 스타일"
            }
        }
    }

    enum ResponseTone: String, CaseIterable, Identifiable {
        case concise
        case friendly
        case expert

        var id: String { rawValue }

        var title: String {
            switch self {
            case .concise:
                "간단하게"
            case .friendly:
                "친절하게"
            case .expert:
                "전문가처럼"
            }
        }

        var description: String {
            switch self {
            case .concise:
                "핵심만 짧고 명확하게 답변합니다."
            case .friendly:
                "이해하기 쉽게 설명하고 필요한 맥락을 덧붙입니다."
            case .expert:
                "더 깊이 있는 분석과 구체적인 근거를 포함합니다."
            }
        }

        var instruction: String {
            switch self {
            case .concise:
                "답변은 핵심만 짧고 명확하게 작성해 주세요. 불필요한 배경 설명은 줄이고 바로 실행 가능한 내용 위주로 정리해 주세요."
            case .friendly:
                "답변은 이해하기 쉽고 친절하게 작성해 주세요. 필요한 맥락을 덧붙이되 장황하지 않게 정리해 주세요."
            case .expert:
                "답변은 전문가 관점에서 깊이 있게 작성해 주세요. 판단 근거, 주의할 점, 실무적으로 중요한 세부사항을 구체적으로 포함해 주세요."
            }
        }
    }

    @Published var selectedModel: GeminiModel {
        didSet { defaults.set(selectedModel.rawValue, forKey: Keys.selectedModel) }
    }

    @Published var responseTone: ResponseTone {
        didSet { defaults.set(responseTone.rawValue, forKey: Keys.responseTone) }
    }

    @Published var textSystemPrompt: String {
        didSet { defaults.set(textSystemPrompt, forKey: Keys.textSystemPrompt) }
    }

    @Published var imageAnalysisPrompt: String {
        didSet { defaults.set(imageAnalysisPrompt, forKey: Keys.imageAnalysisPrompt) }
    }

    @Published var pdfAnalysisPrompt: String {
        didSet { defaults.set(pdfAnalysisPrompt, forKey: Keys.pdfAnalysisPrompt) }
    }

    @Published var emptyFileQuestionPrompt: String {
        didSet { defaults.set(emptyFileQuestionPrompt, forKey: Keys.emptyFileQuestionPrompt) }
    }

    @Published var hoverActivationPadding: Double {
        didSet { defaults.set(hoverActivationPadding, forKey: Keys.hoverActivationPadding) }
    }

    @Published var hoverCollapseDelay: Double {
        didSet { defaults.set(hoverCollapseDelay, forKey: Keys.hoverCollapseDelay) }
    }

    @Published var keepsHoverOpenWhileTyping: Bool {
        didSet { defaults.set(keepsHoverOpenWhileTyping, forKey: Keys.keepsHoverOpenWhileTyping) }
    }

    @Published var animationSpeed: AnimationSpeed {
        didSet { defaults.set(animationSpeed.rawValue, forKey: Keys.animationSpeed) }
    }

    @Published var glowIntensity: GlowIntensity {
        didSet { defaults.set(glowIntensity.rawValue, forKey: Keys.glowIntensity) }
    }

    @Published var notchTheme: NotchTheme {
        didSet { defaults.set(notchTheme.rawValue, forKey: Keys.notchTheme) }
    }

    @Published private(set) var isAPIKeyConfigured: Bool

    private let defaults: UserDefaults
    private let keychainStore: NudgeKeychainStore

    init(
        defaults: UserDefaults = .standard,
        keychainStore: NudgeKeychainStore = NudgeKeychainStore()
    ) {
        self.defaults = defaults
        self.keychainStore = keychainStore

        selectedModel = GeminiModel.storedValue(defaults.string(forKey: Keys.selectedModel))
        responseTone = ResponseTone(rawValue: defaults.string(forKey: Keys.responseTone) ?? "") ?? .friendly
        textSystemPrompt = defaults.string(forKey: Keys.textSystemPrompt) ?? Defaults.textSystemPrompt
        imageAnalysisPrompt = defaults.string(forKey: Keys.imageAnalysisPrompt) ?? Defaults.imageAnalysisPrompt
        pdfAnalysisPrompt = defaults.string(forKey: Keys.pdfAnalysisPrompt) ?? Defaults.pdfAnalysisPrompt
        emptyFileQuestionPrompt = defaults.string(forKey: Keys.emptyFileQuestionPrompt) ?? Defaults.emptyFileQuestionPrompt
        hoverActivationPadding = defaults.object(forKey: Keys.hoverActivationPadding) as? Double ?? Defaults.hoverActivationPadding
        hoverCollapseDelay = defaults.object(forKey: Keys.hoverCollapseDelay) as? Double ?? Defaults.hoverCollapseDelay
        keepsHoverOpenWhileTyping = defaults.object(forKey: Keys.keepsHoverOpenWhileTyping) as? Bool ?? Defaults.keepsHoverOpenWhileTyping
        animationSpeed = AnimationSpeed(rawValue: defaults.string(forKey: Keys.animationSpeed) ?? "") ?? .smooth
        glowIntensity = GlowIntensity(rawValue: defaults.string(forKey: Keys.glowIntensity) ?? "") ?? .normal
        notchTheme = NotchTheme(rawValue: defaults.string(forKey: Keys.notchTheme) ?? "") ?? .nudgeDefault
        isAPIKeyConfigured = keychainStore.loadAPIKey() != nil
    }

    func loadAPIKey() -> String? {
        keychainStore.loadAPIKey()
    }

    func saveAPIKey(_ apiKey: String) throws {
        try keychainStore.saveAPIKey(apiKey)
        refreshAPIKeyStatus()
    }

    func deleteAPIKey() {
        keychainStore.deleteAPIKey()
        refreshAPIKeyStatus()
    }

    func refreshAPIKeyStatus() {
        isAPIKeyConfigured = keychainStore.loadAPIKey() != nil
    }

    func resetPrompts() {
        responseTone = .friendly
        textSystemPrompt = Defaults.textSystemPrompt
        imageAnalysisPrompt = Defaults.imageAnalysisPrompt
        pdfAnalysisPrompt = Defaults.pdfAnalysisPrompt
        emptyFileQuestionPrompt = Defaults.emptyFileQuestionPrompt
    }

    func resetPreferencesToDefaults() {
        selectedModel = .auto
        resetPrompts()
        hoverActivationPadding = Defaults.hoverActivationPadding
        hoverCollapseDelay = Defaults.hoverCollapseDelay
        keepsHoverOpenWhileTyping = Defaults.keepsHoverOpenWhileTyping
        animationSpeed = .smooth
        glowIntensity = .normal
        notchTheme = .nudgeDefault
    }

    private enum Keys {
        static let selectedModel = "selectedModel"
        static let responseTone = "responseTone"
        static let textSystemPrompt = "textSystemPrompt"
        static let imageAnalysisPrompt = "imageAnalysisPrompt"
        static let pdfAnalysisPrompt = "pdfAnalysisPrompt"
        static let emptyFileQuestionPrompt = "emptyFileQuestionPrompt"
        static let hoverActivationPadding = "hoverActivationPadding"
        static let hoverCollapseDelay = "hoverCollapseDelay"
        static let keepsHoverOpenWhileTyping = "keepsHoverOpenWhileTyping"
        static let animationSpeed = "animationSpeed"
        static let glowIntensity = "glowIntensity"
        static let notchTheme = "notchTheme"
    }

    enum Defaults {
        static let hoverActivationPadding = 18.0
        static let hoverCollapseDelay = 0.45
        static let keepsHoverOpenWhileTyping = true
        static let textSystemPrompt = "당신은 macOS 유틸리티 Nudge 안에서 동작하는 간결하고 실용적인 AI 어시스턴트입니다. 사용자의 작업 흐름을 끊지 않도록 한국어로 핵심부터 답변해 주세요."
        static let imageAnalysisPrompt = "이 이미지를 한국어로 자세히 분석해 주세요. 핵심 내용, 눈에 띄는 요소, 필요한 후속 작업을 간결하게 정리해 주세요."
        static let pdfAnalysisPrompt = "이 PDF 문서를 한국어로 자세히 분석해 주세요. 핵심 요약, 주요 주장이나 내용, 표와 차트에서 읽을 수 있는 정보, 필요한 후속 작업을 간결하게 정리해 주세요."
        static let emptyFileQuestionPrompt = "이 파일에서 핵심만 요약해 주세요."
    }
}
