import SwiftUI

struct DiagnosticsView: View {
    @EnvironmentObject private var appModel: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                overviewCards
                if let captureSummary = appModel.lastCaptureSummary {
                    captureSection(summary: captureSummary)
                }
                if let report = appModel.lastRestoreReport {
                    restoreSection(report: report)
                }
                logsSection
            }
            .padding(24)
        }
        .background(
            LinearGradient(
                colors: [Color(red: 0.95, green: 0.98, blue: 1.0), Color.white],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("진단")
                .font(.system(size: 30, weight: .bold, design: .rounded))
            Text("현재 디스플레이 상태, 저장된 프로필, 마지막 복원 결과를 한 번에 확인합니다.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            HStack(spacing: 10) {
                Button("새로고침") {
                    appModel.refreshDiagnostics()
                }
                .buttonStyle(.borderedProminent)

                Button("지금 저장") {
                    appModel.captureNow(reason: "진단 창 저장")
                }
                .buttonStyle(.bordered)

                Button("지금 복원") {
                    appModel.restoreCurrentTopology(reason: "진단 창 복원")
                }
                .buttonStyle(.bordered)

                Button("보류 재시도") {
                    appModel.retryPendingRestores()
                }
                .buttonStyle(.bordered)
            }
        }
    }

    private var overviewCards: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 14) {
            infoCard(
                title: "현재 화면",
                value: appModel.topologySummary,
                accent: .blue,
                detail: "실시간 감지 중"
            )
            infoCard(
                title: "현재 보이는 창",
                value: "\(appModel.liveWindowCount)개",
                accent: .teal,
                detail: "손쉬운 사용 기준"
            )
            infoCard(
                title: "저장된 프로필 창",
                value: "\(appModel.currentProfileWindowCount)개",
                accent: .indigo,
                detail: appModel.lastSavedSummary
            )
            infoCard(
                title: "보류 복원 큐",
                value: "\(appModel.pendingRestoreCount)개",
                accent: .orange,
                detail: appModel.lastRestoreSummary
            )
            infoCard(
                title: "권한",
                value: appModel.accessibilityGranted ? "허용됨" : "필요함",
                accent: appModel.accessibilityGranted ? .green : .red,
                detail: appModel.accessibilityGranted ? "창 읽기/이동 가능" : "복원을 위해 필요"
            )
            infoCard(
                title: "로그인 시 실행",
                value: appModel.launchAtLoginEnabled ? "켜짐" : "꺼짐",
                accent: .purple,
                detail: appModel.launchAtLoginStatus
            )
        }
    }

    private func captureSection(summary: CaptureSummary) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("마지막 저장")
                .font(.headline)

            VStack(alignment: .leading, spacing: 8) {
                Text(summary.topologySummary)
                    .font(.subheadline.weight(.semibold))
                Text("\(summary.windowCount)개 창 저장 · \(summary.createdAt.formatted(date: .omitted, time: .standard))")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if !summary.appBreakdown.isEmpty {
                    ForEach(summary.appBreakdown, id: \.self) { line in
                        Text(line)
                            .font(.caption)
                    }
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.white, in: RoundedRectangle(cornerRadius: 20))
        }
    }

    private func restoreSection(report: RestoreReport) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("마지막 복원")
                .font(.headline)

            VStack(alignment: .leading, spacing: 10) {
                Text(report.headline)
                    .font(.subheadline.weight(.semibold))
                Text("\(report.topologySummary) · \(report.createdAt.formatted(date: .omitted, time: .standard))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.white, in: RoundedRectangle(cornerRadius: 20))

            LazyVStack(spacing: 10) {
                ForEach(report.traces) { trace in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(trace.appName)
                                    .font(.subheadline.weight(.semibold))
                                if !trace.requestedTitle.isEmpty {
                                    Text(trace.requestedTitle)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                            }

                            Spacer()

                            Text(trace.status.title)
                                .font(.caption.weight(.bold))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(statusColor(trace.status).opacity(0.14), in: Capsule())
                                .foregroundStyle(statusColor(trace.status))
                        }

                        Text(trace.reason.title)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)

                        Text(trace.note)
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        HStack {
                            Text("대상: \(trace.targetDisplayName)")
                            if !trace.sourceDisplayName.isEmpty {
                                Text("실제: \(trace.sourceDisplayName)")
                            }
                            if let score = trace.score {
                                Text("점수: \(score)")
                            }
                        }
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.white, in: RoundedRectangle(cornerRadius: 16))
                }
            }
        }
    }

    private var logsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("최근 이벤트")
                    .font(.headline)
                Spacer()
                Button("로그 폴더 열기") {
                    appModel.openLogsDirectory()
                }
                .font(.caption)
            }

            VStack(alignment: .leading, spacing: 8) {
                ForEach(appModel.recentLogs, id: \.self) { line in
                    Text(line)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(16)
            .background(Color.black.opacity(0.92), in: RoundedRectangle(cornerRadius: 20))
            .foregroundStyle(.white)
        }
    }

    private func infoCard(title: String, value: String, accent: Color, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            RoundedRectangle(cornerRadius: 8)
                .fill(accent.opacity(0.18))
                .frame(width: 42, height: 8)
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 22, weight: .bold, design: .rounded))
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white, in: RoundedRectangle(cornerRadius: 22))
    }

    private func statusColor(_ status: RestoreTraceStatus) -> Color {
        switch status {
        case .restored: .green
        case .pending: .orange
        case .skipped: .red
        }
    }
}
