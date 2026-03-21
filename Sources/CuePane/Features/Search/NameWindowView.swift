import SwiftUI

struct NameWindowView: View {
    @EnvironmentObject private var appModel: AppModel
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(appModel.editingExistingAnchor ? "앵커 이름 수정" : "현재 창 이름 붙이기")
                .font(.title2.weight(.bold))

            VStack(alignment: .leading, spacing: 6) {
                Text(appModel.namingTargetDescription)
                    .font(.subheadline.weight(.medium))
                Text("저장 시 같은 모니터의 \(appModel.namingPreviewCount)개 창을 함께 기록합니다.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            TextField("앵커 이름", text: $appModel.namingDraft)
                .textFieldStyle(.roundedBorder)
                .focused($isFocused)
                .onSubmit {
                    appModel.saveNamingDraft()
                }

            HStack {
                Button("취소") {
                    appModel.dismissNaming()
                }
                .buttonStyle(.bordered)

                Spacer(minLength: 0)

                Button(appModel.editingExistingAnchor ? "업데이트" : "저장") {
                    appModel.saveNamingDraft()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(22)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(
            LinearGradient(
                colors: [
                    Color(red: 0.97, green: 0.98, blue: 0.99),
                    Color(red: 0.93, green: 0.96, blue: 0.98),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .onAppear {
            isFocused = true
        }
        .onExitCommand {
            appModel.dismissNaming()
        }
    }
}
