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
    static let placeholder = Color(red: 0xA2 / 255, green: 0xA2 / 255, blue: 0xA2 / 255)

    /// CTAs — every button except Sign in with Apple. Three roles, applied
    /// with `.ctaStyle(_:)` / `.ctaIcon(_:)` — see `CTARole`.
    static let ctaBackground = surface
    static let ctaForeground = Color(red: 0x76 / 255, green: 0x76 / 255, blue: 0x76 / 255)
    static let ctaTertiaryBackground = Color(red: 0xE0 / 255, green: 0xE0 / 255, blue: 0xE0 / 255)
    static let ctaTertiaryForeground = Color.white

    static let divider = Color.black.opacity(0.08)

    /// State indicators — toggles, radio buttons, the selected tab.
    static let selection = Color.black

    static let accentPink = Color(red: 0.89, green: 0.66, blue: 0.87)
    /// Status *icons* (checkmarks, seals). Status text is black like all text.
    static let success = Color(red: 0.30, green: 0.78, blue: 0.45)
    static let warning = Color(red: 0.93, green: 0.62, blue: 0.20)

    static let cornerRadius: CGFloat = 14
}

enum CTARole {
    /// `#767676` on `#F6F6F6`. The default, and the primary of a pair.
    case primary
    /// `#767676` label and 1pt outline on white — the secondary of a pair
    /// (Skip beside Verify, Preview beside Share).
    case secondary
    /// White on `#E0E0E0`. **Only for a button standing alone on something
    /// that isn't white** — over the live camera feed, over a photo.
    case tertiary

    var foreground: Color {
        switch self {
        case .primary, .secondary: return Theme.ctaForeground
        case .tertiary: return Theme.ctaTertiaryForeground
        }
    }

    var background: Color {
        switch self {
        case .primary: return Theme.ctaBackground
        case .secondary: return Theme.background
        case .tertiary: return Theme.ctaTertiaryBackground
        }
    }

    var outline: Color {
        self == .secondary ? Theme.ctaForeground : .clear
    }
}

extension View {
    /// A text CTA in the given role.
    func ctaStyle(_ role: CTARole = .primary, cornerRadius: CGFloat = Theme.cornerRadius) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius)
        return foregroundStyle(role.foreground)
            .background(role.background, in: shape)
            .overlay(shape.stroke(role.outline, lineWidth: 1))
    }

    /// An icon-only CTA: the glyph centred on a circle in the given role.
    func ctaIcon(_ role: CTARole = .primary, diameter: CGFloat = 36) -> some View {
        foregroundStyle(role.foreground)
            .frame(width: diameter, height: diameter)
            .background(role.background, in: Circle())
            .overlay(Circle().stroke(role.outline, lineWidth: 1))
    }
}
