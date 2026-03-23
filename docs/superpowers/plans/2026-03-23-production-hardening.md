# CuePane 프로덕션 고도화 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** CuePane을 디버그 코드 제거, 성능 최적화, UX 피드백, 자동 실행, 코드 품질 강화를 통해 프로덕션 레벨로 끌어올린다.

**Architecture:** 기존 구조(AppModel → Services → UI) 유지. 디버그 코드 제거 → 성능 최적화 → UX 개선 → 시스템 통합 → 코드 품질 순서로 진행. 각 태스크는 독립적으로 커밋 가능.

**Tech Stack:** Swift, SwiftUI, AppKit, Accessibility API, CGWindowList, CGEvent

---

## File Map

| 파일 | 역할 | 변경 내용 |
|------|------|----------|
| `Services/AppModel.swift` | 앱 상태 관리 | writeDiag 제거, 토스트 상태 추가, CGWindowList 캐시 |
| `Services/WindowCatalogService.swift` | 창 조회 | print 제거, allSystemWindows 캐시, 검색 창 열기 최적화 |
| `Services/RecallCoordinator.swift` | 복원 매칭 | presentation() 캐시 적용 |
| `Features/Search/SearchOverlayView.swift` | 검색 UI | 토스트 표시, 빈 상태 가이드, 단축키 힌트 |
| `Features/Search/NameWindowView.swift` | 이름 붙이기 UI | 토스트 표시 |
| `App/AppDelegate.swift` | 앱 생명주기 | Login Items 등록 |
| `Features/Settings/SettingsView.swift` | 설정 | 자동 실행 토글, 앵커 만료 설정 |
| `Support/CuePaneChrome.swift` | UI 컴포넌트 | 토스트 뷰 컴포넌트 |
| `Services/WindowCoordinator.swift` | 창 관리 | 검색 창 프리로드 |

---

## Task 1: 디버그 코드 제거

**Files:**
- Modify: `Sources/CuePane/Services/AppModel.swift`
- Modify: `Sources/CuePane/Services/WindowCatalogService.swift`

- [ ] **Step 1: AppModel에서 writeDiag 관련 코드 전부 제거**

`writeDiag()` 메서드 정의, 모든 `writeDiag(...)` 호출, `debugEvents`/`debugEventPreview`/`debugCapturedWindows`/`lastNamingSubmitSource`/`recordDebug()` 중 진단 전용 항목 제거. `recordDebug()`는 `lastActionSummary` 업데이트에 사용되므로 유지하되 `debugEvents` 배열 자체는 제거.

- [ ] **Step 2: WindowCatalogService에서 print 문 전부 제거**

`print("[CuePane]")` 로 시작하는 9개 라인 모두 제거.

- [ ] **Step 3: 빌드 확인**

Run: `swift build 2>&1 | grep -E 'error:|Build complete'`
Expected: `Build complete!`

- [ ] **Step 4: 커밋**

```bash
git add Sources/CuePane/Services/AppModel.swift Sources/CuePane/Services/WindowCatalogService.swift
git commit -m "chore: 디버그 코드 및 진단 로그 제거"
```

---

## Task 2: 검색 창 열기 성능 최적화

**Files:**
- Modify: `Sources/CuePane/Services/WindowCoordinator.swift`
- Modify: `Sources/CuePane/Services/AppModel.swift`

현재 `⌘⇧Space` → `showSearch()` → `present()` → `NSWindow` 생성 + `NSHostingController` 생성 + `NSApp.activate()` 체인이 느림.

- [ ] **Step 1: WindowCoordinator에서 검색 창 프리로드**

`start()` 시점에 검색 창을 미리 생성해두고, `showSearch` 시에는 content 교체 + `makeKeyAndOrderFront`만 수행. 창 생성 비용을 앱 시작 시 1회로 분산.

```swift
// WindowCoordinator.swift - present() 내부
// 기존: 매번 NSHostingController 새로 생성
// 변경: 기존 hostingController의 rootView만 교체
if let existing = windows[id], let window = existing.window {
    if let hosting = window.contentViewController as? NSHostingController<AnyView> {
        hosting.rootView = sizedContent
    } else {
        window.contentViewController = hostingController
    }
    ...
}
```

- [ ] **Step 2: refreshCatalogSnapshot 호출 최적화**

`openSearch()` 에서 `refreshCatalogSnapshot()` 호출 시 `fetchWindows` + 모든 앵커의 `presentation()` 계산이 동기로 실행됨. `presentation()`이 `allSystemWindows()`를 호출하면 CGWindowList를 앵커 수만큼 반복 호출.

변경: `refreshCatalogSnapshot()` 내부에서 `allSystemWindows`를 1회만 호출하고 결과를 `presentation()`에 전달.

