//
//  NudgeOverlayView.swift
//  Nudge
//
//  Created by Codex on 6/16/26.
//

import AppKit
import SwiftUI

struct NudgeOverlayView: View {
    @ObservedObject var model: NudgeOverlayModel
    @ObservedObject var settingsStore: NudgeSettingsStore
    @State private var isInputVisible = false
    @State private var promptFieldHeight: CGFloat = 46
    @State private var isPromptFocused = false
    @Namespace private var geminiModelPickerNamespace

    private var state: NudgeOverlayState {
        model.state
    }

    private var isShowingLoadingGlow: Bool {
        state == .loading || (state == .result && model.isLoading)
    }

    private var shouldShowGeminiModelPicker: Bool {
        true
    }

    var body: some View {
        ZStack(alignment: .top) {
            NudgeUnifiedSurfaceShape(cornerRadius: state == .normal ? 21 : 30)
                .fill(Color.black.opacity(0.95))
                .overlay {
                    ZStack {
                        NudgeUnifiedSurfaceShape(cornerRadius: state == .normal ? 21 : 30)
                            .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)

                        if state == .dragging {
                            NudgeUnifiedSurfaceShape(cornerRadius: 30)
                                .strokeBorder(
                                    nudgeGlowGradient,
                                    style: StrokeStyle(lineWidth: 1.4, dash: [8, 8])
                                )
                                .opacity(0.82)
                                .padding(8)
                        }

                        if isShowingLoadingGlow {
                            NudgeBreathingGlowView(
                                shape: NudgeUnifiedSurfaceShape(cornerRadius: state == .loading ? 30 : 32),
                                intensity: (state == .loading ? 0.34 : 0.38) * settingsStore.glowIntensity.multiplier
                            )
                            .padding(state == .loading ? 3 : 0)
                            .allowsHitTesting(false)
                        }
                    }
                }

            Rectangle()
                .fill(Color.black.opacity(0.95))
                .frame(height: 32)
                .allowsHitTesting(false)

            if isShowingLoadingGlow {
                NudgeTopBreathingGlowStrip()
                    .frame(height: 32)
                    .opacity(settingsStore.glowIntensity.multiplier)
                    .allowsHitTesting(false)
            }

            switch state {
            case .dragging:
                draggingView
            case .filePrompt:
                filePromptView
            case .hovered:
                promptInputView
            case .loading:
                loadingView
            case .result:
                resultView
            case .normal:
                EmptyView()
            }
        }
        .animation(settingsStore.animationSpeed.swiftUIAnimation, value: state)
        .onChange(of: state) { _, newState in
            updateInputVisibility(for: newState)
        }
    }

    private func updateInputVisibility(for state: NudgeOverlayState) {
        promptFieldHeight = 46
        isPromptFocused = false

        switch state {
        case .normal, .dragging, .filePrompt, .loading, .result:
            isInputVisible = false
        case .hovered:
            isInputVisible = false
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) {
                guard self.state == .hovered else { return }
                withAnimation(.easeOut(duration: 0.16)) {
                    isInputVisible = true
                }
            }
        }
    }

    private var promptInputView: some View {
        VStack(spacing: 0) {
            Spacer()
                .frame(height: 64)

            gradientPromptField(
                placeholder: "무엇이든 물어보세요...",
                fontSize: 17,
                isDisabled: false
            )
        }
        .padding(.horizontal, 30)
        .opacity(isInputVisible ? 1 : 0)
        .transition(.opacity)
    }

    private var draggingView: some View {
        VStack(spacing: 0) {
            Spacer()
                .frame(height: 64)

            HStack(spacing: 10) {
                Image(systemName: model.dragPromptIconName)
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(nudgeGlowGradient)

                Text(model.dragPromptText)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.86))
            }
            .padding(.horizontal, 20)
            .frame(height: 46)
            .frame(maxWidth: .infinity)
            .background(inputBackground(isFocused: false, isDisabled: false))
        }
        .padding(.horizontal, 30)
        .transition(.opacity)
    }

    private var filePromptView: some View {
        VStack(spacing: 0) {
            Spacer()
                .frame(height: 60)

            HStack(spacing: 12) {
                filePreviewTile

                VStack(alignment: .leading, spacing: 5) {
                    Text(model.droppedFileDisplayName)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.9))
                        .lineLimit(1)
                        .truncationMode(.middle)

                    HStack(spacing: 6) {
                        Text(model.droppedFileKindLabel)
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(nudgeGlowGradient)

                        Circle()
                            .fill(Color.white.opacity(0.25))
                            .frame(width: 3, height: 3)

                        Text(model.droppedFileSizeText)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Color.white.opacity(0.52))
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 4)
            .frame(height: 58)

            if !model.fileAnalysisTemplates.isEmpty {
                fileTemplateChipsView
                    .padding(.top, 14)
            }

            HStack(spacing: 12) {
                gradientPromptField(
                    placeholder: "\(model.droppedFileDisplayName)에게 물어보기...",
                    fontSize: 16,
                    isDisabled: false
                )
                .frame(maxWidth: .infinity)

                Button {
                    model.cancelFilePrompt()
                } label: {
                    ZStack {
                        Circle()
                            .fill(Color.white.opacity(0.13))
                            .overlay {
                                Circle()
                                    .strokeBorder(Color.white.opacity(0.14), lineWidth: 1)
                            }
                            .frame(width: 32, height: 32)

                        Image(systemName: "xmark")
                            .font(.system(size: 13, weight: .bold))
                    }
                    .frame(width: 32, height: promptFieldHeight)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.white.opacity(0.84))
                .help("Cancel")
                .fixedSize()
            }
            .padding(.top, 14)
        }
        .padding(.horizontal, 30)
        .transition(.opacity)
    }

    private var filePreviewTile: some View {
        Group {
            if model.hasMultipleDroppedFiles {
                multiFilePreviewStack
            } else {
                singleFilePreviewTile
            }
        }
    }

    private var singleFilePreviewTile: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.white.opacity(0.10))
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
                }

            if let thumbnail = model.droppedFilePreviewThumbnail {
                Image(nsImage: thumbnail)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 48, height: 48)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            } else {
                Image(systemName: model.droppedFilePreviewIconName)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(nudgeGlowGradient)
            }
        }
        .frame(width: 48, height: 48)
        .clipped()
    }

    private var multiFilePreviewStack: some View {
        ZStack {
            ForEach(Array(previewStackIndices.enumerated()), id: \.offset) { offset, index in
                filePreviewStackItem(at: index)
                    .offset(x: CGFloat(offset) * 8, y: CGFloat(offset) * -4)
                    .zIndex(Double(offset))
            }
        }
        .frame(width: 64, height: 56, alignment: .center)
    }

    private var previewStackIndices: [Int] {
        Array(0..<min(3, model.droppedFilePreviewItems.count))
    }

    private func filePreviewStackItem(at index: Int) -> some View {
        let item = model.droppedFilePreviewItems[index]

        return ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.white.opacity(0.12))
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.14), lineWidth: 1)
                }

            if let thumbnail = item.thumbnail {
                Image(nsImage: thumbnail)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 42, height: 42)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            } else {
                Image(systemName: item.iconName)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(nudgeGlowGradient)
            }
        }
        .frame(width: 42, height: 42)
        .clipped()
    }

    private var fileTemplateChipsView: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 7) {
                Image(systemName: "sparkles")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(nudgeGlowGradient)

                Text("빠른 분석 템플릿")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.62))

                Text("선택하면 질문창에 채워져요")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.38))
                    .lineLimit(1)
            }

            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(model.fileAnalysisTemplates) { template in
                        Button {
                            model.applyFileAnalysisTemplate(template)
                        } label: {
                            fileTemplateChip(template)
                        }
                        .buttonStyle(.plain)
                        .help("\(template.title) 템플릿을 질문창에 입력")
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollIndicators(.hidden)
        }
    }

    private func fileTemplateChip(_ template: NudgeFileAnalysisTemplate) -> some View {
        let isSelected = model.selectedFileAnalysisTemplateID == template.id

        return Text(template.title)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(Color.white.opacity(isSelected ? 0.94 : 0.82))
            .padding(.horizontal, 11)
            .frame(height: 30)
            .background {
                Capsule(style: .continuous)
                    .fill(Color.white.opacity(isSelected ? 0.15 : 0.09))
                    .overlay {
                        Capsule(style: .continuous)
                            .strokeBorder(
                                isSelected ? AnyShapeStyle(nudgeGlowGradient) : AnyShapeStyle(Color.white.opacity(0.11)),
                                lineWidth: isSelected ? 1.2 : 1
                            )
                    }
            }
    }

    private var loadingView: some View {
        VStack(spacing: 0) {
            Spacer()
                .frame(height: 64)

            NudgeBreathingGlowCapsule(intensity: settingsStore.glowIntensity.multiplier)
            .frame(height: 46)
        }
        .padding(.horizontal, 30)
        .transition(.opacity)
    }

    private var resultView: some View {
        VStack(alignment: .leading, spacing: 18) {
            resultHeaderView

            ScrollView {
                if model.isLoading {
                    resultLoadingView
                } else if let statusKind = model.activeResultStatusKind {
                    resultStatusView(for: statusKind)
                } else {
                    NudgeMarkdownText(markdown: model.displayedResponseText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .scrollIndicators(.hidden)

            if model.activeResultStatusKind == nil {
                followUpInputView
            }
        }
        .padding(.horizontal, 30)
        .padding(.top, 28)
        .padding(.bottom, 24)
        .transition(.opacity)
    }

    private var resultHeaderView: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 10) {
                providerPill

                if model.isFileResult {
                    resultFileHeader
                } else {
                    resultPromptSummary
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            resultActionButtons
        }
    }

    private var providerPill: some View {
        Text(model.responseProviderTitle)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(Color.white.opacity(0.86))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background {
                Capsule(style: .continuous)
                    .fill(Color.white.opacity(0.08))
                    .overlay {
                        Capsule(style: .continuous)
                            .strokeBorder(Color.white.opacity(0.10), lineWidth: 1)
                    }
            }
    }

    private var resultPromptSummary: some View {
        Text(model.submittedPrompt)
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(Color.white.opacity(0.62))
            .lineLimit(2)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var resultFileHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                resultFilePreviewTile

                VStack(alignment: .leading, spacing: 4) {
                    Text(model.droppedFileDisplayName)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.88))
                        .lineLimit(1)
                        .truncationMode(.middle)

                    HStack(spacing: 6) {
                        Text(model.droppedFileKindLabel)
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(nudgeGlowGradient)

                        Circle()
                            .fill(Color.white.opacity(0.22))
                            .frame(width: 3, height: 3)

                        Text(model.droppedFileSizeText)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(Color.white.opacity(0.46))
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Text(resultFilePromptSummary)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.46))
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var resultFilePreviewTile: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.white.opacity(0.10))
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
                }

            if let thumbnail = model.droppedFilePreviewThumbnail {
                Image(nsImage: thumbnail)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 36, height: 36)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            } else {
                Image(systemName: model.droppedFilePreviewIconName)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(nudgeGlowGradient)
            }
        }
        .frame(width: 36, height: 36)
        .clipped()
    }

    private var resultFilePromptSummary: String {
        let filePrefix = "\(model.droppedFileDisplayName) - "
        if model.submittedPrompt.hasPrefix(filePrefix) {
            return String(model.submittedPrompt.dropFirst(filePrefix.count))
        }

        return model.submittedPrompt
    }

    private var resultActionButtons: some View {
        HStack(spacing: 8) {
            resultActionsMenu

            headerIconButton(systemName: "doc.on.doc") {
                model.copyResponseToPasteboard()
            }
            .help("Copy")

            headerIconButton(systemName: "xmark") {
                model.closeResult()
            }
            .help("Close")
        }
        .frame(width: 106, alignment: .trailing)
        .fixedSize()
    }

    private var resultLoadingView: some View {
        Color.clear
            .frame(maxWidth: .infinity, minHeight: 240)
    }

    private func resultStatusView(for kind: NudgeResultStatusKind) -> some View {
        VStack(spacing: 14) {
            Image(systemName: resultStatusIconName(for: kind))
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(nudgeGlowGradient)
                .frame(width: 54, height: 54)
                .background {
                    Circle()
                        .fill(Color.white.opacity(0.08))
                        .overlay {
                            Circle()
                                .strokeBorder(Color.white.opacity(0.10), lineWidth: 1)
                        }
                }

            VStack(spacing: 6) {
                Text(resultStatusTitle(for: kind))
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.90))
                    .multilineTextAlignment(.center)

                Text(resultStatusDescription(for: kind))
                    .font(.system(size: 13, weight: .medium))
                    .lineSpacing(3)
                    .foregroundStyle(Color.white.opacity(0.54))
                    .multilineTextAlignment(.center)
                    .textSelection(.enabled)
                    .frame(maxWidth: 360)
            }

            if let actionTitle = resultStatusPrimaryActionTitle(for: kind) {
                Button {
                    performResultStatusPrimaryAction(for: kind)
                } label: {
                    Text(actionTitle)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.88))
                        .padding(.horizontal, 14)
                        .frame(height: 34)
                        .background {
                            Capsule(style: .continuous)
                                .fill(Color.white.opacity(0.11))
                                .overlay {
                                    Capsule(style: .continuous)
                                        .strokeBorder(Color.white.opacity(0.13), lineWidth: 1)
                                }
                        }
                }
                .buttonStyle(.plain)
                .disabled(isResultStatusPrimaryActionDisabled(for: kind))
                .opacity(isResultStatusPrimaryActionDisabled(for: kind) ? 0.45 : 1)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 240)
        .padding(.vertical, 8)
    }

    private func resultStatusIconName(for kind: NudgeResultStatusKind) -> String {
        switch kind {
        case .missingAPIKey:
            "key"
        case .networkFailure:
            "wifi.exclamationmark"
        case .unsupportedFile:
            "doc.badge.exclamationmark"
        case .emptyResponse, .empty:
            "text.bubble"
        case .genericError:
            "exclamationmark.triangle"
        }
    }

    private func resultStatusTitle(for kind: NudgeResultStatusKind) -> String {
        switch kind {
        case .missingAPIKey:
            "Gemini API Key가 필요합니다"
        case .networkFailure:
            "네트워크 연결을 확인해 주세요"
        case .unsupportedFile:
            "지원하지 않는 파일입니다"
        case .emptyResponse:
            "응답이 비어 있습니다"
        case .genericError:
            "요청을 처리하지 못했습니다"
        case .empty:
            "표시할 응답이 없습니다"
        }
    }

    private func resultStatusDescription(for kind: NudgeResultStatusKind) -> String {
        switch kind {
        case .missingAPIKey:
            "설정에서 Gemini API Key를 입력해 주세요."
        case .networkFailure:
            "응답을 불러오지 못했습니다. 연결 상태를 확인한 뒤 다시 시도해 주세요."
        case .unsupportedFile:
            "현재는 이미지와 PDF 파일을 우선 지원합니다."
        case .emptyResponse:
            "AI가 표시할 내용을 반환하지 않았습니다. 같은 요청을 다시 시도해 보세요."
        case .genericError:
            model.errorMessage ?? "잠시 후 다시 시도해 주세요."
        case .empty:
            "다시 질문을 입력해 주세요."
        }
    }

    private func resultStatusPrimaryActionTitle(for kind: NudgeResultStatusKind) -> String? {
        switch kind {
        case .missingAPIKey:
            "설정 열기"
        case .networkFailure, .emptyResponse, .genericError:
            model.canRetryLastRequest ? "다시 시도" : nil
        case .unsupportedFile, .empty:
            "닫기"
        }
    }

    private func isResultStatusPrimaryActionDisabled(for kind: NudgeResultStatusKind) -> Bool {
        switch kind {
        case .networkFailure, .emptyResponse, .genericError:
            !model.canRetryLastRequest
        default:
            false
        }
    }

    private func performResultStatusPrimaryAction(for kind: NudgeResultStatusKind) {
        switch kind {
        case .missingAPIKey:
            model.openSettings()
        case .networkFailure, .emptyResponse, .genericError:
            model.regenerateLastResponse()
        case .unsupportedFile, .empty:
            model.closeResult()
        }
    }

    private var followUpInputView: some View {
        gradientPromptField(
            placeholder: model.isLoading ? "" : "이어서 물어보세요...",
            fontSize: 15,
            isDisabled: model.isLoading
        )
        .opacity(model.isLoading ? 0.62 : 1)
    }

    private var resultActionsMenu: some View {
        Menu {
            Button("텍스트 파일로 저장") {
                model.saveResponseAsTextFile()
            }

            Button("공유") {
                model.shareResponse()
            }

            Button("원본 파일 열기") {
                model.openDroppedFile()
            }
            .disabled(!model.canOpenDroppedFile)

            Divider()

            Button("설정") {
                model.openSettings()
            }

            Button("다시 생성") {
                model.regenerateLastResponse()
            }
            .disabled(model.isLoading)
        } label: {
            headerIconLabel(systemName: "ellipsis")
        }
        .buttonStyle(.plain)
        .fixedSize()
        .help("More")
    }

    private func headerIconButton(
        systemName: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            headerIconLabel(systemName: systemName)
        }
        .buttonStyle(.plain)
    }

    private func headerIconLabel(systemName: String) -> some View {
        Image(systemName: systemName)
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(Color.white.opacity(0.86))
            .frame(width: 30, height: 30)
            .background {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.white.opacity(0.10))
                    .overlay {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
                    }
            }
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func inputBackground(isFocused: Bool, isDisabled: Bool) -> some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(Color.white.opacity(0.12))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(Color.white.opacity(isDisabled ? 0.07 : 0.12), lineWidth: 1)
            }
            .overlay {
                if isFocused && !isDisabled {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(nudgeGlowGradient, lineWidth: 1.2)
                        .opacity(0.92)
                }
            }
    }

    private func gradientPromptField(
        placeholder: String,
        fontSize: CGFloat,
        isDisabled: Bool
    ) -> some View {
        let showsModelPicker = shouldShowGeminiModelPicker

        return ZStack(alignment: .topLeading) {
            if model.prompt.isEmpty {
                Text(placeholder)
                    .font(.system(size: fontSize, weight: .medium))
                    .foregroundStyle(nudgeGlowGradient)
                    .lineLimit(1)
                    .padding(.horizontal, 18)
                    .padding(.trailing, showsModelPicker ? 104 : 18)
                    .padding(.top, 12)
                    .allowsHitTesting(false)
            }

            NudgeMultilinePromptEditor(
                text: $model.prompt,
                height: $promptFieldHeight,
                fontSize: fontSize,
                isDisabled: isDisabled,
                onFocusChange: { isFocused in
                    guard !isDisabled else { return }
                    withAnimation(.easeOut(duration: 0.16)) {
                        isPromptFocused = isFocused
                    }
                }
            ) {
                if state == .filePrompt {
                    model.submitFilePrompt()
                } else {
                    model.submitPrompt()
                }
            }
            .padding(.horizontal, 18)
            .padding(.trailing, showsModelPicker ? 96 : 18)
            .padding(.vertical, 11)

            if showsModelPicker {
                geminiModelQuickPicker(isDisabled: isDisabled)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(.top, 8)
                    .padding(.trailing, 8)
            }
        }
        .frame(height: promptFieldHeight)
        .background(inputBackground(isFocused: isPromptFocused, isDisabled: isDisabled))
        .opacity(isDisabled ? 0.62 : 1)
        .animation(.easeOut(duration: 0.18), value: promptFieldHeight)
        .animation(.easeOut(duration: 0.16), value: isPromptFocused)
    }

    private func geminiModelQuickPicker(isDisabled: Bool) -> some View {
        HStack(spacing: 2) {
            ForEach(NudgeSettingsStore.GeminiModel.allCases) { geminiModel in
                Button {
                    withAnimation(.timingCurve(0.25, 0.1, 0.25, 1.0, duration: 0.22)) {
                        settingsStore.selectedModel = geminiModel
                    }
                } label: {
                    Text(geminiModel.title)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Color.white.opacity(settingsStore.selectedModel == geminiModel ? 0.92 : 0.52))
                        .frame(width: 38, height: 24)
                        .background {
                            if settingsStore.selectedModel == geminiModel {
                                Capsule(style: .continuous)
                                    .fill(Color.white.opacity(0.14))
                                    .overlay {
                                        Capsule(style: .continuous)
                                            .strokeBorder(nudgeGlowGradient, lineWidth: 1)
                                            .opacity(0.78)
                                    }
                                    .matchedGeometryEffect(id: "selectedGeminiModel", in: geminiModelPickerNamespace)
                            }
                        }
                }
                .buttonStyle(.plain)
                .disabled(isDisabled)
                .help("\(geminiModel.title): \(geminiModel.modelName)")
            }
        }
        .padding(3)
        .background {
            Capsule(style: .continuous)
                .fill(Color.black.opacity(0.28))
                .overlay {
                    Capsule(style: .continuous)
                        .strokeBorder(Color.white.opacity(0.10), lineWidth: 1)
                }
        }
        .opacity(isDisabled ? 0.45 : 1)
        .animation(.timingCurve(0.25, 0.1, 0.25, 1.0, duration: 0.22), value: settingsStore.selectedModel)
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
}

