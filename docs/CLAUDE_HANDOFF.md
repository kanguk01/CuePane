# CuePane Claude Handoff

## 프로젝트 요약

- 앱 이름: `CuePane`
- 목적: macOS에서 이름 붙인 창과 같은 모니터의 작업 문맥을 저장하고, 검색으로 다시 복원하는 메뉴바 유틸리티
- 핵심 개념:
  - `Anchor`: 이름 붙인 기준 창
  - `Context Snapshot`: 저장 시점에 같은 모니터에 보이던 다른 창들
  - 기본 동작은 `문맥 복원`, 보조 동작은 `창만 복원`, `여기로 가져오기`

제품 기획과 아키텍처 문서는 아래에 정리되어 있다.

- [PRD.md](/Users/kanguklee/CuePane/docs/PRD.md)
- [ARCHITECTURE.md](/Users/kanguklee/CuePane/docs/ARCHITECTURE.md)
- [README.md](/Users/kanguklee/CuePane/README.md)

## 작업 디렉터리와 주요 경로

- 레포 루트: `/Users/kanguklee/CuePane`
- 설치 앱: `/Applications/CuePane.app`
- DMG 출력물: `/Users/kanguklee/CuePane/dist/CuePane.dmg`
- 빌드 스테이징 앱: `/Users/kanguklee/CuePane/.build/dmg-stage/CuePane.app`
- 설치 백업 앱들: `/Users/kanguklee/CuePane/.install-backups`

## 현재 Git 상태

- 최근 커밋:
  - `7a9d42d` `큐패인 외부 앱 전환 캐시 반영`
  - `8b4a90c` `큐패인 외부 창 캐시로 저장 보강`
  - `ce49e35` `큐패인 핫키 창 캡처 경로 보강`
  - `d7e785a` `큐패인 현재 창 캡처 상태 정리`
  - `f15dcf0` `큐패인 저장 디버그 정보 노출`
- 워크트리: 코드 변경 없음
- 미추적 파일: `.install-backups/`

주의:

- 사용자 지침상 커밋 메시지는 한글로 작성해야 한다.
- 푸시는 금지다.
- `.install-backups/`는 커밋 대상이 아니다.

## 핵심 소스 구조

### 앱 진입과 UI

- [CuePaneApp.swift](/Users/kanguklee/CuePane/Sources/CuePane/App/CuePaneApp.swift)
- [AppDelegate.swift](/Users/kanguklee/CuePane/Sources/CuePane/App/AppDelegate.swift)
- [MenuBarContentView.swift](/Users/kanguklee/CuePane/Sources/CuePane/Features/MenuBar/MenuBarContentView.swift)
- [SearchOverlayView.swift](/Users/kanguklee/CuePane/Sources/CuePane/Features/Search/SearchOverlayView.swift)
- [NameWindowView.swift](/Users/kanguklee/CuePane/Sources/CuePane/Features/Search/NameWindowView.swift)
- [SettingsView.swift](/Users/kanguklee/CuePane/Sources/CuePane/Features/Settings/SettingsView.swift)
- [OnboardingView.swift](/Users/kanguklee/CuePane/Sources/CuePane/Features/Onboarding/OnboardingView.swift)
- [WindowCoordinator.swift](/Users/kanguklee/CuePane/Sources/CuePane/Services/WindowCoordinator.swift)

### 도메인과 저장 모델

- [Models.swift](/Users/kanguklee/CuePane/Sources/CuePane/Domain/Models.swift)
- [RestoreModels.swift](/Users/kanguklee/CuePane/Sources/CuePane/Domain/RestoreModels.swift)
- [AnchorRecordUtilities.swift](/Users/kanguklee/CuePane/Sources/CuePane/Domain/AnchorRecordUtilities.swift)

### 창 조회 / 저장 / 복원 핵심 서비스

- [AppModel.swift](/Users/kanguklee/CuePane/Sources/CuePane/Services/AppModel.swift)
- [WindowCatalogService.swift](/Users/kanguklee/CuePane/Sources/CuePane/Services/WindowCatalogService.swift)
- [ContextCaptureService.swift](/Users/kanguklee/CuePane/Sources/CuePane/Services/ContextCaptureService.swift)
- [RecallCoordinator.swift](/Users/kanguklee/CuePane/Sources/CuePane/Services/RecallCoordinator.swift)
- [AnchorStore.swift](/Users/kanguklee/CuePane/Sources/CuePane/Services/AnchorStore.swift)
- [GlobalHotKeyManager.swift](/Users/kanguklee/CuePane/Sources/CuePane/Services/GlobalHotKeyManager.swift)
- [AccessibilityPermissionManager.swift](/Users/kanguklee/CuePane/Sources/CuePane/Services/AccessibilityPermissionManager.swift)

### 지원 컴포넌트

