import SwiftUI
import UIKit

/// The look of Fade, taken from the "Fade App Design" canvas. Every colour has a dark and a light value,
/// and switches by itself with the phone's appearance setting. Use these names, never raw colours, in screens.
enum Theme {
    // Surfaces
    static let bg = Color(light: 0xF4F6F8, dark: 0x0A0C0F)        // the ground behind everything
    static let card = Color(light: 0xFFFFFF, dark: 0x12161B)      // cards and sheets
    static let raised = Color(light: 0xEEF1F4, dark: 0x1A2027)    // things sitting on a card: chips, tiles, inputs
    static let line = Color(light: 0xE2E7EC, dark: 0x222932)      // hairlines and borders

    // Text
    static let text = Color(light: 0x0E1318, dark: 0xF3F5F7)
    static let text2 = Color(light: 0x4D5967, dark: 0x98A2AE)
    static let text3 = Color(light: 0x6B7683, dark: 0x7C8794)

    // Accent and status
    static let accent = Color(light: 0x1F5FE0, dark: 0x4F8CFF)
    static let onAccent = Color(light: 0xFFFFFF, dark: 0x0A0C0F)  // text on an accent-coloured button
    static let win = Color(light: 0x0F8A4B, dark: 0x34D17F)
    static let loss = Color(light: 0xC7302F, dark: 0xFF6B6B)
    static let pending = Color(light: 0x9A6700, dark: 0xF5B942)

    // The coin
    static let coin = Color(hex: 0xF5B942)
    static let coinRing = Color(hex: 0xB9801A)
    static let onAvatar = Color(hex: 0x0A0C0F)

    enum Radius {
        static let pill: CGFloat = 8       // status pills
        static let tile: CGFloat = 12      // stat tiles, small buttons
        static let button: CGFloat = 14
        static let card: CGFloat = 18
        static let sheet: CGFloat = 28
    }
}

extension Color {
    /// 0xRRGGBB
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: 1
        )
    }

    /// A colour that switches between a light and a dark value with the phone's appearance.
    init(light: UInt32, dark: UInt32) {
        self.init(uiColor: UIColor { traits in
            let value = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(
                red: CGFloat((value >> 16) & 0xFF) / 255,
                green: CGFloat((value >> 8) & 0xFF) / 255,
                blue: CGFloat(value & 0xFF) / 255,
                alpha: 1
            )
        })
    }
}

/// Type styles. They are the phone's own text styles, so they grow and shrink with the Text Size setting.
extension Font {
    static let fadeScreenTitle = Font.largeTitle.weight(.heavy)    // 34
    static let fadeSectionTitle = Font.title2.weight(.bold)        // 22
    static let fadeHeadline = Font.headline                        // 17
    static let fadeBody = Font.subheadline                         // 15
    static let fadeCaption = Font.footnote                         // 13
    static let fadeLabel = Font.caption2.weight(.bold)             // 11, shown in capitals
}

extension View {
    /// The dark (or light) ground behind a whole screen.
    func fadeScreen() -> some View {
        background(Theme.bg.ignoresSafeArea())
    }

    /// A card: card colour, 18 radius, hairline border, no shadow.
    func fadeCard(padding: CGFloat = 16, fill: Color = Theme.card, stroke: Color = Theme.line) -> some View {
        self
            .padding(padding)
            .background(fill, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                    .strokeBorder(stroke, lineWidth: 1)
            )
    }
}
