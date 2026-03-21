<div align="center">

<img src="assets/AppIcon.svg" width="128" alt="CuePane">

# CuePane

**Name a window. Recall the whole context.**

Window Context Recall · Favorites · Quick Search · Import / Export

[![Swift 6.2](https://img.shields.io/badge/Swift-6.2-F05138?logo=swift&logoColor=white)](https://swift.org)
[![macOS 14+](https://img.shields.io/badge/macOS-14.0+-000000?logo=apple&logoColor=white)](https://developer.apple.com/macos/)
[![Accessibility API](https://img.shields.io/badge/Accessibility-Native-0A84FF)](https://developer.apple.com/documentation/applicationservices/accessibility)

<br>

[<img src="https://img.shields.io/badge/Download-Latest-28A745?style=for-the-badge&logo=apple&logoColor=white" alt="Download">](https://github.com/kanguk01/CuePane/releases/latest)

</div>

<br>

## Why CuePane?

macOS에서 앱 전환은 쉬워도, **정확한 작업 문맥 복귀**는 의외로 자주 깨집니다.

- 같은 앱 창이 여러 개라서 원하는 창만 바로 못 찾음
- 멀티모니터에서 같이 보던 창 조합이 한 번에 안 돌아옴
- Stage Manager나 일반 창 전환에서 작업 흐름이 자꾸 끊김

CuePane는 여기에 집중합니다.

- **앵커 저장** — 현재 창에 `서버로그`, `PR 482`, `회의 참고자료` 같은 이름을 붙임
- **문맥 캡처** — 저장 시점에 같은 모니터에 함께 보이던 창들을 같이 기억
- **빠른 복원** — 검색창에서 이름만 치면 창 하나 또는 작업 문맥 전체를 다시 호출
- **현재 디스플레이로 가져오기** — 원래 위치 대신 지금 보고 있는 화면으로 불러오기

## Install

### Manual

1. [최신 릴리즈](https://github.com/kanguk01/CuePane/releases/latest)에서 `CuePane.dmg` 다운로드
2. `CuePane.app`을 응용 프로그램 폴더로 드래그
3. 첫 실행 시 손쉬운 사용 권한 허용

> **요구 사항** — macOS 14.0 이상

### Build From Source

```bash
git clone https://github.com/kanguk01/CuePane.git
cd CuePane
swift build
swift run CuePane
```

## Features

### Window Context Recall

현재 창을 앵커로 저장하면, 같은 모니터에 함께 떠 있던 일반 창들이 문맥으로 저장됩니다.

예:

- Terminal `서버로그`
- Slack
- 브라우저 `운영 대시보드`

나중에 `서버로그`를 검색하면 위 문맥을 다시 한 번에 호출할 수 있습니다.

### Search Overlay

`⌘⇧Space`로 Spotlight 스타일 검색 오버레이를 열고:

- 이름으로 찾기
- 앱명으로 찾기
- 현재 창 제목으로 찾기
- `문맥 복원`, `창만`, `여기로` 바로 실행

### Favorites And Recents

- 자주 쓰는 앵커를 즐겨찾기로 상단 고정
- 마지막으로 열었던 작업 문맥을 메뉴바에서 바로 다시 열기
- 실행 횟수와 최근 사용 시각 추적

### Rename Without Re-Capturing

이미 저장한 앵커는 문맥을 다시 캡처하지 않고 이름만 바꿀 수 있습니다.

### Import / Export

앵커를 JSON으로 내보내고 다시 가져올 수 있습니다.

- 다른 맥에 옮기기
- 백업용 보관
- 실험 후 복원

## Keyboard Shortcuts

| Shortcut | Action |
|----------|--------|
| `⌘⇧Space` | 검색 오버레이 열기 |
| `⌘⇧N` | 현재 창 이름 붙이기 |
| `Enter` | 검색 결과 문맥 복원 |
| `Esc` | 검색 / 이름 패널 닫기 |

## Permissions

CuePane는 macOS 손쉬운 사용 권한을 사용합니다.

이 권한이 있어야:

- 현재 보이는 창을 열거하고
- 특정 창을 앞으로 가져오고
- 창 위치를 현재 디스플레이로 이동할 수 있습니다

## Packaging

```bash
./scripts/build_dmg.sh
```

DMG는 `dist/CuePane.dmg`에 생성됩니다.  
기본값은 로컬 ad-hoc 서명이고, 별도 인증서로 서명하려면 `CUEPANE_SIGNING_IDENTITY`를 지정하면 됩니다.

아이콘만 다시 생성하려면:

```bash
./scripts/generate_app_icon.sh
```

## Architecture

```text
Sources/CuePane/
├── App/
├── Domain/
├── Features/
│   ├── MenuBar/
│   ├── Onboarding/
│   ├── Search/
│   └── Settings/
├── Services/
└── Support/
```

핵심 레이어:

- `WindowCatalogService` — AX 기반 현재 창 열거 / 이동 / 포커스
- `ContextCaptureService` — 앵커와 같은 모니터 문맥 저장
- `RecallCoordinator` — 저장 문맥과 현재 라이브 창 매칭 / 복원
- `AnchorStore` — 로컬 JSON 저장소와 가져오기 / 내보내기
- `AppModel` — 검색, 즐겨찾기, 빠른 재호출 흐름 조율

## Current Scope

- 메뉴바 앱
- 같은 모니터 기준 문맥 저장
- 앵커 검색 / 복원 / 업데이트
- 즐겨찾기 / 최근 작업
- JSON import / export

## Limitations

- 탭 단위 복원은 지원하지 않습니다
- Stage Manager 상태를 완전히 제어하지는 않습니다
- 일부 앱은 AX 지원 품질에 따라 복원 정확도가 다를 수 있습니다

## License

Private — All rights reserved.