private struct NudgeMultilinePromptEditor: NSViewRepresentable {
    @Binding var text: String
    @Binding var height: CGFloat

    let fontSize: CGFloat
    let isDisabled: Bool
    let onFocusChange: (Bool) -> Void
    let onSubmit: () -> Void

    private let minHeight: CGFloat = 46
    private let maxHeight: CGFloat = 112
    private let verticalPadding: CGFloat = 22

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = false
        scrollView.autohidesScrollers = true

        let textView = NudgePromptTextView()
        textView.delegate = context.coordinator
        textView.onSubmit = onSubmit
        textView.onFocusChange = onFocusChange
        textView.drawsBackground = false
        textView.isRichText = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.allowsUndo = true
        textView.textColor = NSColor.white.withAlphaComponent(0.92)
        textView.insertionPointColor = NSColor(
            calibratedRed: 0.46,
            green: 0.78,
            blue: 1.0,
            alpha: 1.0
        )
        textView.font = NSFont.systemFont(ofSize: fontSize, weight: .medium)
        textView.textContainerInset = .zero
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.widthTracksTextView = true
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = true
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.autoresizingMask = [.width]
        textView.string = text

        scrollView.documentView = textView
        context.coordinator.textView = textView
        context.coordinator.recalculateHeight()

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NudgePromptTextView else { return }

