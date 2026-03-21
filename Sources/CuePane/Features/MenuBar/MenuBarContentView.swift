import SwiftUI

struct MenuBarContentView: View {
    @EnvironmentObject private var appModel: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("CuePane")
                    .font(.headline)
                Text(appModel.topologySummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if !appModel.accessibilityGranted {
                VStack(alignment: .leading, spacing: 8) {
                    Text("손쉬운 사용 권한이 있어야 창 위치를 읽고 복원할 수 있습니다.")
                        .font(.caption)
                        .foregroundStyle(.orange)

                    HStack {
                        Button("권한 요청") {
                            appModel.requestAccessibility()
                        }
                        Button("설정 열기") {
                            appModel.openAccessibilitySettings()
                        }
                    }
                }
                .padding(10)
                .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
            }

            VStack(alignment: .leading, spacing: 8) {
                statusRow(title: "마지막 저장", value: appModel.lastSavedSummary)
                statusRow(title: "마지막 복원", value: appModel.lastRestoreSummary)
                statusRow(title: "보류 복원", value: "\(appModel.pendingRestoreCount)개")
                statusRow(title: "보이는 창", value: "\(appModel.liveWindowCount)개")
            }

            VStack(alignment: .leading, spacing: 10) {
                Toggle(
                    "자동 저장",
                    isOn: Binding(
                        get: { appModel.preferences.autoCaptureEnabled },
                        set: { newValue in
                            appModel.preferences.autoCaptureEnabled = newValue
                        }
                    )
                )
                Toggle(
                    "디스플레이 변경 시 자동 복원",
                    isOn: Binding(
                        get: { appModel.preferences.autoRestoreEnabled },
                        set: { newValue in
                            appModel.preferences.autoRestoreEnabled = newValue
                        }
                    )
                )
            }
            .toggleStyle(.switch)

            HStack(spacing: 8) {
                Button {
                    appModel.captureNow()
                } label: {
                    Label("지금 저장", systemImage: "square.and.arrow.down")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)

                Button {
                    appModel.restoreCurrentTopology()
                } label: {
                    Label("지금 복원", systemImage: "arrow.uturn.backward.circle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }

            HStack(spacing: 8) {
                Button("보류 재시도") {
                    appModel.retryPendingRestores()
                }

                Button("진단") {
                    appModel.openDiagnosticsWindow()
                }

                Button("시작하기") {
                    appModel.openOnboardingWindow()
                }

                SettingsLink {
                    Label("설정", systemImage: "gearshape")
                }
            }
            .font(.caption)

            VStack(alignment: .leading, spacing: 8) {
                Button("프로필 폴더 열기") {
                    appModel.openProfilesDirectory()
                }
                .font(.caption)

                Button("로그 폴더 열기") {
                    appModel.openLogsDirectory()
                }
                .font(.caption)
            }

            if !appModel.recentLogs.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("최근 로그")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                    ForEach(appModel.recentLogs, id: \.self) { line in
                        Text(line)
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                .padding(10)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("매칭 모드: \(appModel.preferences.matchingMode.title)")
                    .font(.caption.weight(.semibold))
                Text(appModel.launchAtLoginStatus)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Button(role: .destructive) {
                appModel.quit()
            } label: {
                Label("종료", systemImage: "power")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        }
        .padding(16)
        .frame(width: 360)
    }

    private func statusRow(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption)
        }
    }
}
