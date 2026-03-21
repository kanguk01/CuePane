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
                    Color(red: 0.08, green: 0.11, blue: 0.18),
                    Color(red: 0.11, green: 0.20, blue: 0.31),
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

            Text("이름 붙인 창 하나에 현재 모니터의 작업 문맥을 매달아 두고, 나중에 검색해서 다시 부르는 앱입니다.")
                .font(.title3.weight(.medium))
                .foregroundStyle(Color.white.opacity(0.88))

            HStack(spacing: 10) {
                statusChip(
                    title: appModel.accessibilityGranted ? "권한 허용됨" : "손쉬운 사용 필요",
                    color: appModel.accessibilityGranted ? .green : .orange
                )
                statusChip(
                    title: "\(appModel.anchorCount)개 앵커 저장됨",
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
                body: "CuePane가 현재 창을 읽고 앞으로 가져오려면 macOS 손쉬운 사용 권한이 필요합니다.",
                accent: .orange
            )
            onboardingCard(
                index: "2",
                title: "현재 창 이름 붙이기",
                body: "예를 들어 터미널 창에 '서버로그' 같은 이름을 붙이면, 같은 모니터에 보이는 Slack 같은 보조 창도 함께 저장됩니다.",
                accent: .cyan
            )
            onboardingCard(
                index: "3",
                title: "검색 후 복원",
                body: "⌘⇧Space로 검색창을 열고 이름을 치면 문맥 전체, 창만, 현재 디스플레이로 가져오기를 바로 실행할 수 있습니다.",
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

                Button("검색 열기") {
                    appModel.openSearch()
                }
                .buttonStyle(.bordered)
            }

            HStack(spacing: 10) {
                Button("현재 창 이름 붙이기") {
                    appModel.beginNamingCurrentWindow()
                }
                .buttonStyle(.bordered)

                Button("저장소 폴더 열기") {
                    appModel.openStorageDirectory()
                }
                .buttonStyle(.bordered)
            }

            Text("단축키: \(GlobalHotKeyAction.toggleSearch.displayString) 검색 · \(GlobalHotKeyAction.nameCurrentWindow.displayString) 이름 붙이기")
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
