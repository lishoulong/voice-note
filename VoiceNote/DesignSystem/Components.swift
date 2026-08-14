import SwiftUI

// MARK: - Kicker(uppercase 小标签,大量用于分区标题/元信息)
struct Kicker: View {
    let text: String
    var color: Color = DC.neutral600
    var tracking: CGFloat = 1.6   // ≈ 0.16em @ 11px
    var body: some View {
        Text(text.uppercased())
            .font(.serifBody(11))
            .tracking(tracking)
            .foregroundStyle(color)
    }
}

// MARK: - Tag
enum TagKind { case outline, accent, neutral }

struct Tag: View {
    let text: String
    var kind: TagKind = .outline
    var body: some View {
        Text(text)
            .font(.serifBody(11))
            .tracking(0.2)
            .foregroundStyle(fg)
            .padding(.horizontal, 10)
            .padding(.vertical, 3)
            .background(bg, in: RoundedRectangle(cornerRadius: Radius.tag))
            .overlay(RoundedRectangle(cornerRadius: Radius.tag).stroke(border, lineWidth: 1))
    }
    private var fg: Color {
        switch kind {
        case .outline: DC.accent
        case .accent:  DC.accent800
        case .neutral: DC.neutral800
        }
    }
    private var bg: Color {
        switch kind {
        case .outline: .clear
        case .accent:  DC.accent100
        case .neutral: DC.neutral100
        }
    }
    private var border: Color {
        switch kind {
        case .outline: DC.accent
        case .accent, .neutral: .clear
        }
    }
}

// MARK: - Horizontal rule
struct HRule: View {
    var body: some View {
        Rectangle().fill(DC.divider).frame(height: 1)
    }
}

// MARK: - Card 容器修饰(border 1px + radius md,背景透明,浮在米色底上靠描边区分)
extension View {
    func dcCard(border: Color = DC.divider, padding: CGFloat = Space.s3) -> some View {
        self
            .padding(padding)
            .overlay(RoundedRectangle(cornerRadius: Radius.md).stroke(border, lineWidth: 1))
    }
}

// MARK: - Button styles(全部克制描边风,字体用衬线 heading)
/// 主按钮:accent 描边 + accent 文字(设计 .btn-primary)
struct PrimaryButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.heading(15, .semibold))
            .foregroundStyle(DC.accent)
            .padding(.vertical, Space.s2)
            .padding(.horizontal, Space.s3 * 1.2)
            .frame(minHeight: 44)
            .background(configuration.isPressed ? DC.accent.opacity(0.22) : .clear,
                        in: RoundedRectangle(cornerRadius: Radius.sm))
            .overlay(RoundedRectangle(cornerRadius: Radius.sm).stroke(DC.accent, lineWidth: 1))
            .contentShape(Rectangle())
    }
}

/// 次按钮:淡描边(divider)
struct SecondaryButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.heading(15, .semibold))
            .foregroundStyle(DC.text)
            .padding(.vertical, Space.s2)
            .padding(.horizontal, Space.s3 * 1.2)
            .frame(minHeight: 44)
            .background(configuration.isPressed ? DC.text.opacity(0.14) : .clear,
                        in: RoundedRectangle(cornerRadius: Radius.sm))
            .overlay(RoundedRectangle(cornerRadius: Radius.sm).stroke(DC.divider, lineWidth: 1))
            .contentShape(Rectangle())
    }
}

/// 文字按钮:无边框 accent 文字(设计 .btn-ghost),常用于 返回/完成/取消
struct GhostButton: ButtonStyle {
    var color: Color = DC.accent700
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.heading(15, .semibold))
            .foregroundStyle(color)
            .padding(.vertical, Space.s1)
            .padding(.horizontal, Space.s1)
            .background(configuration.isPressed ? DC.accent.opacity(0.18) : .clear,
                        in: RoundedRectangle(cornerRadius: Radius.sm))
            .contentShape(Rectangle())
    }
}

// MARK: - Icon button(顶栏 38×38 圆钮,用 SF Symbol 替代设计的自定义线性图标)
struct IconButton: View {
    let systemName: String
    var size: CGFloat = 38
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 17, weight: .regular))
                .foregroundStyle(DC.text)
                .frame(width: size, height: size)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 整屏背景容器
struct Screen<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        ZStack {
            DC.bg.ignoresSafeArea()
            content
        }
        .foregroundStyle(DC.text)
    }
}
