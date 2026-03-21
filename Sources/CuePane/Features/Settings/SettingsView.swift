import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var appModel: AppModel

    var body: some View {
        Form {
            Section("자동화") {
                Toggle(
                    "레이아웃 자동 저장",
                    isOn: Binding(
                        get: { appModel.preferences.autoCaptureEnabled },
                        set: { appModel.preferences.autoCaptureEnabled = $0 }
                    )
                )
                Toggle(
                    "디스플레이 변경 시 자동 복원",
                    isOn: Binding(
                        get: { appModel.preferences.autoRestoreEnabled },
                        set: { appModel.preferences.autoRestoreEnabled = $0 }
                    )
                )

                VStack(alignment: .leading) {
                    Text("자동 저장 주기: \(appModel.preferences.captureIntervalSeconds, specifier: "%.1f")초")
                    Slider(
                        value: Binding(
                            get: { appModel.preferences.captureIntervalSeconds },
                            set: { appModel.preferences.captureIntervalSeconds = $0 }
                        ),
                        in: 2...15,
                        step: 1
                    )
                }

                VStack(alignment: .leading) {
                    Text("자동 복원 지연: \(appModel.preferences.restoreDelaySeconds, specifier: "%.1f")초")
                    Slider(
                        value: Binding(
                            get: { appModel.preferences.restoreDelaySeconds },
                            set: { appModel.preferences.restoreDelaySeconds = $0 }
                        ),
                        in: 0.5...4,
                        step: 0.5
                    )
                }

                Toggle(
                    "복원 후 좌표 검증",
                    isOn: Binding(
                        get: { appModel.preferences.verifyRestoreEnabled },
                        set: { appModel.preferences.verifyRestoreEnabled = $0 }
                    )
                )

                Picker(
                    "매칭 모드",
                    selection: Binding(
                        get: { appModel.preferences.matchingMode },
                        set: { appModel.preferences.matchingMode = $0 }
                    )
                ) {
                    ForEach(MatchingMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }

                Text(appModel.preferences.matchingMode.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("로그인 시 실행") {
                Toggle(
                    "로그인 시 자동 실행",
                    isOn: Binding(
                        get: { appModel.launchAtLoginEnabled },
                        set: { appModel.setLaunchAtLoginEnabled($0) }
                    )
                )

                Text(appModel.launchAtLoginStatus)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Button("온보딩 열기") {
                    appModel.openOnboardingWindow()
                }

                Button("진단 창 열기") {
                    appModel.openDiagnosticsWindow()
                }
            }

            Section("제외 앱") {
                Text("한 줄에 번들 ID 하나씩 입력합니다.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextEditor(
                    text: Binding(
                        get: { appModel.preferences.excludedBundleIdentifiers },
                        set: { appModel.preferences.excludedBundleIdentifiers = $0 }
                    )
                )
                .font(.system(.body, design: .monospaced))
                .frame(minHeight: 120)
            }

            Section("상태") {
                LabeledContent("현재 화면", value: appModel.topologySummary)
                LabeledContent("현재 보이는 창", value: "\(appModel.liveWindowCount)개")
                LabeledContent("저장된 프로필 창", value: "\(appModel.currentProfileWindowCount)개")
                LabeledContent("마지막 저장", value: appModel.lastSavedSummary)
                LabeledContent("마지막 복원", value: appModel.lastRestoreSummary)
            }
        }
        .padding(20)
        .frame(width: 560, height: 560)
    }
}