        context.coordinator.parent = self
        textView.onSubmit = onSubmit
        textView.onFocusChange = onFocusChange
        textView.font = NSFont.systemFont(ofSize: fontSize, weight: .medium)
        textView.isEditable = !isDisabled
        textView.isSelectable = !isDisabled
        textView.textColor = NSColor.white.withAlphaComponent(isDisabled ? 0.46 : 0.92)

        if textView.string != text {
            textView.string = text
        }

        DispatchQueue.main.async {
            context.coordinator.recalculateHeight()
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: NudgeMultilinePromptEditor
        weak var textView: NSTextView?

        init(parent: NudgeMultilinePromptEditor) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.text = textView.string
            recalculateHeight()
        }

        func recalculateHeight() {
            guard let textView else { return }

            textView.layoutManager?.ensureLayout(for: textView.textContainer!)
            let usedHeight = textView.layoutManager?.usedRect(for: textView.textContainer!).height ?? 0
            let nextHeight = min(
                max(parent.minHeight, ceil(usedHeight) + parent.verticalPadding),
                parent.maxHeight
            )

            if abs(parent.height - nextHeight) > 0.5 {
                parent.height = nextHeight
            }
        }
    }
}

private final class NudgePromptTextView: NSTextView {
    var onSubmit: (() -> Void)?
    var onFocusChange: ((Bool) -> Void)?