- [CuePaneAutoFocusTextField.swift](/Users/kanguklee/CuePane/Sources/CuePane/Support/CuePaneAutoFocusTextField.swift)
- [CuePaneChrome.swift](/Users/kanguklee/CuePane/Sources/CuePane/Support/CuePaneChrome.swift)
- [WindowTitleNormalizer.swift](/Users/kanguklee/CuePane/Sources/CuePane/Support/WindowTitleNormalizer.swift)
- [MenuBarIconRenderer.swift](/Users/kanguklee/CuePane/Sources/CuePane/Support/MenuBarIconRenderer.swift)

## 지금까지 구현된 기능

- 메뉴바 앱 기본 구조
- 검색 오버레이 `⌘⇧Space`
- 현재 창 이름 붙이기 `⌘⇧N`
- 같은 모니터 문맥 저장
- 문맥 복원 / 창만 복원 / 현재 디스플레이로 가져오기
- 즐겨찾기 / 최근 작업
- JSON import / export
- 로컬 코드서명 기반 DMG 빌드
- 손쉬운 사용 권한 온보딩

## 실제로 남아 있는 치명 버그

### 사용자 재현 시나리오

1. 사용자는 Codex 같은 외부 앱 창을 보고 있다.
2. `⌘⇧N`으로 이름 붙이기 패널을 연다.
3. 이름을 입력하고 `Enter` 또는 `저장` 버튼을 누른다.
4. 기대 결과: 현재 보고 있던 외부 창이 앵커로 저장된다.
5. 실제 결과: 패널 상단은 `저장할 현재 창을 다시 캡처하세요` 또는 `저장 대상 없음`으로 뜨고, 저장이 되지 않는다.

### 관찰된 현상

- `Enter`와 `저장 버튼` 이벤트 자체는 들어온다.
- 저장 함수 `saveNamingDraft()`도 호출된다.
- 실패 지점은 `namingTargetSnapshot == nil` 이다.
- 검색창이 열려 있는 상태에서 이름 붙이기를 누르면, 외부 앱 대신 CuePane 자신이 포커스를 잡아버리는 경향이 있다.
- 외부 창 캐시가 Slack 같은 이전 앱 상태로 남아 있는 사례가 있었다.

## 지금까지 넣은 디버그 / 보정 시도

### 1. 저장 입력 계측

- `Enter`와 `저장 버튼`을 각각 로그로 남김
- 최근 이벤트, 저장 예정 창 목록, 저장된 앵커 이름을 패널에 직접 노출

관련 파일:

- [AppModel.swift](/Users/kanguklee/CuePane/Sources/CuePane/Services/AppModel.swift)
- [NameWindowView.swift](/Users/kanguklee/CuePane/Sources/CuePane/Features/Search/NameWindowView.swift)
- [SearchOverlayView.swift](/Users/kanguklee/CuePane/Sources/CuePane/Features/Search/SearchOverlayView.swift)
- [CuePaneAutoFocusTextField.swift](/Users/kanguklee/CuePane/Sources/CuePane/Support/CuePaneAutoFocusTextField.swift)

### 2. 포커스 창 판별 강화

- `NSWorkspace.frontmostApplication` 기반 판별 외에
- 시스템 전역 AX `kAXFocusedApplicationAttribute` 와 `kAXFocusedWindowAttribute` 우선 사용
- 핫키 순간의 외부 앱 PID도 같이 받아서 우선 탐색

관련 파일:

- [GlobalHotKeyManager.swift](/Users/kanguklee/CuePane/Sources/CuePane/Services/GlobalHotKeyManager.swift)
- [WindowCatalogService.swift](/Users/kanguklee/CuePane/Sources/CuePane/Services/WindowCatalogService.swift)

### 3. stale 상태 제거

- 이름 붙이기 진입 시 예전 `namingTargetSnapshot` / `namingContextSnapshots` 를 즉시 비움
- 캡처 실패 시 이전 Slack 상태가 남아 보이는 문제를 정리

관련 파일:

- [AppModel.swift](/Users/kanguklee/CuePane/Sources/CuePane/Services/AppModel.swift)

### 4. 외부 창 캐시

- 최근 외부 창 스냅샷과 문맥을 캐시
- 검색창이 떠 있어도 마지막 외부 창을 이름 붙이기에서 사용하도록 폴백 추가
- 외부 앱 활성화 알림을 받아 캐시 갱신 시도

관련 파일:

- [AppModel.swift](/Users/kanguklee/CuePane/Sources/CuePane/Services/AppModel.swift)

## 현재 진단에서 읽을 수 있는 결론

현재까지의 로그상 가장 유력한 문제는 이 두 가지 중 하나다.

