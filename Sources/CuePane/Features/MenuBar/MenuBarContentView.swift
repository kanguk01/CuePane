import SwiftUI

struct MenuBarContentView: View {
    @EnvironmentObject private var appModel: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                header
                permissionBanner
                statusSection
                primaryActions
                recentAnchorsSection
                footerActions
            }
            .padding(16)
        }
        .frame(width: 400, height: 560)
        .background(CuePaneWindowBackground())
    }

    private var header: some View {
        CuePaneSurface {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: "tag.square.fill")
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(CuePaneChrome.accent)
                    .frame(width: 42, height: 42)
                    .background(CuePaneChrome.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))

                VStack(alignment: .leading, spacing: 5) {
                    Text("CuePane")
                        .font(.title3.weight(.bold))
                    Text("이름 붙인 창으로 작업 문맥을 다시 부릅니다.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    HStack(spacing: 8) {
                        CuePaneStatusBadge(
                            title: appModel.accessibilityGranted ? "권한 허용됨" : "권한 필요",
                            color: appModel.accessibilityGranted ? CuePaneChrome.mint : CuePaneChrome.amber
                        )
                        CuePaneStatusBadge(
                            title: "\(appModel.anchorCount)개 앵커",
                            color: CuePaneChrome.accent
                        )
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var permissionBanner: some View {
        if !appModel.accessibilityGranted {
            CuePaneSurface {
                VStack(alignment: .leading, spacing: 10) {
                    Label("손쉬운 사용 권한이 있어야 현재 창을 읽고 복원할 수 있습니다.", systemImage: "hand.raised.fill")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(CuePaneChrome.amber)

                    HStack {
                        Button("권한 요청") {
                            appModel.requestAccessibility()
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(CuePaneChrome.amber)

                        Button("설정 열기") {
                            appModel.openAccessibilitySettings()
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }
        }
    }

    private var statusSection: some View {
        CuePaneSurface {
            VStack(alignment: .leading, spacing: 12) {
                Text("현재 상태")
                    .font(.headline)

                HStack(spacing: 12) {
                    CuePaneMetricTile(label: "보이는 창", value: "\(appModel.liveWindowCount)")
                    CuePaneMetricTile(label: "앵커", value: "\(appModel.anchorCount)")
                }

                Divider()

                statusRow(title: "현재 화면", value: appModel.topologySummary)
                statusRow(title: "최근 상태", value: appModel.lastActionSummary)
            }
        }
    }

    private var primaryActions: some View {
        CuePaneSurface {
            VStack(alignment: .leading, spacing: 12) {
                Text("빠른 실행")
                    .font(.headline)

                HStack(spacing: 8) {
                    CuePaneShortcutBadge(title: GlobalHotKeyAction.toggleSearch.displayString)
                    Text("검색 오버레이")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Button {
                    appModel.openSearch()
                } label: {
                    Label("검색 열기", systemImage: "magnifyingglass")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(CuePaneChrome.accent)

                Button {
                    appModel.beginNamingCurrentWindow()
                } label: {
                    Label("현재 창 이름 붙이기", systemImage: "tag")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
        }
    }

    @ViewBuilder
    private var recentAnchorsSection: some View {
        if !appModel.recentPresentations.isEmpty {
            CuePaneSurface {
                VStack(alignment: .leading, spacing: 10) {
                    Text("최근 앵커")
                        .font(.headline)

                    ForEach(appModel.recentPresentations) { presentation in
                        HStack(alignment: .top, spacing: 12) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(presentation.record.name)
                                    .font(.subheadline.weight(.semibold))
                                Text("\(presentation.record.totalWindowCount)개 창 · \(presentation.statusLabel)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer(minLength: 0)

                            Button("문맥") {
                                appModel.recall(presentation, mode: .context, destination: .originalDisplay)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }

                        if presentation.id != appModel.recentPresentations.last?.id {
                            Divider()
                        }
                    }
                }
            }
        }
    }

    private var footerActions: some View {
        CuePaneSurface {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    CuePaneShortcutBadge(title: GlobalHotKeyAction.toggleSearch.displayString)
                    CuePaneShortcutBadge(title: GlobalHotKeyAction.nameCurrentWindow.displayString)
                }

                HStack(spacing: 8) {
                    Button("저장소") {
                        appModel.openStorageDirectory()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    Button("가이드") {
                        appModel.openOnboarding()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    SettingsLink {
                        Label("설정", systemImage: "gearshape")
                    }
                    .controlSize(.small)
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
