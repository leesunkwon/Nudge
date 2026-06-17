# Nudge

> Just nudge your notch for Gemini AI.

Nudge는 MacBook의 노치 영역을 AI와 만나는 가장 가까운 포털로 바꾸는 macOS 인터랙티브 AI 유틸리티입니다. 화면 상단의 노치를 살짝 건드리거나, 파일을 툭 던지는 동작만으로 질문, 이미지 분석, PDF 요약, 후속 대화를 이어갈 수 있습니다.

브라우저를 열고 새 창을 띄우는 흐름 대신, 지금 보고 있는 작업 맥락 위에서 바로 AI를 호출하는 것을 목표로 합니다.

## 주요 기능

### 노치 오버레이

- `WindowGroup` 기본 창 대신 AppKit 기반 `NSPanel` 오버레이 사용
- 화면 상단 중앙 노치 위치에 투명/무테/항상 위 패널 배치
- `.statusBar` 레벨로 일반 앱 창 위에 표시
- normal, hovered, dragging, filePrompt, loading, result 상태 기반 UI
- 검은 단일 표면이 아래로 자연스럽게 확장되는 Apple 스타일 애니메이션

### Hover Quick Input

- 마우스를 노치 영역에 올리면 입력창이 나타남
- 멀티라인 입력 지원
- `Enter` 제출
- `Shift + Enter`, `Option + Enter` 줄바꿈
- 입력창 포커스 시 Apple Intelligence 느낌의 그라데이션 stroke 표시

### Gemini / Apple Intelligence 텍스트 질문

- 설정에서 AI 엔진 선택 가능
- Gemini 텍스트 질문 지원
- Apple Intelligence 텍스트 질문 지원
- Apple Intelligence 사용 불가 환경에서는 안내 메시지 표시
- 이미지/PDF 분석은 AI 엔진 설정과 무관하게 Gemini 사용

### 파일 / 이미지 / PDF 드롭 분석

- 노치 영역에 파일을 드래그하면 파일 타입별 드롭 UI 표시
- 이미지 드롭 지원
- PDF 드롭 지원
- 파일 드롭 후 바로 분석하지 않고 질문 입력 단계 제공
- 빈 질문 제출 시 파일 타입별 기본 프롬프트 사용
- 이미지/PDF와 텍스트 질문을 Gemini 멀티모달 요청으로 전송
- 파일 분석 후 후속 질문에서도 파일 맥락 유지

### Result 패널

- Gemini 또는 Apple Intelligence 응답 결과 표시
- 마크다운 렌더링 지원
  - 제목
  - 목록
  - 코드블록
  - 일반 문단
- 응답 타이핑 효과
- 후속 질문 입력창
- 복사, 저장, 공유, 원본 파일 열기, 다시 생성 액션
- 파일 분석 Result에서는 파일명, 타입, 용량, 썸네일/아이콘 표시
- API Key 없음, 네트워크 실패, Apple Intelligence 사용 불가, 빈 응답, 지원하지 않는 파일 상태 UI 정리

### 설정

- macOS 메뉴바 상태 아이콘에서 설정 창 열기
- Result 패널 더보기 메뉴에서 설정 열기
- Gemini API Key 입력 및 저장
- Keychain 우선 저장 구조
- Gemini 모델 선택
- 기본 프롬프트 설정
  - 일반 텍스트 질문
  - 이미지 분석
  - PDF 분석
  - 빈 파일 질문
- Hover 감지 민감도 및 닫힘 지연 설정
- 입력 중 패널 유지 옵션
- 애니메이션 속도 설정
- 글로우 강도 설정
- 설정 초기화 지원

## 기술 스택

- Swift
- SwiftUI
- AppKit
- FoundationModels
- Google Gemini REST API
- Keychain Services
- UserDefaults
- UniformTypeIdentifiers

## 프로젝트 구조

```text
Nudge/
  Nudge/
    AppDelegate.swift
    NudgeApp.swift
    NudgeOverlayWindowController.swift
    NudgeOverlayState.swift
    NudgeOverlayModel.swift
    NudgeOverlayView.swift
    NudgeMarkdownText.swift
    GeminiClient.swift
    NudgeSettingsStore.swift
    NudgeKeychainStore.swift
    SettingsWindowController.swift
    SettingsView.swift
    Info.plist
```

## 실행 전 설정

### Gemini API Key

실제 API Key는 Git에 포함하지 않습니다.

로컬 개발에서는 `Secrets.xcconfig`를 사용하고, 저장소에는 예시 파일만 포함하는 방식을 사용합니다.

```text
Secrets.xcconfig
Secrets.xcconfig.example
```

앱에서는 `Info.plist`를 통해 빌드 타임에 주입된 `GeminiAPIKey`를 fallback으로 읽을 수 있습니다. 앱 내 설정 창에서 Keychain에 저장한 API Key가 있으면 해당 값을 우선 사용합니다.

API Key 조회 우선순위:

1. Keychain
2. `GEMINI_API_KEY` 환경변수
3. `Info.plist`의 `GeminiAPIKey`

## 빌드

```bash
xcodebuild -project Nudge/Nudge.xcodeproj \
  -scheme Nudge \
  -configuration Debug \
  -derivedDataPath /tmp/NudgeDerivedData \
  CODE_SIGNING_ALLOWED=NO \
  build
```

## 현재 지원 범위

- macOS 앱
- MacBook 노치 중심 UX
- 텍스트 질문
- 후속 질문
- 이미지 분석
- PDF 분석
- Gemini API
- Apple Intelligence 텍스트 질문
- 앱 내부 설정 창

## 아직 확장 가능한 부분

- 대화 히스토리 UI
- 전역 단축키 호출
- 클립보드 기반 질문
- 선택 텍스트 가져오기
- 코드블록별 복사/저장 액션
- 텍스트/코드 파일 분석 지원
- 로그인 시 자동 실행
- 실제 Gemini streaming API 연동

## 개발 원칙

- 노치와 하나의 표면처럼 보이는 UI를 우선합니다.
- 사용자의 작업 흐름을 끊지 않는 가벼운 제스처를 우선합니다.
- API Key와 로컬 secret은 Git에 포함하지 않습니다.
- 설정 가능한 값은 앱 설정 창으로 점진적으로 이동합니다.
- 기능보다 먼저 macOS 유틸리티다운 반응성과 질감을 중요하게 봅니다.
