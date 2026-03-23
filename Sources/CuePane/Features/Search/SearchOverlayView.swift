import SwiftUI

struct SearchOverlayView: View {
    @EnvironmentObject private var appModel: AppModel
    @FocusState private var isQueryFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            queryField
            Divider()
            resultsSection
        }
        .background(.ultraThinMaterial)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            isQueryFocused = true
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(120))
                isQueryFocused = true
            }
        }
        .onExitCommand {
            appModel.dismissSearch()
        }
    }

    private var queryField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.title2)
                .foregroundStyle(.secondary)

            TextField("검색", text: $appModel.searchQuery)
                .textFieldStyle(.plain)
                .font(.title2)
                .focused($isQueryFocused)
                .onSubmit {
                    guard let first = appModel.filteredPresentations.first else {
                        return
                    }
                    appModel.recall(first, mode: .context, destination: .originalDisplay)
                }

            HStack(spacing: 6) {
                CuePaneStatusBadge(title: "\(appModel.filteredPresentations.count)개", color: .accentColor)
                CuePaneShortcutBadge(title: "esc")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    @ViewBuilder
    private var resultsSection: some View {
        let results = appModel.filteredPresentations

        if results.isEmpty {
            VStack(spacing: 8) {
                Text("결과 없음")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Button("현재 창 이름 붙이기") {
                    appModel.dismissSearch()
                    appModel.beginNamingCurrentWindow()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            let favoriteIDs = Set(appModel.favoritePresentations.map(\.id))
            let recentIDs = Set(appModel.recentPresentations.map(\.id))
            let remainingPresentations = appModel.filteredPresentations.filter { presentation in
                !favoriteIDs.contains(presentation.id) && !recentIDs.contains(presentation.id)
            }

            ScrollView {
                LazyVStack(spacing: 1) {
                    if appModel.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !appModel.favoritePresentations.isEmpty {
                        sectionHeader("즐겨찾기")

                        ForEach(appModel.favoritePresentations) { presentation in
                            AnchorRowView(presentation: presentation)
                                .environmentObject(appModel)
                        }

                        if !appModel.recentPresentations.isEmpty {
                            sectionHeader("최근 작업")
                        }

                        ForEach(appModel.recentPresentations) { presentation in
                            AnchorRowView(presentation: presentation)
                                .environmentObject(appModel)
                        }

                        if !remainingPresentations.isEmpty {
                            sectionHeader("전체")
                        }

                        ForEach(remainingPresentations) { presentation in
                            AnchorRowView(presentation: presentation)
                                .environmentObject(appModel)
                        }
                    } else {
                        ForEach(results) { presentation in
                            AnchorRowView(presentation: presentation)
                                .environmentObject(appModel)
                        }
                    }
                }
                .padding(6)
            }
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.caption2.weight(.medium))
            .foregroundStyle(.tertiary)
            .padding(.horizontal, 12)
            .padding(.top, 8)
            .padding(.bottom, 2)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct AnchorRowView: View {
    @EnvironmentObject private var appModel: AppModel
    @State private var isHovered = false
    let presentation: AnchorPresentation

    var body: some View {
        Button {
            appModel.recall(presentation, mode: .context, destination: .originalDisplay)
        } label: {
            HStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(statusColor.opacity(0.15))
                    .frame(width: 32, height: 32)
                    .overlay {
                        Text(String(presentation.record.anchorWindow.appName.prefix(1)))
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(statusColor)
                    }

                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 4) {
                        Text(presentation.record.name)
                            .font(.subheadline.weight(.medium))
                            .lineLimit(1)

                        if presentation.record.isFavorite {
                            Image(systemName: "star.fill")
                                .font(.system(size: 8))
                                .foregroundStyle(CuePaneChrome.amber)
                        }
                    }

                    Text("\(presentation.record.anchorWindow.appName) · \(presentation.record.totalWindowCount)개 창")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)

                CuePaneStatusBadge(title: presentation.statusLabel, color: statusColor)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(isHovered ? Color.primary.opacity(0.04) : Color.clear, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
        .contextMenu {
            Button("문맥 복원") {
                appModel.recall(presentation, mode: .context, destination: .originalDisplay)
            }

            Button("창만 복원") {
                appModel.recall(presentation, mode: .anchorOnly, destination: .originalDisplay)
            }

            Button("현재 화면으로 복원") {
                appModel.recall(presentation, mode: .context, destination: .currentDisplay)
            }

            Divider()

            Button("문맥 업데이트") {
                appModel.updateContext(for: presentation.record)
            }

            Button("이름 수정") {
                appModel.beginRenaming(presentation.record)
            }

            Button(presentation.record.isFavorite ? "즐겨찾기 해제" : "즐겨찾기") {
                appModel.toggleFavorite(presentation.record)
            }

            Divider()

            Button("삭제", role: .destructive) {
                appModel.delete(presentation.record)
            }
        }
    }

    private var statusColor: Color {
        if presentation.anchorLive && presentation.missingCount == 0 {
            return CuePaneChrome.mint
        }
        if presentation.anchorLive {
            return CuePaneChrome.amber
        }
        return CuePaneChrome.danger
    }
}