1. `⌘⇧N` 직전의 외부 앱/창 식별은 일부 성공하지만, 실제 이름 패널이 열릴 때 `namingTargetSnapshot` 이 세팅되기 전에 CuePane 자신이 전면으로 올라오면서 다시 비워진다.
2. 외부 앱 활성화 감지와 캐시 갱신 타이밍이 사용자의 실제 `⌘⇧N` 타이밍보다 늦어서, 최신 외부 창 대신 오래된 캐시 또는 빈 상태가 사용된다.

현재 구현은 방어 로직이 많아졌지만, 근본적으로는 "핫키 누른 순간의 정확한 외부 창 AX 요소를 그대로 잡고 유지"하는 설계가 아직 아니다.

## Claude가 우선 봐야 할 디버깅 포인트

### 최우선

- [AppModel.beginNamingCurrentWindow()](/Users/kanguklee/CuePane/Sources/CuePane/Services/AppModel.swift)
- [AppModel.prepareLiveNamingCandidate()](/Users/kanguklee/CuePane/Sources/CuePane/Services/AppModel.swift)
- [WindowCatalogService.focusedWindow()](/Users/kanguklee/CuePane/Sources/CuePane/Services/WindowCatalogService.swift)
- [GlobalHotKeyManager](/Users/kanguklee/CuePane/Sources/CuePane/Services/GlobalHotKeyManager.swift)

### 확인해야 할 질문

- 핫키가 눌린 그 시점의 `AXUIElement` window reference 자체를 저장해서 후속 단계까지 들고 가야 하는가
- `NameWindowView` 를 띄우기 전에 앵커 캡처를 완료하고, UI는 이미 완성된 draft만 보여주게 바꾸는 편이 맞는가
- 지금의 `Task { @MainActor in ... }` 경로가 핫키 이후 포커스 타이밍을 놓치게 만드는가
- `CGWindowListCopyWindowInfo` 결과와 AX window 매칭을 더 직접적으로 해야 하는가

## 내가 권하는 다음 작업 순서

1. 이름 붙이기 흐름을 "UI 열기 전에 캡처 완료" 구조로 바꾸기
2. `GlobalHotKeyManager`에서 PID뿐 아니라 창 식별에 쓸 수 있는 더 강한 힌트를 얻을 수 있는지 검토
3. `AppModel`의 외부 창 캐시 폴백을 정리하거나 제거하고, 캡처 실패 원인을 더 직접 추적
4. 저장 성공 이후 검색 결과 표시와 이름 패널 자동 닫힘을 다시 검증
5. 버그 해결 후 디버그 패널/로그를 축소 또는 제거

## 빌드 / 실행 / 설치 명령

레포 루트에서:

```bash
swift build
swift run CuePane
./scripts/build_dmg.sh
```

설치 교체에 사용한 명령:

```bash
pkill -x CuePane || true
mv /Applications/CuePane.app /Users/kanguklee/CuePane/.install-backups/CuePane.app.$(date +%Y%m%d-%H%M%S)
cp -R /Users/kanguklee/CuePane/.build/dmg-stage/CuePane.app /Applications/CuePane.app
open -na /Applications/CuePane.app
```

프로세스 확인:

```bash
ps -ax | rg '[C]uePane'
```

## 서명 / 권한 관련 메모

- ad-hoc 대신 로컬 고정 코드서명 `CuePane Local Signer`를 쓰도록 정리했다.
- 그래도 앱을 교체 설치할 때는 권한/TCC가 다시 꼬일 수 있으니 `/Applications/CuePane.app` 기준으로만 설치하는 쪽이 안전하다.

관련 스크립트:

- [build_dmg.sh](/Users/kanguklee/CuePane/scripts/build_dmg.sh)
- [ensure_local_signing_identity.sh](/Users/kanguklee/CuePane/scripts/ensure_local_signing_identity.sh)

## GitHub / 배포 상태

- 원격 레포: [kanguk01/CuePane](https://github.com/kanguk01/CuePane)
- 릴리즈: [v0.1.0](https://github.com/kanguk01/CuePane/releases/tag/v0.1.0)

이번 인수인계 시점에서는 푸시하지 않았다.

## 사용자 피드백 요약

- UI/UX는 네이티브한 느낌으로 정리해 달라는 요구가 있었고, 현재 전체적으로 `material` 기반 맥 유틸 톤으로 맞춰져 있다.
- 하지만 현재 사용자 불만의 핵심은 UI가 아니라 저장 정확도다.
- 사용자는 지금 상태를 강하게 불만족스럽게 느끼고 있고, 특히 `⌘⇧N` 저장 실패를 치명 버그로 보고 있다.

## 결론

이 레포는 기획, UI, 저장소, 복원 엔진, 패키징까지 MVP 구조는 갖춰져 있다.
막혀 있는 건 딱 하나다.

`현재 외부 창을 정확하게 캡처해서 이름 붙이기 저장으로 연결하는 경로`

Claude는 여기만 집중해서 구조를 다시 잡는 게 맞다.
