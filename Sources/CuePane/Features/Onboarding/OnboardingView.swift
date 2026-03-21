import SwiftUI

struct OnboardingView: View {
    @EnvironmentObject private var appModel: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            hero
            steps
            controls
            Spacer(minLength: 0)
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(
            LinearGradient(
                colors: [
                    Color(red: 0.06, green: 0.09, blue: 0.16),
                    Color(red: 0.09, green: 0.18, blue: 0.29),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("CuePane 시작하기")
                .font(.system(size: 32, weight: .bold, design: .rounded))
                .foregroundStyle(.white)

            Text("모니터를 뽑았다가 다시 연결해도 창이 원래 작업 배치로 돌아오게 만드는 앱입니다.")
                .font(.title3.weight(.medium))
                .foregroundStyle(Color.white.opacity(0.88))

            HStack(spacing: 10) {
                statusChip(
                    title: appModel.accessibilityGranted ? "권한 허용됨" : "손쉬운 사용 필요",
                    color: appModel.accessibilityGranted ? .green : .orange
                )
                statusChip(
                    title: appModel.preferences.autoRestoreEnabled ? "자동 복원 켜짐" : "자동 복원 꺼짐",
                    color: .cyan
                )
            }
        }
    }

    private var steps: some View {
        VStack(alignment: .leading, spacing: 14) {
            onboardingCard(
                index: "1",
                title: "손쉬운 사용 권한",
                body: "CuePane가 창 위치를 읽고 옮기려면 macOS 손쉬운 사용 권한이 필요합니다.",
                accent: .orange
            )
            onboardingCard(
                index: "2",
                title: "현재 레이아웃 저장",
                body: "원하는 배치를 맞춘 뒤 `지금 저장`을 누르거나 자동 저장을 켜 두면 현재 화면 조합의 프로필이 만들어집니다.",
                accent: .cyan
            )
            onboardingCard(
                index: "3",
                title: "연결 변경 시 자동 복원",
                body: "노트북 단독/외부 모니터 조합이 바뀌면 CuePane가 해당 토폴로지 저장본으로 창을 되돌립니다.",
                accent: .mint
            )
        }
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Button("권한 요청") {
                    appModel.requestAccessibility()
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)

                Button("설정 열기") {
                    appModel.openAccessibilitySettings()
                }
                .buttonStyle(.bordered)

                Button("진단 창") {
                    appModel.openDiagnosticsWindow()
                }
                .buttonStyle(.bordered)
            }

            HStack(spacing: 10) {
                Button("지금 저장") {
                    appModel.captureNow(reason: "온보딩 저장")
                }
                .buttonStyle(.bordered)

                Button("지금 복원") {
                    appModel.restoreCurrentTopology(reason: "온보딩 복원")
                }
                .buttonStyle(.bordered)
            }

            Text(appModel.launchAtLoginStatus)
                .font(.caption)
                .foregroundStyle(Color.white.opacity(0.72))
        }
    }

    private func onboardingCard(index: String, title: String, body: String, accent: Color) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Text(index)
                .font(.headline.weight(.bold))
                .foregroundStyle(accent)
                .frame(width: 34, height: 34)
                .background(accent.opacity(0.18), in: Circle())

            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.white)
                Text(body)
                    .font(.subheadline)
                    .foregroundStyle(Color.white.opacity(0.78))
            }
        }
        .padding(18)
        .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 20))
    }

    private func statusChip(title: String, color: Color) -> some View {
        Text(title)
            .font(.caption.weight(.bold))
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(color.opacity(0.18), in: Capsule())
            .foregroundStyle(color)
    }
}
