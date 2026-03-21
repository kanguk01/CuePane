import SwiftUI

struct NameWindowView: View {
    @EnvironmentObject private var appModel: AppModel
    @FocusState private var isFocused: Bool

    var body: some View {
        ZStack {
            CuePaneWindowBackground()

            CuePaneSurface(padding: 20) {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: "tag.fill")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(CuePaneChrome.accent)
                            .frame(width: 36, height: 36)
                            .background(CuePaneChrome.accent.opacity(0.14), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                        VStack(alignment: .leading, spacing: 4) {
                            Text(appModel.editingExistingAnchor ? "앵커 이름 수정" : "현재 창 이름 붙이기")
                                .font(.title2.weight(.bold))
                            Text("저장 시 같은 모니터의 작업 문맥을 함께 기록합니다.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text(appModel.namingTargetDescription)
                            .font(.subheadline.weight(.medium))
                        HStack(spacing: 8) {
                            CuePaneStatusBadge(title: "\(appModel.namingPreviewCount)개 창 저장 예정", color: CuePaneChrome.mint)
                        }
                    }

                    TextField("앵커 이름", text: $appModel.namingDraft)
                        .textFieldStyle(.roundedBorder)
                        .font(.title3)
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
                        .tint(CuePaneChrome.accent)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(22)
        .onAppear {
            isFocused = true
        }
        .onExitCommand {
            appModel.dismissNaming()
        }
    }
}
