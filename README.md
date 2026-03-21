# CuePane

이름 붙인 윈도우를 검색하고, 그 윈도우가 속했던 같은 모니터의 작업 문맥까지 다시 불러오는 macOS 메뉴바 앱입니다.

## 핵심 개념

- `앵커`: 사용자가 이름을 붙인 기준 윈도우
- `문맥`: 앵커를 저장할 때 같은 모니터에 보이던 다른 일반 윈도우들
- `문맥 복원`: 앵커와 그 주변 윈도우들을 함께 다시 앞으로 가져오는 동작

예시:

- 터미널 창에 `서버로그`라고 이름을 붙임
- 같은 모니터에 Slack이 함께 떠 있음
- 나중에 `서버로그`를 검색
- 기본 동작으로 터미널과 Slack을 같이 다시 불러옴

## MVP 범위

- 메뉴바 앱
- 손쉬운 사용 권한 기반 윈도우 열거
- 현재 활성 윈도우 이름 붙이기
- 같은 모니터 문맥 스냅샷 저장
- Spotlight 스타일 검색 오버레이
- `문맥 복원`, `앵커만 복원`, `현재 디스플레이로 가져오기`
- 문맥 업데이트
- 로컬 JSON 저장소

## 단축키

- `⌘⇧Space`: 검색 오버레이 열기
- `⌘⇧N`: 현재 활성 윈도우 이름 붙이기

## 개발

```bash
swift build
swift run CuePane
```

## 로컬 패키징

```bash
./scripts/build_dmg.sh
```

DMG는 `/Users/kanguklee/CuePane/dist/CuePane.dmg`에 생성됩니다.
기본값은 로컬 ad-hoc 서명이고, 별도 인증서로 서명하려면 `CUEPANE_SIGNING_IDENTITY`를 지정하면 됩니다.

아이콘만 다시 생성하려면:

```bash
./scripts/generate_app_icon.sh
```

## 구조

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

## 문서

- [PRD](/Users/kanguklee/CuePane/docs/PRD.md)
- [Architecture](/Users/kanguklee/CuePane/docs/ARCHITECTURE.md)

## 상태

MVP 구현 중. 현재 버전은 macOS 손쉬운 사용 권한을 전제로 동작합니다.

## License

Private — All rights reserved.