    override func becomeFirstResponder() -> Bool {
        let didBecomeFirstResponder = super.becomeFirstResponder()
        if didBecomeFirstResponder {
            onFocusChange?(true)
        }
        return didBecomeFirstResponder
    }

    override func resignFirstResponder() -> Bool {
        let didResignFirstResponder = super.resignFirstResponder()
        if didResignFirstResponder {
            onFocusChange?(false)
        }
        return didResignFirstResponder
    }

    override func keyDown(with event: NSEvent) {
        let isReturnKey = event.keyCode == 36 || event.keyCode == 76

        if isReturnKey {
            let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            let shouldInsertNewline = modifiers.contains(.shift) || modifiers.contains(.option)

            if shouldInsertNewline {
                insertNewline(nil)
            } else {
                onSubmit?()
            }
            return
        }

        super.keyDown(with: event)
    }
}

private extension NSEvent.ModifierFlags {
    static let deviceIndependentFlagsMask: NSEvent.ModifierFlags = [
        .capsLock,
        .shift,
        .control,
        .option,
        .command,
        .numericPad,
        .help,
        .function
    ]
}

private struct NudgeUnifiedSurfaceShape: InsettableShape {
    var cornerRadius: CGFloat
    var insetAmount: CGFloat = 0

    var animatableData: CGFloat {
        get { cornerRadius }
        set { cornerRadius = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let insetRect = rect.insetBy(dx: insetAmount, dy: insetAmount)
        let radius = min(cornerRadius, insetRect.width / 2, insetRect.height)
        let minX = insetRect.minX
        let maxX = insetRect.maxX
        let minY = insetRect.minY
        let maxY = insetRect.maxY

        var path = Path()
        path.move(to: CGPoint(x: minX, y: minY))
        path.addLine(to: CGPoint(x: maxX, y: minY))
        path.addLine(to: CGPoint(x: maxX, y: maxY - radius))
        path.addQuadCurve(
            to: CGPoint(x: maxX - radius, y: maxY),
            control: CGPoint(x: maxX, y: maxY)
        )
        path.addLine(to: CGPoint(x: minX + radius, y: maxY))
        path.addQuadCurve(
            to: CGPoint(x: minX, y: maxY - radius),
            control: CGPoint(x: minX, y: maxY)
        )
        path.addLine(to: CGPoint(x: minX, y: minY))
        path.closeSubpath()

        return path
    }

    func inset(by amount: CGFloat) -> NudgeUnifiedSurfaceShape {
        var shape = self
        shape.insetAmount += amount
        return shape
    }
}

private struct NudgeBreathingGlowView<GlowShape: InsettableShape>: View {
    let shape: GlowShape
    let intensity: Double

