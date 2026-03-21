import SwiftUI

struct MenuBarContentView: View {
    @EnvironmentObject private var appModel: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            permissionBanner
            statusSection
            primaryActions
            recentAnchorsSection
            footerActions
        }
        .padding(16)
        .frame(width: 380)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("CuePane")
                .font(.headline)
            Text("이름 붙인 창으로 작업 문맥을 다시 부릅니다.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var permissionBanner: some View {
        if !appModel.accessibilityGranted {
            VStack(alignment: .leading, spacing: 8) {
                Text("손쉬운 사용 권한이 있어야 현재 창을 읽고 복원할 수 있습니다.")
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
    }

    private var statusSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            statusRow(title: "현재 화면", value: appModel.topologySummary)
            statusRow(title: "보이는 창", value: "\(appModel.liveWindowCount)개")
            statusRow(title: "저장된 앵커", value: "\(appModel.anchorCount)개")
            statusRow(title: "최근 상태", value: appModel.lastActionSummary)
        }
    }

    private var primaryActions: some View {
        VStack(spacing: 8) {
            Button {
                appModel.openSearch()
            } label: {
                Label("검색 열기", systemImage: "magnifyingglass")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)

            Button {
                appModel.beginNamingCurrentWindow()
            } label: {
                Label("현재 창 이름 붙이기", systemImage: "tag")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        }
    }

    @ViewBuilder
    private var recentAnchorsSection: some View {
        if !appModel.recentPresentations.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("최근 앵커")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                ForEach(appModel.recentPresentations) { presentation in
                    HStack(alignment: .top, spacing: 10) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(presentation.record.name)
                                .font(.subheadline.weight(.semibold))
                            Text("\(presentation.record.totalWindowCount)개 창 · \(presentation.statusLabel)")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }

                        Spacer(minLength: 0)

                        Button("문맥") {
                            appModel.recall(presentation, mode: .context, destination: .originalDisplay)
                        }
                        .font(.caption)
                        .buttonStyle(.bordered)
                    }
                }
            }
        }
    }

    private var footerActions: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("단축키: \(GlobalHotKeyAction.toggleSearch.displayString) 검색 · \(GlobalHotKeyAction.nameCurrentWindow.displayString) 이름 붙이기")
                .font(.caption2)
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                Button("저장소") {
                    appModel.openStorageDirectory()
                }
                .font(.caption)

                Button("가이드") {
                    appModel.openOnboarding()
                }
                .font(.caption)

                SettingsLink {
                    Label("설정", systemImage: "gearshape")
                }
                .font(.caption)
            }

            Button(role: .destructive) {
                appModel.quit()
            } label: {
                Label("종료", systemImage: "power")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        }
    }

    private func statusRow(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption)
                .lineLimit(2)
        }
    }
}
