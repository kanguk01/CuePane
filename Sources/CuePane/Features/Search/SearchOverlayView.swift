import SwiftUI

struct SearchOverlayView: View {
    @EnvironmentObject private var appModel: AppModel
    @FocusState private var isQueryFocused: Bool

    var body: some View {
        ZStack {
            CuePaneWindowBackground()

            VStack(alignment: .leading, spacing: 18) {
                header
                queryField
                resultsSection
            }
            .padding(24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear {
            isQueryFocused = true
        }
        .onExitCommand {
            appModel.dismissSearch()
        }
    }

    private var header: some View {
        CuePaneSurface(padding: 16) {
            HStack(alignment: .center, spacing: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("CuePane 검색")
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .lineLimit(1)
                    Text("이름, 앱명, 창 제목으로 검색하고 필요한 작업 문맥을 바로 다시 부르세요.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Spacer(minLength: 0)

                HStack(spacing: 8) {
                    CuePaneShortcutBadge(title: "Enter 문맥")
                    CuePaneShortcutBadge(title: "Esc 닫기")
                }
            }
        }
    }

    private var queryField: some View {
        CuePaneSurface(padding: 14) {
            VStack(alignment: .leading, spacing: 10) {
                Text("빠른 검색")
                    .font(.headline)

                TextField("예: 서버로그, PR 482, 배포", text: $appModel.searchQuery)
                    .textFieldStyle(.roundedBorder)
                    .font(.title3)
                    .focused($isQueryFocused)
                    .onSubmit {
                        guard let first = appModel.filteredPresentations.first else {
                            return
                        }
                        appModel.recall(first, mode: .context, destination: .originalDisplay)
                    }

                HStack(spacing: 8) {
                    CuePaneStatusBadge(title: "\(appModel.filteredPresentations.count)개 결과", color: CuePaneChrome.accent)
                    CuePaneStatusBadge(title: "\(appModel.favoriteCount)개 즐겨찾기", color: CuePaneChrome.mint)
                }

                Divider()

                VStack(alignment: .leading, spacing: 6) {
                    Text("저장된 앵커")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                    Text(appModel.debugAnchorNamesText)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(2)

                    if !appModel.debugEventPreview.isEmpty {
                        Text("최근 이벤트")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .padding(.top, 2)

                        ForEach(appModel.debugEventPreview.prefix(3), id: \.self) { line in
                            Text(line)
                                .font(.caption2.monospaced())
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var resultsSection: some View {
        let results = appModel.filteredPresentations

        if results.isEmpty {
            CuePaneSurface {
                VStack(alignment: .leading, spacing: 10) {
                    Text("검색 결과가 없습니다.")
                        .font(.headline)
                    Text("현재 창 이름 붙이기로 먼저 앵커를 하나 만들어 두면 여기서 바로 찾을 수 있습니다.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Button("현재 창 이름 붙이기") {
                        appModel.dismissSearch()
                        appModel.beginNamingCurrentWindow()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(CuePaneChrome.accent)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        } else {
            let favoriteIDs = Set(appModel.favoritePresentations.map(\.id))
            let recentIDs = Set(appModel.recentPresentations.map(\.id))
            let remainingPresentations = appModel.filteredPresentations.filter { presentation in
                !favoriteIDs.contains(presentation.id) && !recentIDs.contains(presentation.id)
            }

            CuePaneSurface(padding: 12) {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        if appModel.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !appModel.favoritePresentations.isEmpty {
                            sectionTitle("즐겨찾기")

                            ForEach(appModel.favoritePresentations) { presentation in
                                AnchorRowView(presentation: presentation)
                                    .environmentObject(appModel)
                            }

                            if !appModel.recentPresentations.isEmpty {
                                sectionTitle("최근 작업")
                            }

                            ForEach(appModel.recentPresentations) { presentation in
                                AnchorRowView(presentation: presentation)
                                    .environmentObject(appModel)
                            }

                            if !remainingPresentations.isEmpty {
                                sectionTitle("전체 앵커")
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
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 6)
            .padding(.top, 4)
    }
}

private struct AnchorRowView: View {
    @EnvironmentObject private var appModel: AppModel
    let presentation: AnchorPresentation

    var body: some View {
        CuePaneSurface(padding: 12) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 14) {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 8) {
                            Text(presentation.record.name)
                                .font(.headline)
                                .lineLimit(1)

                            if presentation.record.isFavorite {
                                Image(systemName: "star.fill")
                                    .font(.caption)
                                    .foregroundStyle(CuePaneChrome.amber)
                            }
                        }

                        Text(presentation.subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)

                        if !presentation.record.previewContextAppNames.isEmpty {
                            Text(presentation.record.previewContextAppNames.prefix(3).joined(separator: " · "))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }

                    Spacer(minLength: 0)

                    CuePaneStatusBadge(title: presentation.statusLabel, color: statusColor)
                }

                Text("문맥 \(presentation.record.totalWindowCount)개 · 매칭 \(presentation.matchedCount)개 · 실행 \(presentation.record.usageCount)회 · \(presentation.record.updatedAt.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                HStack(spacing: 8) {
                    actionButton("문맥 복원", systemImage: "square.stack.3d.up.fill") {
                        appModel.recall(presentation, mode: .context, destination: .originalDisplay)
                    }
                    .tint(CuePaneChrome.accent)

                    actionButton("창만", systemImage: "rectangle.on.rectangle") {
                        appModel.recall(presentation, mode: .anchorOnly, destination: .originalDisplay)
                    }

                    actionButton("여기로", systemImage: "arrow.down.right.and.arrow.up.left") {
                        appModel.recall(presentation, mode: .context, destination: .currentDisplay)
                    }

                    actionButton("업데이트", systemImage: "arrow.clockwise") {
                        appModel.updateContext(for: presentation.record)
                    }

                    Menu {
                        Button("이름 수정") {
                            appModel.beginRenaming(presentation.record)
                        }

                        Button(presentation.record.isFavorite ? "즐겨찾기 해제" : "즐겨찾기") {
                            appModel.toggleFavorite(presentation.record)
                        }

                        Button("삭제", role: .destructive) {
                            appModel.delete(presentation.record)
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
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

    private func actionButton(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
    }
}
