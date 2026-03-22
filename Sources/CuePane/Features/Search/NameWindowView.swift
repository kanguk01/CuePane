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
                        onSubmitAttempt: appModel.noteNamingSubmitAttempt,
                        onSubmit: appModel.saveNamingDraft
                    )
                    .frame(height: 34)

                    HStack {
                        Button("취소") {
                            appModel.dismissNaming()
                        }
                        .buttonStyle(.bordered)
                        .keyboardShortcut(.cancelAction)

                        Spacer(minLength: 0)

                        Button(appModel.namingSaveButtonTitle) {
                            appModel.noteNamingSubmitAttempt(source: "저장 버튼")
                            appModel.saveNamingDraft()
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(CuePaneChrome.accent)
                        .keyboardShortcut(.defaultAction)
                    }

                    Text(appModel.lastActionSummary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)

                    diagnosticSection
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(22)
        .onExitCommand {
            appModel.dismissNaming()
        }
    }

    private var diagnosticSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider()

            Text("진단")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            Text("최근 입력: \(appModel.lastNamingSubmitSource)")
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)

            if appModel.debugCapturedWindows.isEmpty {
                Text("저장 예정 창 없음")
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            } else {
                ForEach(appModel.debugCapturedWindows.prefix(5), id: \.self) { line in
                    Text(line)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            if !appModel.debugEventPreview.isEmpty {
                ForEach(appModel.debugEventPreview.prefix(4), id: \.self) { line in
                    Text(line)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
    }
}
