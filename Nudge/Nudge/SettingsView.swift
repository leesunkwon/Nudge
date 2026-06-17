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
    @State private var resetMessage: String?
    @Namespace private var geminiModelSettingsNamespace

    var body: some View {
        ZStack {
            settingsBackground

            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    header
                    aiSection
                    promptSection
                    interactionSection
                    animationSection
                    resetSection
                }
                .padding(28)
            }
        }
        .frame(minWidth: 560, minHeight: 560)
        .colorScheme(.dark)
        .onAppear {
            settingsStore.refreshAPIKeyStatus()
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 14) {
            ZStack {
                Circle()
                    .fill(nudgeGlowGradient)
                    .blur(radius: 8)
                    .opacity(0.62)

                Image(systemName: "sparkles")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .frame(width: 42, height: 42)
            .background {
                Circle()
                    .fill(Color.white.opacity(0.08))
                    .overlay {
                        Circle()
                            .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
                    }
            }

            VStack(alignment: .leading, spacing: 5) {
                Text("Nudge 설정")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(.white)

                Text("AI, 프롬프트, Hover 동작, 애니메이션을 조정합니다.")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.56))
            }
        }
    }

    private var aiSection: some View {
        settingsSection("AI") {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Gemini API Key")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Color.white.opacity(0.88))

                        Text(settingsStore.isAPIKeyConfigured ? "Keychain에 저장됨" : "설정되지 않음")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(settingsStore.isAPIKeyConfigured ? Color(red: 0.50, green: 0.95, blue: 0.66) : Color(red: 1.0, green: 0.74, blue: 0.36))
                    }

                    Spacer()

                    Button("삭제") {
                        settingsStore.deleteAPIKey()
                        apiKeyInput = ""
                        apiKeyMessage = "API Key를 삭제했습니다."
                    }
                    .disabled(!settingsStore.isAPIKeyConfigured)
                    .buttonStyle(NudgeSettingsButtonStyle(kind: .secondary))
                }

                SecureField("Gemini API Key 입력", text: $apiKeyInput)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.9))
                    .padding(.horizontal, 12)
                    .frame(height: 38)
                    .background(settingsInputBackground)

                HStack {
                    Button("저장") {
                        saveAPIKey()
                    }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(NudgeSettingsButtonStyle(kind: .primary))

                    if let apiKeyMessage {
                        Text(apiKeyMessage)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Color.white.opacity(0.52))
                    }
                }

                Divider()

                VStack(alignment: .leading, spacing: 10) {
                    Text("Gemini 모델")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.88))

                    HStack(spacing: 10) {
                        ForEach(NudgeSettingsStore.GeminiModel.allCases) { model in
                            geminiModelOptionButton(model)
                        }
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
                .buttonStyle(NudgeSettingsButtonStyle(kind: .secondary))
            }
        }
    }

    private var interactionSection: some View {
        settingsSection("Interaction") {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Hover 감지 민감도")
                            .foregroundStyle(Color.white.opacity(0.84))
                        Spacer()
                        Text("\(Int(settingsStore.hoverActivationPadding))px")
                            .foregroundStyle(Color.white.opacity(0.48))
                    }
                    Slider(value: $settingsStore.hoverActivationPadding, in: 8...40, step: 1)
                }

                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Hover 닫힘 지연 시간")
                            .foregroundStyle(Color.white.opacity(0.84))
                        Spacer()
                        Text(String(format: "%.2fs", settingsStore.hoverCollapseDelay))
                            .foregroundStyle(Color.white.opacity(0.48))
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

    private var resetSection: some View {
        settingsSection("Reset") {
            VStack(alignment: .leading, spacing: 10) {
                Text("모델, 프롬프트, Hover 동작, 애니메이션 설정을 기본값으로 되돌립니다. Gemini API Key는 삭제하지 않습니다.")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.54))

                HStack {
                    Button("설정 초기화") {
                        settingsStore.resetPreferencesToDefaults()
                        resetMessage = "기본 설정으로 되돌렸습니다."
                    }
                    .buttonStyle(NudgeSettingsButtonStyle(kind: .secondary))

                    if let resetMessage {
                        Text(resetMessage)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Color.white.opacity(0.52))
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
                .foregroundStyle(Color.white.opacity(0.92))

            content()
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.white.opacity(0.07))
                        .overlay {
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .strokeBorder(Color.white.opacity(0.10), lineWidth: 1)
                        }
                }
        }
    }

    private func promptEditor(_ title: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.52))

            TextEditor(text: text)
                .font(.system(size: 13))
                .foregroundStyle(Color.white.opacity(0.88))
                .frame(minHeight: 76)
                .scrollContentBackground(.hidden)
                .padding(8)
                .background {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.black.opacity(0.34))
                        .overlay {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .strokeBorder(Color.white.opacity(0.10), lineWidth: 1)
                        }
                }
        }
    }

    private func geminiModelOptionButton(_ model: NudgeSettingsStore.GeminiModel) -> some View {
        let isSelected = settingsStore.selectedModel == model

        return Button {
            withAnimation(.timingCurve(0.25, 0.1, 0.25, 1.0, duration: 0.24)) {
                settingsStore.selectedModel = model
            }
        } label: {
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 7) {
                    Text(model.title)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Color.white.opacity(0.92))

                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(nudgeGlowGradient)
                    }
                }
                .animation(.easeOut(duration: 0.16), value: isSelected)

                Text(model.modelName)
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Color.white.opacity(0.45))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                Text(model.description)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.58))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(Color.white.opacity(0.06))
                    .overlay {
                        if isSelected {
                            RoundedRectangle(cornerRadius: 11, style: .continuous)
                                .fill(Color.white.opacity(0.07))
                                .overlay {
                                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                                        .strokeBorder(nudgeGlowGradient, lineWidth: 1.2)
                                }
                                .matchedGeometryEffect(id: "selectedGeminiSettingsModel", in: geminiModelSettingsNamespace)
                        } else {
                            RoundedRectangle(cornerRadius: 11, style: .continuous)
                                .strokeBorder(Color.white.opacity(0.09), lineWidth: 1)
                        }
                    }
            }
        }
        .buttonStyle(.plain)
        .animation(.timingCurve(0.25, 0.1, 0.25, 1.0, duration: 0.24), value: settingsStore.selectedModel)
    }

    private var settingsBackground: some View {
        LinearGradient(
            colors: [
                Color.black,
                Color(red: 0.05, green: 0.04, blue: 0.08),
                Color(red: 0.02, green: 0.02, blue: 0.03)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(nudgeGlowGradient)
                .frame(height: 1)
                .blur(radius: 3)
                .opacity(0.62)
        }
    }

    private var settingsInputBackground: some View {
        RoundedRectangle(cornerRadius: 9, style: .continuous)
            .fill(Color.black.opacity(0.34))
            .overlay {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.10), lineWidth: 1)
            }
    }

    private var nudgeGlowGradient: LinearGradient {
        LinearGradient(
            colors: [
                Color(red: 0.25, green: 0.73, blue: 1.0),
                Color(red: 0.57, green: 0.45, blue: 1.0),
                Color(red: 1.0, green: 0.42, blue: 0.78),
                Color(red: 1.0, green: 0.64, blue: 0.36)
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
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

private struct NudgeSettingsButtonStyle: ButtonStyle {
    enum Kind {
        case primary
        case secondary
    }

    let kind: Kind

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(kind == .primary ? Color.black : Color.white.opacity(0.86))
            .padding(.horizontal, 13)
            .frame(height: 30)
            .background {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(background)
                    .overlay {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(Color.white.opacity(kind == .primary ? 0 : 0.12), lineWidth: 1)
                    }
            }
            .opacity(configuration.isPressed ? 0.72 : 1)
    }

    private var background: AnyShapeStyle {
        switch kind {
        case .primary:
            AnyShapeStyle(LinearGradient(
                colors: [
                    Color(red: 0.46, green: 0.82, blue: 1.0),
                    Color(red: 1.0, green: 0.52, blue: 0.82)
                ],
                startPoint: .leading,
                endPoint: .trailing
            ))
        case .secondary:
            AnyShapeStyle(Color.white.opacity(0.10))
        }
    }
}
