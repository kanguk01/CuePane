import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var appModel: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            CuePaneSurface {
                VStack(alignment: .leading, spacing: 6) {
                    Text("CuePane 설정")
                        .font(.title2.weight(.bold))
                    Text("단축키, 제외 앱, 로컬 저장소 동작을 이곳에서 정리합니다.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            Form {
                Section("단축키") {
                    LabeledContent("검색 오버레이", value: GlobalHotKeyAction.toggleSearch.displayString)
                    LabeledContent("현재 창 이름 붙이기", value: GlobalHotKeyAction.nameCurrentWindow.displayString)

                    Toggle(
                        "앱 실행 시 가이드 열기",
                        isOn: Binding(
                            get: { appModel.preferences.showOnboardingOnLaunch },
                            set: { appModel.preferences.showOnboardingOnLaunch = $0 }
                        )
                    )
                }

                Section("제외 앱") {
                    Text("문맥 저장과 검색에서 제외할 번들 ID를 한 줄에 하나씩 입력합니다.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextEditor(
                        text: Binding(
                            get: { appModel.preferences.excludedBundleIdentifiers },
                            set: { appModel.preferences.excludedBundleIdentifiers = $0 }
                        )
                    )
                    .font(.system(.body, design: .monospaced))
                    .frame(minHeight: 140)
                }

                Section("상태") {
                    LabeledContent("현재 화면", value: appModel.topologySummary)
                    LabeledContent("보이는 창", value: "\(appModel.liveWindowCount)개")
                    LabeledContent("저장된 앵커", value: "\(appModel.anchorCount)개")
                    LabeledContent("최근 상태", value: appModel.lastActionSummary)
                }

                Section("관리") {
                    Button("저장소 폴더 열기") {
                        appModel.openStorageDirectory()
                    }

                    Button("손쉬운 사용 설정 열기") {
                        appModel.openAccessibilitySettings()
                    }

                    Button("가이드 다시 보기") {
                        appModel.openOnboarding()
                    }
                }
            }
            .formStyle(.grouped)
        }
        .padding(20)
        .frame(width: 560, height: 600)
        .background(CuePaneWindowBackground())
    }
}
