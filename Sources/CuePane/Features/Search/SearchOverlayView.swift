import SwiftUI

struct SearchOverlayView: View {
    @EnvironmentObject private var appModel: AppModel
    @FocusState private var isQueryFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            queryField
            resultsSection
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(
            LinearGradient(
                colors: [
                    Color(red: 0.95, green: 0.97, blue: 0.99),
                    Color(red: 0.92, green: 0.95, blue: 0.99),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .onAppear {
            isQueryFocused = true
        }
        .onExitCommand {
            appModel.dismissSearch()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("CuePane")
                .font(.system(size: 28, weight: .bold, design: .rounded))
            Text("이름, 앱명, 창 제목으로 검색하고 문맥 전체를 다시 부르세요.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var queryField: some View {
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
    }

    @ViewBuilder
    private var resultsSection: some View {
        let results = appModel.filteredPresentations

        if results.isEmpty {
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
            }
            .padding(20)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Color.white.opacity(0.72), in: RoundedRectangle(cornerRadius: 18))
        } else {
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(results) { presentation in
                        AnchorRowView(presentation: presentation)
                            .environmentObject(appModel)
                    }
                }
            }
        }
    }
}

private struct AnchorRowView: View {
    @EnvironmentObject private var appModel: AppModel
    let presentation: AnchorPresentation

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(presentation.record.name)
                        .font(.headline)
                    Text(presentation.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)

                Text(presentation.statusLabel)
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(statusColor.opacity(0.14), in: Capsule())
                    .foregroundStyle(statusColor)
            }

            HStack(spacing: 10) {
                metricChip(title: "문맥", value: "\(presentation.record.totalWindowCount)개")
                metricChip(title: "매칭", value: "\(presentation.matchedCount)개")
                metricChip(title: "업데이트", value: presentation.record.updatedAt.formatted(date: .abbreviated, time: .shortened))
            }

            HStack(spacing: 8) {
                actionButton("문맥 복원", systemImage: "square.stack.3d.up.fill") {
                    appModel.recall(presentation, mode: .context, destination: .originalDisplay)
                }

                actionButton("창만", systemImage: "rectangle.on.rectangle") {
                    appModel.recall(presentation, mode: .anchorOnly, destination: .originalDisplay)
                }

                actionButton("여기로", systemImage: "arrow.down.right.and.arrow.up.left") {
                    appModel.recall(presentation, mode: .context, destination: .currentDisplay)
                }

                actionButton("업데이트", systemImage: "arrow.clockwise") {
                    appModel.updateContext(for: presentation.record)
                }

                Button(role: .destructive) {
                    appModel.delete(presentation.record)
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(16)
        .background(Color.white.opacity(0.82), in: RoundedRectangle(cornerRadius: 18))
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(Color.white.opacity(0.6), lineWidth: 1)
        )
    }

    private var statusColor: Color {
        if presentation.anchorLive && presentation.missingCount == 0 {
            return .green
        }
        if presentation.anchorLive {
            return .orange
        }
        return .red
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
        .background(Color.black.opacity(0.035), in: RoundedRectangle(cornerRadius: 12))
    }

    private func actionButton(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
        }
        .buttonStyle(.bordered)
    }
}
