import SwiftUI

struct NameWindowView: View {
    @EnvironmentObject private var appModel: AppModel

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
                            Text(appModel.namingTitle)
                                .font(.title2.weight(.bold))
                            Text(appModel.namingSubtitle)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text(appModel.namingTargetDescription)
                            .font(.subheadline.weight(.medium))
                        HStack(spacing: 8) {
                            CuePaneStatusBadge(
                                title: appModel.namingBadgeText,
                                color: appModel.namingCapturesContext ? CuePaneChrome.mint : CuePaneChrome.accent
                            )
                        }
                    }

                    CuePaneAutoFocusTextField(
                        placeholder: "앵커 이름",
                        text: $appModel.namingDraft,
                        font: .systemFont(ofSize: 20),
                        onSubmit: appModel.saveNamingDraft
                    )
                    .frame(height: 34)

                    HStack {
                        Button("취소") {
                            appModel.dismissNaming()
                        }
                        .buttonStyle(.bordered)

                        Spacer(minLength: 0)

                        Button(appModel.namingSaveButtonTitle) {
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
        .onExitCommand {
            appModel.dismissNaming()
        }
    }
}