    var body: some View {
        TimelineView(.animation) { context in
            let phase = context.date.timeIntervalSinceReferenceDate
            let breath = (sin(phase * 1.45) + 1) / 2
            let drift = (sin(phase * 0.72) + 1) / 2

            shape
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.25, green: 0.74, blue: 1.0).opacity(0.25 + breath * 0.18),
                            Color(red: 0.62, green: 0.45, blue: 1.0).opacity(0.30 + breath * 0.20),
                            Color(red: 1.0, green: 0.40, blue: 0.80).opacity(0.22 + breath * 0.18),
                            Color(red: 1.0, green: 0.65, blue: 0.34).opacity(0.18 + breath * 0.14)
                        ],
                        startPoint: UnitPoint(x: -0.20 + drift * 0.34, y: 0.05),
                        endPoint: UnitPoint(x: 0.86 + drift * 0.30, y: 1.0)
                    )
                )
                .scaleEffect(1.0 + breath * 0.018)
                .blur(radius: 18 + breath * 7)
                .opacity(intensity)
                .blendMode(.screen)
                .overlay {
                    shape
                        .strokeBorder(
                            LinearGradient(
                                colors: [
                                    Color(red: 0.35, green: 0.78, blue: 1.0).opacity(0.20 + breath * 0.28),
                                    Color(red: 0.95, green: 0.48, blue: 0.94).opacity(0.28 + breath * 0.22),
                                    Color(red: 1.0, green: 0.74, blue: 0.36).opacity(0.16 + breath * 0.18)
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            ),
                            lineWidth: 1.1 + breath * 0.6
                        )
                        .opacity(0.54)
                        .blendMode(.screen)
                }
        }
    }
}

