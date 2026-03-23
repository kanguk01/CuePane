import AppKit
import SwiftUI

enum CuePaneChrome {
    static let mint = Color(red: 0.18, green: 0.65, blue: 0.53)
    static let amber = Color(red: 0.85, green: 0.55, blue: 0.20)
    static let danger = Color(red: 0.78, green: 0.32, blue: 0.28)
}

struct CuePaneWindowBackground: View {
    var body: some View {
        Rectangle()
            .fill(.ultraThinMaterial)
            .ignoresSafeArea()
    }
}

struct CuePaneSurface<Content: View>: View {
    private let padding: CGFloat
    @ViewBuilder private let content: Content

    init(padding: CGFloat = 12, @ViewBuilder content: () -> Content) {
        self.padding = padding
        self.content = content()
    }

    var body: some View {
        content
            .padding(padding)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.primary.opacity(0.08), lineWidth: 0.5)
            )
    }
}

struct CuePaneStatusBadge: View {
    let title: String
    let color: Color

    var body: some View {
        Text(title)
            .font(.caption2.weight(.medium))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.12), in: Capsule())
            .foregroundStyle(color)
    }
}

struct CuePaneMetricTile: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.tertiary)
            Text(value)
                .font(.subheadline.weight(.medium))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct CuePaneShortcutBadge: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.system(.caption2, design: .monospaced).weight(.medium))
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 4, style: .continuous))
            .foregroundStyle(.secondary)
    }
}

struct CuePaneToast: View {
    let message: String

    var body: some View {
        Text(message)
            .font(.subheadline.weight(.medium))
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.regularMaterial, in: Capsule())
            .shadow(color: .black.opacity(0.1), radius: 8)
            .transition(.move(edge: .bottom).combined(with: .opacity))
    }
}
