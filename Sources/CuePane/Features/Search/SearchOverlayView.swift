import SwiftUI

struct SearchOverlayView: View {
    @EnvironmentObject private var appModel: AppModel
    @FocusState private var isQueryFocused: Bool
    @State private var selectedIndex = 0

    var body: some View {
        VStack(spacing: 0) {
            queryField
            Divider()
            resultsSection
        }
        .background(.ultraThinMaterial)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(alignment: .bottom) {
            if let toast = appModel.toastMessage {
                CuePaneToast(message: toast)
                    .padding(.bottom, 16)
                    .animation(.spring(duration: 0.3), value: appModel.toastMessage)
            }
        }
        .onAppear {
            isQueryFocused = true
            selectedIndex = 0
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(120))
                isQueryFocused = true
            }
        }
        .onExitCommand {
            appModel.dismissSearch()
        }
        .onChange(of: appModel.searchQuery) {
            selectedIndex = 0
        }
    }

    private var queryField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.title2)
                .foregroundStyle(.secondary)

            SearchTextField(
                text: $appModel.searchQuery,
                selectedIndex: $selectedIndex,
                resultCount: appModel.filteredPresentations.count,
                onSubmit: { submitSelected() }
            )
            .focused($isQueryFocused)

            HStack(spacing: 6) {
                if !appModel.filteredPresentations.isEmpty {
                    Button {
                        for p in appModel.filteredPresentations {
                            appModel.delete(p.record)
                        }
                    } label: {
                        Image(systemName: "trash")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("전체 삭제")
                }
                CuePaneStatusBadge(title: "\(appModel.filteredPresentations.count)개", color: .accentColor)
                CuePaneShortcutBadge(title: "esc")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private func submitSelected() {
        let results = appModel.filteredPresentations
        guard !results.isEmpty else { return }
        let index = min(selectedIndex, results.count - 1)
        appModel.recall(results[index], mode: .context, destination: .originalDisplay)
    }

    @ViewBuilder
    private var resultsSection: some View {
        let results = appModel.filteredPresentations

        if results.isEmpty {
            VStack(spacing: 8) {
                Text("결과 없음")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Button("현재 창 이름 붙이기") {
                    appModel.dismissSearch()
                    appModel.beginNamingCurrentWindow()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 1) {
                        ForEach(Array(results.enumerated()), id: \.element.id) { index, presentation in
                            AnchorRowView(
                                presentation: presentation,
                                isSelected: index == selectedIndex
                            )
                            .environmentObject(appModel)
                            .id(index)
                            .onTapGesture {
                                appModel.recall(presentation, mode: .context, destination: .originalDisplay)
                            }
                        }
                    }
                    .padding(6)
                }
                .onChange(of: selectedIndex) {
                    withAnimation {
                        proxy.scrollTo(selectedIndex, anchor: .center)
                    }
                }
            }
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.caption2.weight(.medium))
            .foregroundStyle(.tertiary)
            .padding(.horizontal, 12)
            .padding(.top, 8)
            .padding(.bottom, 2)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// 방향키 + Enter를 처리하는 NSTextField 래퍼
private struct SearchTextField: NSViewRepresentable {
    @Binding var text: String
    @Binding var selectedIndex: Int
    let resultCount: Int
    let onSubmit: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, selectedIndex: $selectedIndex, resultCount: resultCount, onSubmit: onSubmit)
    }

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField(string: text)
        field.placeholderString = "검색"
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = .systemFont(ofSize: 22)
        field.delegate = context.coordinator
        context.coordinator.field = field

        Task { @MainActor in
            field.window?.makeFirstResponder(field)
        }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(100))
            field.window?.makeFirstResponder(field)
        }

        return field
    }

    func updateNSView(_ nsView: NSTextField, context: Context) {
        if nsView.stringValue != text {
            nsView.stringValue = text
        }
        context.coordinator.resultCount = resultCount
        context.coordinator.onSubmit = onSubmit
    }

    @MainActor
    final class Coordinator: NSObject, NSTextFieldDelegate {
        @Binding var text: String
        @Binding var selectedIndex: Int
        var resultCount: Int
        var onSubmit: () -> Void
        weak var field: NSTextField?

        init(text: Binding<String>, selectedIndex: Binding<Int>, resultCount: Int, onSubmit: @escaping () -> Void) {
            _text = text
            _selectedIndex = selectedIndex
            self.resultCount = resultCount
            self.onSubmit = onSubmit
        }

        func controlTextDidChange(_ notification: Notification) {
            text = field?.stringValue ?? text
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSResponder.moveDown(_:)) {
                if resultCount > 0 {
                    selectedIndex = min(selectedIndex + 1, resultCount - 1)
                }
                return true
            }
            if commandSelector == #selector(NSResponder.moveUp(_:)) {
                selectedIndex = max(selectedIndex - 1, 0)
                return true
            }
            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                onSubmit()
                return true
            }
            return false
        }
    }
}

private struct AnchorRowView: View {
    @EnvironmentObject private var appModel: AppModel
    @State private var isHovered = false
    let presentation: AnchorPresentation
    var isSelected: Bool = false

    var body: some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(statusColor.opacity(0.15))
                .frame(width: 32, height: 32)
                .overlay {
                    Text(String(presentation.record.anchorWindow.appName.prefix(1)))
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(statusColor)
                }

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    Text(presentation.record.name)
                        .font(.subheadline.weight(.medium))
                        .lineLimit(1)

                    if presentation.record.isFavorite {
                        Image(systemName: "star.fill")
                            .font(.system(size: 8))
                            .foregroundStyle(CuePaneChrome.amber)
                    }
                }

                Text("\(presentation.record.anchorWindow.appName) · \(presentation.record.totalWindowCount)개 창")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            if isHovered || isSelected {
                HStack(spacing: 2) {
                    rowButton(icon: "star\(presentation.record.isFavorite ? ".fill" : "")", color: CuePaneChrome.amber) {
                        appModel.toggleFavorite(presentation.record)
                    }
                    .help(presentation.record.isFavorite ? "즐겨찾기 해제" : "즐겨찾기")

                    rowButton(icon: "pencil", color: .secondary) {
                        appModel.beginRenaming(presentation.record)
                    }
                    .help("이름 수정")

                    rowButton(icon: "arrow.clockwise", color: .secondary) {
                        appModel.updateContext(for: presentation.record)
                    }
                    .help("문맥 업데이트")

                    rowButton(icon: "xmark", color: CuePaneChrome.danger) {
                        appModel.delete(presentation.record)
                    }
                    .help("삭제")
                }
            } else {
                CuePaneStatusBadge(title: presentation.statusLabel, color: statusColor)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            (isSelected ? Color.accentColor.opacity(0.15) : isHovered ? Color.primary.opacity(0.04) : Color.clear),
            in: RoundedRectangle(cornerRadius: 8, style: .continuous)
        )
        .contentShape(Rectangle())
        .onHover { hovering in
            isHovered = hovering
        }
    }

    private func rowButton(icon: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 11))
                .foregroundStyle(color)
                .frame(width: 24, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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
}
