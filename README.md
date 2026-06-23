# Nudge

> Just nudge your notch for Gemini AI.

Nudge는 MacBook의 노치 영역에서 바로 Gemini AI를 호출하는 macOS 유틸리티입니다.
마우스를 노치에 올려 질문하거나, 파일을 노치로 드롭해 요약과 분석을 받을 수 있습니다.

브라우저를 열거나 새 창을 찾지 않고, 지금 작업 중인 화면 위에서 가볍게 AI를 사용하는 경험을 목표로 합니다.

## 무엇을 할 수 있나요?

- 노치에 마우스를 올려 바로 질문하기
- 이미지, PDF, 문서, 코드 파일을 드롭해서 분석하기
- 여러 파일을 한 번에 드롭해 비교하거나 요약하기
- 분석 결과에 이어서 후속 질문하기
- 답변을 복사, 저장, 공유하거나 다시 생성하기
- 설정에서 Gemini API Key, 모델, 기본 프롬프트, 테마, 애니메이션 조정하기
- 메뉴바 아이콘에서 일시 중지, 다시 시작, 설정 열기, 종료하기

## 지원 파일

Nudge는 아래 파일을 Gemini로 분석할 수 있습니다.

- 이미지: `png`, `jpg`, `jpeg`, `webp`, `heic`
- 문서: `pdf`, `docx`, `pptx`, `xlsx`
- 텍스트/마크다운: `txt`, `md`
- 코드: `swift`, `kt`, `js`, `ts`, `tsx`, `jsx`, `py`, `java`, `c`, `cpp`, `h`, `hpp`, `json`, `xml`, `html`, `css`, `yml`, `yaml`

큰 이미지와 PDF는 Gemini Files API를 사용해 업로드 후 분석합니다.
PDF는 Gemini 제한에 맞춰 최대 50MB 또는 1000페이지까지 지원합니다.

## 설치 및 실행

현재는 배포용 앱 파일이 아니라, Xcode에서 직접 빌드해 실행하는 개발 버전입니다.

### 1. 저장소 받기

```bash
git clone https://github.com/leesunkwon/Nudge.git
cd Nudge
```

### 2. Gemini API Key 준비

Google AI Studio에서 Gemini API Key를 발급받습니다.

- [Google AI Studio](https://aistudio.google.com/app/apikey)

### 3. 로컬 Secret 파일 만들기

저장소에는 실제 키를 넣지 않습니다.
예시 파일을 복사해서 로컬 전용 설정 파일을 만듭니다.

```bash
cp Nudge/Secrets.xcconfig.example Nudge/Secrets.xcconfig
```

`Nudge/Secrets.xcconfig`를 열고 Gemini API Key를 입력합니다.

```text
GEMINI_API_KEY = 여기에_발급받은_키
```

`Secrets.xcconfig`는 Git에 포함되지 않아야 합니다.

### 4. Xcode에서 실행하기

```bash
open Nudge/Nudge.xcodeproj
```

Xcode에서 `Nudge` scheme을 선택한 뒤 실행합니다.

처음 실행 후 메뉴바의 Nudge 아이콘 또는 Result 패널의 설정 메뉴에서 Gemini API Key를 Keychain에 저장할 수도 있습니다.
앱은 Keychain에 저장된 키를 우선 사용합니다.

## 사용 방법

### 질문하기

1. 화면 상단 노치 근처에 마우스를 올립니다.
2. 입력창이 열리면 질문을 입력합니다.
3. `Enter`로 제출합니다.
4. `Shift + Enter` 또는 `Option + Enter`로 줄바꿈할 수 있습니다.

### 파일 분석하기

1. 이미지, PDF, 문서, 코드 파일을 노치로 드래그합니다.
2. 파일 질문 입력창이 열리면 원하는 질문을 입력합니다.
3. 질문 없이 제출하면 기본 분석 프롬프트로 분석합니다.
4. 결과가 나오면 아래 입력창에서 후속 질문을 이어갈 수 있습니다.

### 메뉴바에서 제어하기

메뉴바의 Nudge 아이콘에서 다음 작업을 할 수 있습니다.

- 현재 모델 확인
- Nudge 일시 중지 / 다시 시작
- 설정 열기
- 앱 종료

## 설정

설정 창에서는 다음 항목을 변경할 수 있습니다.

- Gemini API Key
- Gemini 모델: 자동, 빠름, 고급
- 기본 프롬프트
- Hover 민감도와 닫힘 지연 시간
- 노치 테마: Nudge 기본, Gemini Glow, Mono, Glass
- 애니메이션 속도와 글로우 강도
- 설정 초기화

모델을 `자동`으로 두면 짧은 질문은 빠른 모델을, 긴 문서/코드/다중 파일 분석은 고급 모델을 사용합니다.

## 개발자용 빌드 확인

```bash
xcodebuild -project Nudge/Nudge.xcodeproj \
  -scheme Nudge \
  -configuration Debug \
  -derivedDataPath /tmp/NudgeDerivedData \
  CODE_SIGNING_ALLOWED=NO \
  build
```

## 기술 스택

- Swift
- SwiftUI
- AppKit
- Google Gemini REST API
- Gemini Files API
- Keychain Services
- UserDefaults

## 주의사항

- Nudge는 MacBook 노치 환경에 맞춰 설계된 macOS 앱입니다.
- Gemini API 사용량에 따라 Google 계정에 비용이 발생할 수 있습니다.
- 실제 API Key와 `Secrets.xcconfig`는 Git에 커밋하지 않습니다.
