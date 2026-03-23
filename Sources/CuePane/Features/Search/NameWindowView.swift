import SwiftUI

struct NameWindowView: View {
    @EnvironmentObject private var appModel: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Text(appModel.namingTargetDescription)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Spacer(minLength: 0)

                CuePaneStatusBadge(
                    title: appModel.namingBadgeText,
                    color: appModel.namingCapturesContext ? CuePaneChrome.mint : .accentColor
                )
            }

            CuePaneAutoFocusTextField(
                placeholder: "앵커 이름",
                text: $appModel.namingDraft,
                font: .systemFont(ofSize: 18),
                onSubmit: appModel.saveNamingDraft
            )
            .frame(height: 30)

            HStack {
                Button("취소") {
                    appModel.dismissNaming()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .keyboardShortcut(.cancelAction)

                Spacer(minLength: 0)

                Button(appModel.namingSaveButtonTitle) {
                    appModel.saveNamingDraft()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(16)
        .background(.ultraThinMaterial)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onExitCommand {
            appModel.dismissNaming()
        }
    }
}
