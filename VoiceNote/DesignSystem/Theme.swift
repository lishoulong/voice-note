import SwiftUI

// MARK: - Color from hex
extension Color {
    init(hex: UInt32, alpha: Double = 1) {
        let r = Double((hex >> 16) & 0xFF) / 255
        let g = Double((hex >> 8) & 0xFF) / 255
        let b = Double(hex & 0xFF) / 255
        self.init(.sRGB, red: r, green: g, blue: b, opacity: alpha)
    }
}

// MARK: - Palette
/// 设计 token 来自 design/style/styles.css(:root 变量)。命名空间 DC = Design Color。
enum DC {
    static let bg      = Color(hex: 0xF3F2F2)
    static let surface = Color(hex: 0xEAE9E9)
    static let text    = Color(hex: 0x201F1D)
    static let accent  = Color(hex: 0xB68235)
    static let divider = Color(hex: 0x201F1D, alpha: 0.16)

    // accent 100→900(暖金棕)
    static let accent100 = Color(hex: 0xFFF3E4)
    static let accent200 = Color(hex: 0xFFE3BF)
    static let accent300 = Color(hex: 0xFACB8D)
    static let accent400 = Color(hex: 0xE1AD66)
    static let accent500 = Color(hex: 0xC28D41)
    static let accent600 = Color(hex: 0xA06F24)
    static let accent700 = Color(hex: 0x7D5411)
    static let accent800 = Color(hex: 0x5A3B0A)
    static let accent900 = Color(hex: 0x3A270D)

    // neutral 100→900(暖灰)
    static let neutral100 = Color(hex: 0xF8F4F4)
    static let neutral200 = Color(hex: 0xEAE7E7)
    static let neutral300 = Color(hex: 0xD7D3D3)
    static let neutral400 = Color(hex: 0xBAB6B6)
    static let neutral500 = Color(hex: 0x9B9797)
    static let neutral600 = Color(hex: 0x7D7979)
    static let neutral700 = Color(hex: 0x605D5D)
    static let neutral800 = Color(hex: 0x444141)
    static let neutral900 = Color(hex: 0x2D2B2B)
}

// MARK: - Spacing(design/style: --space-*)
enum Space {
    static let s1: CGFloat = 4.6
    static let s2: CGFloat = 9.2
    static let s3: CGFloat = 13.8
    static let s4: CGFloat = 18.4
    static let s6: CGFloat = 27.6
    static let s8: CGFloat = 36.8
}

// MARK: - Corner radius(--radius-*)
enum Radius {
    static let sm: CGFloat = 2
    static let md: CGFloat = 4
    static let lg: CGFloat = 7
    static let tag: CGFloat = 3   // calc(radius-md * 0.75)
}

// MARK: - Fonts
/// 设计用 Cormorant Garamond(标题)/ Lora(正文),iOS 无内置。
/// 先用系统 serif 还原衬线杂志质感;中文会回退到宋体系,恰合日记调性。
/// TODO: 后续可内嵌 TTF 精确还原西文字形。
extension Font {
    /// 标题字体(对应 --font-heading,Cormorant)
    static func heading(_ size: CGFloat, _ weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight, design: .serif)
    }
    /// 正文字体(对应 --font-body,Lora)
    static func serifBody(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .serif)
    }
}