```swift
// RecallCoordinator.swift
func presentation(for record: AnchorRecord, topology: DisplayTopology, excludedBundleIDs: Set<String>, cachedSystemWindows: [WindowCatalogService.CrossSpaceWindow]? = nil) -> AnchorPresentation {
    ...
    if !anchorLive {
        let systemWindows = cachedSystemWindows ?? windowCatalog.allSystemWindows(excludedBundleIDs: excludedBundleIDs)
        ...
    }
}

// AppModel.swift - refreshCatalogSnapshot()
let systemWindows = windowCatalog.allSystemWindows(excludedBundleIDs: preferences.excludedBundleIDSet)
presentations = sortedPresentations(
    anchors.map {
        recallCoordinator.presentation(for: $0, topology: topology, excludedBundleIDs: preferences.excludedBundleIDSet, cachedSystemWindows: systemWindows)
    }
)
```

- [ ] **Step 3: 빌드 + 검색 창 열기 체감 확인**

Run: `swift build && pkill -x CuePane; ./scripts/build_dmg.sh && ...install...`
Expected: `⌘⇧Space` 반응이 체감 빨라짐

- [ ] **Step 4: 커밋**

```bash
git commit -am "perf: 검색 창 열기 및 CGWindowList 호출 최적화"
```

---

## Task 3: 토스트 피드백 시스템

**Files:**
- Modify: `Sources/CuePane/Support/CuePaneChrome.swift`
- Modify: `Sources/CuePane/Services/AppModel.swift`
- Modify: `Sources/CuePane/Features/Search/SearchOverlayView.swift`
- Modify: `Sources/CuePane/Features/Search/NameWindowView.swift`

현재 `lastActionSummary` 텍스트만 있고 시각적 피드백 없음.

- [ ] **Step 1: AppModel에 토스트 상태 추가**

```swift
@Published private(set) var toastMessage: String?

func showToast(_ message: String) {
    toastMessage = message
    Task { @MainActor in
        try? await Task.sleep(for: .seconds(2))
        if toastMessage == message {
            toastMessage = nil
        }
    }
}
```

저장 성공, 복원 완료, 삭제 등 주요 액션에서 `showToast()` 호출.

- [ ] **Step 2: CuePaneChrome에 ToastView 추가**

```swift
struct CuePaneToast: View {
    let message: String
    var body: some View {
        Text(message)
            .font(.subheadline.weight(.medium))
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.regularMaterial, in: Capsule())
            .shadow(color: .black.opacity(0.1), radius: 8)
            .transition(.move(edge: .bottom).combined(with: .opacity))
    }
}
```

- [ ] **Step 3: SearchOverlayView / NameWindowView에 토스트 오버레이 적용**

검색/이름 뷰 하단에 `toastMessage`가 있을 때 `CuePaneToast` 표시.

- [ ] **Step 4: 빌드 + 동작 확인**

- [ ] **Step 5: 커밋**

```bash
git commit -am "feat: 토스트 피드백 시스템 추가"
```

---

## Task 4: 빈 상태 가이드 및 단축키 힌트

**Files:**
- Modify: `Sources/CuePane/Features/Search/SearchOverlayView.swift`

- [ ] **Step 1: 빈 상태(앵커 0개) 가이드 개선**

현재 "결과 없음" + "현재 창 이름 붙이기" 버튼만 있음. 앵커가 아예 없을 때는 사용법 가이드 표시:

```swift
if appModel.anchors.isEmpty {
    VStack(spacing: 12) {
        Text("저장된 앵커가 없습니다")
            .font(.headline)
        Text("⌘⇧N으로 현재 창에 이름을 붙여보세요.\n같은 모니터의 작업 문맥이 함께 저장됩니다.")
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
    }
}
```

- [ ] **Step 2: 검색 필드 하단에 단축키 힌트**

검색 결과가 있을 때 하단에 작게: `↑↓ 이동  ↵ 복원  ⌫ 삭제  esc 닫기`

- [ ] **Step 3: 빌드 + 확인**

- [ ] **Step 4: 커밋**

```bash
git commit -am "feat: 빈 상태 가이드 및 단축키 힌트 추가"
```

---

## Task 5: Login Items (시작 시 자동 실행)

**Files:**
- Modify: `Sources/CuePane/App/AppDelegate.swift`
- Modify: `Sources/CuePane/Features/Settings/SettingsView.swift`

- [ ] **Step 1: AppDelegate에 SMAppService import 및 등록**

```swift
import ServiceManagement

// applicationDidFinishLaunching에서:
if #available(macOS 13.0, *) {
    try? SMAppService.mainApp.register()
}
```

- [ ] **Step 2: SettingsView에 자동 실행 토글 추가**

```swift
if #available(macOS 13.0, *) {
    Toggle("맥 시작 시 자동 실행", isOn: Binding(
        get: { SMAppService.mainApp.status == .enabled },
        set: { newValue in
            if newValue { try? SMAppService.mainApp.register() }
            else { try? SMAppService.mainApp.unregister() }
        }
    ))
}
```

- [ ] **Step 3: 빌드 + 확인**

- [ ] **Step 4: 커밋**

```bash
git commit -am "feat: Login Items 자동 실행 지원"
```

---

## Task 6: 다크모드 검증 및 수정

