import Sparkle
import SwiftUI

struct MenuBarContentView: View {
    @EnvironmentObject private var appModel: AppModel
    private let updater: SPUUpdater

    init(updater: SPUUpdater) {
        self.updater = updater
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                header
                permissionBanner
                primaryActions
                favoriteAnchorsSection
                recentAnchorsSection
                footerActions
            }
            .padding(12)
        }
        .frame(width: 360, height: 520)
        .background(.ultraThinMaterial)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Text("CuePane")
                .font(.headline)

            Spacer(minLength: 0)

            CuePaneStatusBadge(
                title: appModel.accessibilityGranted ? "권한 허용" : "권한 필요",
                color: appModel.accessibilityGranted ? CuePaneChrome.mint : CuePaneChrome.amber
            )
            CuePaneStatusBadge(
                title: "\(appModel.anchorCount)개",
                color: .accentColor
            )
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var permissionBanner: some View {
        if !appModel.accessibilityGranted {
            CuePaneSurface {
                VStack(alignment: .leading, spacing: 8) {
                    Label("손쉬운 사용 권한이 필요합니다.", systemImage: "hand.raised.fill")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(CuePaneChrome.amber)

                    HStack(spacing: 6) {
                        Button("권한 요청") {
                            appModel.requestAccessibility()
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(CuePaneChrome.amber)
                        .controlSize(.small)

                        Button("설정 열기") {
                            appModel.openAccessibilitySettings()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
            }
        }
    }

    private var primaryActions: some View {
        VStack(spacing: 6) {
            Button {
                appModel.openSearch()
            } label: {
                Label("검색", systemImage: "magnifyingglass")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.bordered)
            .controlSize(.regular)

            Button {
                appModel.beginNamingCurrentWindow()
            } label: {
                Label("현재 창 이름 붙이기", systemImage: "tag")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.bordered)
            .controlSize(.regular)

            if let lastUsed = appModel.lastUsedPresentation {
                Button {
                    appModel.recallLastUsed()
                } label: {
                    Label("최근: \(lastUsed.record.name)", systemImage: "clock.arrow.circlepath")
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .lineLimit(1)
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
            }
        }
    }

    @ViewBuilder
    private var favoriteAnchorsSection: some View {
        if !appModel.favoritePresentations.isEmpty {
            CuePaneSurface(padding: 8) {
                VStack(alignment: .leading, spacing: 0) {
                    Text("즐겨찾기")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 4)
                        .padding(.bottom, 4)

                    ForEach(appModel.favoritePresentations.prefix(4)) { presentation in
                        menuAnchorRow(presentation: presentation, showStar: true)

                        if presentation.id != appModel.favoritePresentations.prefix(4).last?.id {
                            Divider().padding(.horizontal, 4)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var recentAnchorsSection: some View {
        if !appModel.recentPresentations.isEmpty {
            CuePaneSurface(padding: 8) {
                VStack(alignment: .leading, spacing: 0) {
                    Text("최근")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 4)
                        .padding(.bottom, 4)

                    ForEach(appModel.recentPresentations) { presentation in
                        menuAnchorRow(presentation: presentation, showStar: false)

                        if presentation.id != appModel.recentPresentations.last?.id {
                            Divider().padding(.horizontal, 4)
                        }
                    }
                }
            }
        }
    }

    private var footerActions: some View {
        HStack(spacing: 6) {
            Button("내보내기") { appModel.exportAnchors() }
                .buttonStyle(.bordered).controlSize(.small)
            Button("가져오기") { appModel.importAnchors() }
                .buttonStyle(.bordered).controlSize(.small)

            CheckForUpdatesView(updater: updater)
                .controlSize(.small)

            SettingsLink {
                Label("설정", systemImage: "gearshape")
            }
            .controlSize(.small)

            Spacer(minLength: 0)

            Button(role: .destructive) {
                appModel.quit()
            } label: {
                Label("종료", systemImage: "power")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
    }

    private func menuAnchorRow(presentation: AnchorPresentation, showStar: Bool) -> some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    Text(presentation.record.name)
                        .font(.caption.weight(.medium))
                        .lineLimit(1)

                    if showStar {
                        Image(systemName: "star.fill")
                            .font(.system(size: 7))
                            .foregroundStyle(CuePaneChrome.amber)
                    }
                }

                Text("\(presentation.record.totalWindowCount)개 창 · \(presentation.statusLabel)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            Button("열기") {
                appModel.recall(presentation, mode: .context, destination: .originalDisplay)
            }
            .buttonStyle(.bordered)
            .controlSize(.mini)
        }
        .padding(.vertical, 3)
        .padding(.horizontal, 4)
    }
}
