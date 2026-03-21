import AppKit
import SwiftUI

enum CuePaneChrome {
    static let canvasTop = Color(red: 0.96, green: 0.97, blue: 0.99)
    static let canvasBottom = Color(red: 0.92, green: 0.95, blue: 0.98)
    static let accent = Color(red: 0.22, green: 0.45, blue: 0.98)
    static let mint = Color(red: 0.10, green: 0.72, blue: 0.58)
    static let amber = Color(red: 0.93, green: 0.60, blue: 0.17)
    static let danger = Color(red: 0.83, green: 0.30, blue: 0.26)
}

struct CuePaneWindowBackground: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [CuePaneChrome.canvasTop, CuePaneChrome.canvasBottom],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Circle()
                .fill(CuePaneChrome.accent.opacity(0.12))
                .frame(width: 340, height: 340)
                .blur(radius: 30)
                .offset(x: 220, y: -180)

            Circle()
                .fill(CuePaneChrome.mint.opacity(0.10))
                .frame(width: 220, height: 220)
                .blur(radius: 24)
                .offset(x: -180, y: 170)
        }
        .ignoresSafeArea()
    }
}

struct CuePaneSurface<Content: View>: View {
    private let padding: CGFloat
    @ViewBuilder private let content: Content

    init(padding: CGFloat = 16, @ViewBuilder content: () -> Content) {
        self.padding = padding
        self.content = content()
    }

    var body: some View {
        content
            .padding(padding)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(Color.white.opacity(0.55), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.06), radius: 18, x: 0, y: 10)
    }
}

struct CuePaneStatusBadge: View {
    let title: String
    let color: Color

    var body: some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(color.opacity(0.14), in: Capsule())
            .foregroundStyle(color)
    }
}

struct CuePaneMetricTile: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.headline.weight(.semibold))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 4)
    }
}

struct CuePaneShortcutBadge: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.system(.caption, design: .monospaced).weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(Color.black.opacity(0.06), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .foregroundStyle(.secondary)
    }
}
