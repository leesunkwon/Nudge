//
//  SettingsView.swift
//  Nudge
//
//  Created by Codex on 6/16/26.
//

import SwiftUI

struct SettingsView: View {
    @ObservedObject var settingsStore: NudgeSettingsStore
    @State private var apiKeyInput = ""
    @State private var apiKeyMessage: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header
                aiSection
                promptSection
                interactionSection
                animationSection
            }
            .padding(28)
        }
        .frame(minWidth: 560, minHeight: 560)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            settingsStore.refreshAPIKeyStatus()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Nudge 설정")
                .font(.system(size: 28, weight: .bold))

            Text("AI, 프롬프트, Hover 동작, 애니메이션을 조정합니다.")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
        }
    }

    private var aiSection: some View {
        settingsSection("AI") {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Gemini API Key")
                            .font(.system(size: 13, weight: .semibold))

                        Text(settingsStore.isAPIKeyConfigured ? "Keychain에 저장됨" : "설정되지 않음")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(settingsStore.isAPIKeyConfigured ? Color.green : Color.orange)
                    }

                    Spacer()

                    Button("삭제") {
                        settingsStore.deleteAPIKey()
                        apiKeyInput = ""
                        apiKeyMessage = "API Key를 삭제했습니다."
                    }
                    .disabled(!settingsStore.isAPIKeyConfigured)
                }

                SecureField("Gemini API Key 입력", text: $apiKeyInput)
                    .textFieldStyle(.roundedBorder)

                HStack {
                    Button("저장") {
                        saveAPIKey()
                    }
                    .keyboardShortcut(.defaultAction)

                    if let apiKeyMessage {
                        Text(apiKeyMessage)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                }

                Divider()

                Picker("Gemini 모델", selection: $settingsStore.selectedModel) {
                    ForEach(NudgeSettingsStore.GeminiModel.allCases) { model in
                        Text(model.title).tag(model)
                    }
                }
            }
        }
    }

    private var promptSection: some View {
        settingsSection("Prompt") {
            VStack(alignment: .leading, spacing: 14) {
                promptEditor("일반 텍스트 질문 기본 성격", text: $settingsStore.textSystemPrompt)
                promptEditor("이미지 분석 기본 프롬프트", text: $settingsStore.imageAnalysisPrompt)
                promptEditor("PDF 분석 기본 프롬프트", text: $settingsStore.pdfAnalysisPrompt)
                promptEditor("빈 파일 질문 기본 문구", text: $settingsStore.emptyFileQuestionPrompt)

                Button("기본 프롬프트로 되돌리기") {
                    settingsStore.resetPrompts()
                }
            }
        }
    }

    private var interactionSection: some View {
        settingsSection("Interaction") {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Hover 감지 민감도")
                        Spacer()
                        Text("\(Int(settingsStore.hoverActivationPadding))px")
                            .foregroundStyle(.secondary)
                    }
                    Slider(value: $settingsStore.hoverActivationPadding, in: 8...40, step: 1)
                }

                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Hover 닫힘 지연 시간")
                        Spacer()
                        Text(String(format: "%.2fs", settingsStore.hoverCollapseDelay))
                            .foregroundStyle(.secondary)
                    }
                    Slider(value: $settingsStore.hoverCollapseDelay, in: 0.15...1.2, step: 0.05)
                }

                Toggle("마우스가 벗어나도 입력 중이면 패널 유지", isOn: $settingsStore.keepsHoverOpenWhileTyping)
            }
        }
    }

    private var animationSection: some View {
        settingsSection("Animation") {
            VStack(alignment: .leading, spacing: 14) {
                Picker("애니메이션 속도", selection: $settingsStore.animationSpeed) {
                    ForEach(NudgeSettingsStore.AnimationSpeed.allCases) { speed in
                        Text(speed.title).tag(speed)
                    }
                }

                Picker("글로우 효과 강도", selection: $settingsStore.glowIntensity) {
                    ForEach(NudgeSettingsStore.GlowIntensity.allCases) { intensity in
                        Text(intensity.title).tag(intensity)
                    }
                }
            }
        }
    }

    private func settingsSection<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.system(size: 16, weight: .bold))

            content()
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color(nsColor: .controlBackgroundColor))
                }
        }
    }

    private func promptEditor(_ title: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)

            TextEditor(text: text)
                .font(.system(size: 13))
                .frame(minHeight: 76)
                .scrollContentBackground(.hidden)
                .padding(8)
                .background {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color(nsColor: .textBackgroundColor))
                        .overlay {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 1)
                        }
                }
        }
    }

    private func saveAPIKey() {
        do {
            try settingsStore.saveAPIKey(apiKeyInput)
            apiKeyInput = ""
            apiKeyMessage = "API Key를 저장했습니다."
        } catch {
            apiKeyMessage = error.localizedDescription
        }
    }
}