private struct NudgeBreathingGlowCapsule: View {
    let intensity: Double

    var body: some View {
        TimelineView(.animation) { context in
            let phase = context.date.timeIntervalSinceReferenceDate
            let breath = (sin(phase * 1.75) + 1) / 2
            let drift = (sin(phase * 0.95) + 1) / 2

            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white.opacity(0.08 + breath * 0.03))
                .overlay {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color(red: 0.23, green: 0.76, blue: 1.0).opacity(0.20),
                                    Color(red: 0.62, green: 0.45, blue: 1.0).opacity(0.28 + breath * 0.14),
                                    Color(red: 1.0, green: 0.42, blue: 0.80).opacity(0.22 + breath * 0.12),
                                    Color(red: 1.0, green: 0.68, blue: 0.34).opacity(0.18)
                                ],
                                startPoint: UnitPoint(x: -0.25 + drift * 0.44, y: 0.5),
                                endPoint: UnitPoint(x: 0.84 + drift * 0.36, y: 0.5)
                            )
                        )
                        .blur(radius: 13 + breath * 3)
                        .blendMode(.screen)
                        .padding(.horizontal, 14)
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.12 + breath * 0.10), lineWidth: 1)
                }
                .scaleEffect(x: 0.985 + breath * 0.015, y: 0.96 + breath * 0.04)
                .opacity(intensity)
                .animation(nil, value: breath)
        }
    }
}

private struct NudgeTopBreathingGlowStrip: View {
    var body: some View {
        TimelineView(.animation) { context in
            let phase = context.date.timeIntervalSinceReferenceDate
            let breath = (sin(phase * 1.45) + 1) / 2
            let drift = (sin(phase * 0.72) + 1) / 2

            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.25, green: 0.74, blue: 1.0).opacity(0.16 + breath * 0.10),
                            Color(red: 0.62, green: 0.45, blue: 1.0).opacity(0.18 + breath * 0.13),
                            Color(red: 1.0, green: 0.40, blue: 0.80).opacity(0.14 + breath * 0.10),
                            Color(red: 1.0, green: 0.65, blue: 0.34).opacity(0.12 + breath * 0.08)
                        ],
                        startPoint: UnitPoint(x: -0.16 + drift * 0.30, y: 0.5),
                        endPoint: UnitPoint(x: 0.88 + drift * 0.28, y: 0.5)
                    )
                )
                .blur(radius: 18 + breath * 5)
                .opacity(0.82)
                .blendMode(.screen)
                .clipped()
        }
    }
}
