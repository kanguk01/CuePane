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
        CuePaneSurface(padding: 18) {
            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("CuePane 검색")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                    Text("이름, 앱명, 창 제목으로 검색하고 필요한 작업 문맥을 바로 다시 부르세요.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)

                VStack(alignment: .trailing, spacing: 8) {
                    CuePaneShortcutBadge(title: "Enter 문맥")
                    CuePaneShortcutBadge(title: "Esc 닫기")
                }
            }
        }
    }

    private var queryField: some View {
        CuePaneSurface(padding: 16) {
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
        CuePaneSurface {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 14) {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 8) {
                            Text(presentation.record.name)
                                .font(.headline)

                            if presentation.record.isFavorite {
                                Image(systemName: "star.fill")
                                    .font(.caption)
                                    .foregroundStyle(CuePaneChrome.amber)
                            }
                        }

                        Text(presentation.subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        if !presentation.record.previewContextAppNames.isEmpty {
                            Text(presentation.record.previewContextAppNames.prefix(3).joined(separator: " · "))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Spacer(minLength: 0)

                    CuePaneStatusBadge(title: presentation.statusLabel, color: statusColor)
                }

                HStack(spacing: 10) {
                    metricChip(title: "문맥", value: "\(presentation.record.totalWindowCount)개")
                    metricChip(title: "매칭", value: "\(presentation.matchedCount)개")
                    metricChip(title: "실행", value: "\(presentation.record.usageCount)회")
                    metricChip(title: "업데이트", value: presentation.record.updatedAt.formatted(date: .abbreviated, time: .shortened))
                }

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

                    Button {
                        appModel.beginRenaming(presentation.record)
                    } label: {
                        Image(systemName: "pencil")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    Button {
                        appModel.toggleFavorite(presentation.record)
                    } label: {
                        Image(systemName: presentation.record.isFavorite ? "star.slash" : "star")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    Button(role: .destructive) {
                        appModel.delete(presentation.record)
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.bordered)
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

    private func metricChip(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color.black.opacity(0.045), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func actionButton(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
    }
}
