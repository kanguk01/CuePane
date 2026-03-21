# CuePane Architecture

## 목표 구조

CuePane는 `윈도우 인벤토리`, `문맥 캡처`, `앵커 저장소`, `리콜 엔진`, `오버레이 UI` 다섯 층으로 나뉜다.

## 모듈

### App

- `CuePaneApp`: 메뉴바 앱 진입점
- `AppDelegate`: accessory 앱 설정

### Domain

- 디스플레이/좌표 데이터 모델
- 앵커, 문맥 스냅샷, 복원 결과 모델

### Services

- `AccessibilityPermissionManager`: 손쉬운 사용 권한 확인 및 설정 이동
- `GlobalHotKeyManager`: 검색/이름 붙이기 단축키 등록
- `WindowCatalogService`: 현재 visible window 목록과 AX 조작 담당
- `ContextCaptureService`: 앵커 기준 같은 모니터 문맥 저장
- `AnchorStore`: 로컬 JSON 저장소
- `RecallCoordinator`: 라이브 윈도우 매칭, 포커스, 이동
- `AppModel`: 앱 상태, UI 액션, 서비스 조율
- `WindowCoordinator`: 검색/이름 편집/온보딩 패널 관리

### Features

- `MenuBar`: 상태, 권한, 최근 앵커, 주요 액션
- `Search`: 검색 오버레이와 결과 액션
- `Settings`: 저장소와 동작 설명
- `Onboarding`: 권한 및 기본 사용 흐름 안내

## 데이터 흐름

1. 사용자가 현재 창 이름 붙이기 실행
2. `WindowCatalogService`가 현재 포커스 창을 찾음
3. `ContextCaptureService`가 같은 디스플레이의 visible window snapshot을 생성
4. `AnchorStore`가 앵커를 저장
5. 검색 시 `AppModel`이 저장 앵커를 불러오고 라이브 상태를 계산
6. 복원 시 `RecallCoordinator`가 현재 라이브 창과 저장 snapshot을 매칭
7. 복원 성공 시 각 창을 raise하거나 목표 디스플레이로 이동 후 raise

## 저장 전략

- `Application Support/CuePane/anchors.json`
- 저장 단위는 앵커 배열
- 앱 종료와 무관하게 로컬 유지

## 복원 전략

- 기본 동작은 `문맥 전체 복원`
- `앵커만 복원`은 앵커 snapshot 하나만 매칭
- `여기로 가져오기`는 현재 마우스가 위치한 디스플레이를 목표로 사용
- 문맥 복원은 보조 창을 먼저 raise하고 앵커를 마지막에 raise

## 매칭 전략

- 번들 ID 우선 일치
- 정규화된 제목 exact match 우선
- 제목 토큰 겹침 보조 가중치
- 창 크기/위치 근접도 보조 가중치

## 제약

- AX API 특성상 일부 앱은 창 이동/포커스 품질이 다를 수 있다
- Stage Manager 상태는 best-effort만 가능하다
