//
//  Theme.swift
//  the-human-internet
//

import SwiftUI

enum Theme {
    /// Every screen's background. Pure white — the app is light-only
    /// (`RootView` pins `.preferredColorScheme(.light)`).
    static let background = Color.white
    /// Text fields, cards and banners: the one step off white, shared with
    /// the CTA fill so the palette stays two greys deep.
    static let surface = Color(red: 0xF6 / 255, green: 0xF6 / 255, blue: 0xF6 / 255)
    static let surfaceElevated = surface

    /// All text that isn't on a button is pure black — secondary copy
    /// included, by design. `textSecondary` is kept as its own token so
    /// reintroducing a hierarchy is a one-line change.
    static let textPrimary = Color.black
    static let textSecondary = Color.black
    /// Text-field placeholders only: a hint, not copy, so it must not read
    /// as something the user already typed.
    static let placeholder = ctaForeground

    /// CTAs — every button except Sign in with Apple. A text CTA is
    /// `ctaForeground` on `ctaBackground`; an icon-only one is the glyph on
    /// a `ctaBackground` circle. Use `.ctaStyle()` / `.ctaIcon()`.
    static let ctaBackground = surface
    static let ctaForeground = Color(red: 0xA2 / 255, green: 0xA2 / 255, blue: 0xA2 / 255)
    /// The secondary of a primary/secondary pair (Skip beside Verify,
    /// Preview beside Share): same fill, white label. By design it nearly
    /// disappears into its fill (~1.1:1) — the point is to recede.
    static let ctaSecondaryForeground = Color.white

    static let divider = Color.black.opacity(0.08)

    /// State indicators — toggles, radio buttons, the selected tab.
    static let selection = Color.black

    static let accentPink = Color(red: 0.89, green: 0.66, blue: 0.87)
    /// Status *icons* (checkmarks, seals). Status text is black like all text.
    static let success = Color(red: 0.30, green: 0.78, blue: 0.45)
    static let warning = Color(red: 0.93, green: 0.62, blue: 0.20)

    static let cornerRadius: CGFloat = 14
}

extension View {
    /// A text CTA: `#A2A2A2` on `#F6F6F6`, or white on `#F6F6F6` for the
    /// secondary of a pair.
    func ctaStyle(secondary: Bool = false, cornerRadius: CGFloat = Theme.cornerRadius) -> some View {
        foregroundStyle(secondary ? Theme.ctaSecondaryForeground : Theme.ctaForeground)
            .background(Theme.ctaBackground, in: RoundedRectangle(cornerRadius: cornerRadius))
    }

    /// An icon-only CTA: the glyph centred on a `#F6F6F6` circle.
    func ctaIcon(diameter: CGFloat = 36) -> some View {
        foregroundStyle(Theme.ctaForeground)
            .frame(width: diameter, height: diameter)
            .background(Theme.ctaBackground, in: Circle())
    }
}