**Files:**
- Modify: `Sources/CuePane/Support/CuePaneChrome.swift` (필요 시)
- Modify: UI 파일들 (필요 시)

- [ ] **Step 1: 다크모드에서 앱 실행 및 스크린샷 비교**

시스템 설정에서 다크모드 전환 후:
- 검색 오버레이
- 이름 붙이기 패널
- 메뉴바 팝오버
- 설정 뷰

각각 시각적 문제 확인.

- [ ] **Step 2: 하드코딩된 색상을 시스템 색상으로 교체 (필요 시)**

`CuePaneChrome`의 색상이 `.ultraThinMaterial` 위에서 다크모드에서도 잘 보이는지 확인. `mint`, `amber`, `danger` 색상은 밝기 조정이 필요할 수 있음.

- [ ] **Step 3: 빌드 + 다크모드 재확인**

- [ ] **Step 4: 커밋**

```bash
git commit -am "fix: 다크모드 UI 호환성 수정"
```

---

## Task 7: 앵커 자동 정리 옵션

**Files:**
- Modify: `Sources/CuePane/Domain/Models.swift` (CuePanePreferences)
- Modify: `Sources/CuePane/Services/AppModel.swift`
- Modify: `Sources/CuePane/Features/Settings/SettingsView.swift`

- [ ] **Step 1: CuePanePreferences에 만료 설정 추가**

```swift
var anchorExpirationDays: Int = 0 // 0 = 만료 안 함
```

- [ ] **Step 2: AppModel.start()에서 만료된 앵커 자동 제거**

```swift
if preferences.anchorExpirationDays > 0 {
    let cutoff = Calendar.current.date(byAdding: .day, value: -preferences.anchorExpirationDays, to: Date())!
    let filtered = anchors.filter { $0.updatedAt > cutoff }
    if filtered.count < anchors.count {
        _ = commitAnchors(filtered)
    }
}
```

- [ ] **Step 3: SettingsView에 만료 설정 UI**

```swift
Picker("앵커 자동 정리", selection: $preferences.anchorExpirationDays) {
    Text("사용 안 함").tag(0)
    Text("7일 후").tag(7)
    Text("30일 후").tag(30)
    Text("90일 후").tag(90)
}
```

- [ ] **Step 4: 빌드 + 확인**

- [ ] **Step 5: 커밋**

```bash
git commit -am "feat: 앵커 자동 만료 정리 옵션"
```

---

## Task 8: RecallCoordinator 스코어링 유닛 테스트

**Files:**
- Create: `Tests/CuePaneTests/RecallCoordinatorTests.swift`
- Modify: `Package.swift` (testTarget 추가)

- [ ] **Step 1: Package.swift에 테스트 타겟 추가**

```swift
.testTarget(
    name: "CuePaneTests",
    dependencies: ["CuePane"]
)
```

RecallCoordinator의 `score()` 메서드를 `internal`로 변경하여 테스트 접근 가능하게.

- [ ] **Step 2: 스코어링 테스트 작성**

```swift
import Testing
@testable import CuePane

struct RecallCoordinatorTests {
    @Test func exactTitleMatchScoresHighest() {
        // 같은 타이틀 → 높은 점수
    }

    @Test func differentTitleSameAppScoresLow() {
        // 같은 bundleID, 다른 타이틀 → 낮은 점수
    }

    @Test func windowNumberExactMatchReturns200() {
        // CGWindowID 정확 매칭 → 200점
    }

    @Test func tokenOverlapPartialMatch() {
        // 토큰 일부 겹침 → 중간 점수
    }
}
```

- [ ] **Step 3: 테스트 실행**

Run: `swift test 2>&1 | tail -5`
Expected: 모든 테스트 PASS

- [ ] **Step 4: 커밋**

```bash
git commit -am "test: RecallCoordinator 스코어링 유닛 테스트"
```

---

## Task 9: 최종 정리 및 릴리즈 빌드

**Files:**
- Modify: 전체 (미사용 import, 경고 제거)

- [ ] **Step 1: 컴파일 경고 전부 제거**

Run: `swift build 2>&1 | grep warning:` 로 확인 후 모두 수정.

- [ ] **Step 2: 미사용 코드 정리**

`CuePaneAutoFocusTextField`의 미사용 `submit()` 메서드, 미사용 `import` 등 정리.

- [ ] **Step 3: 릴리즈 빌드 + DMG 생성**

```bash
./scripts/build_dmg.sh
```

- [ ] **Step 4: 최종 설치 + 전체 시나리오 테스트**

1. 앱 시작 → 메뉴바 아이콘 확인
2. ⌘⇧N → 이름 붙이기 → 저장 → 토스트
3. ⌘⇧Space → 검색 → 방향키 → Enter → 복원
4. 다른 Space 앵커 복원
5. 다크모드 전환 확인
6. 설정 → 자동 실행 토글

- [ ] **Step 5: 최종 커밋**

```bash
git commit -am "chore: 프로덕션 릴리즈 정리"
```
