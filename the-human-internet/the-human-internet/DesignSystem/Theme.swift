//
//  Theme.swift
//  the-human-internet
//
//  Colour and CTA roles, built from the generated `DesignTokens`. Views read
//  colours from here (or `DesignTokens.Colors`), never from literals. To
//  change a value, edit `design-system/tokens.json` in the website repo and
//  run `node design-system/build.mjs` there.
//

import SwiftUI

enum Theme {
    /// Every screen's background. The app is light-only (`RootView` pins
    /// `.preferredColorScheme(.light)`), so the tokens' provisional dark
    /// values never show.
    static let background = DesignTokens.Colors.background
    /// Cards, fields, icon buttons, banners.
    static let surface = DesignTokens.Colors.surface
    static let surfaceHover = DesignTokens.Colors.surfaceHover

    /// Primary text, icons, the mark.
    static let foreground = DesignTokens.Colors.foreground
    /// Labels, metadata, secondary copy. AA at every size.
    static let mutedForeground = DesignTokens.Colors.mutedForeground
    /// Placeholders and decorative text only — fails AA under 18pt.
    static let subtleForeground = DesignTokens.Colors.subtleForeground

    /// Hairlines and dividers. Prefer spacing or a `surface` fill.
    static let border = DesignTokens.Colors.border
    /// Errors and destructive confirmations.
    static let destructive = DesignTokens.Colors.destructive
}

/// The three CTA roles (DESIGN.md → Components → Button). All pills.
enum CTARole {
    /// Black pill. At most one per screen.
    case primary
    /// Light-grey pill.
    case secondary
    /// Text only, for low-emphasis actions ("Not now", "Skip").
    case tertiary
    /// Red pill, for confirming something that can't be undone.
    case destructive

    var foreground: Color {
        switch self {
        case .primary: return DesignTokens.Colors.primaryForeground
        case .secondary, .tertiary: return DesignTokens.Colors.foreground
        case .destructive: return DesignTokens.Colors.destructiveForeground
        }
    }

    var background: Color {
        switch self {
        case .primary: return DesignTokens.Colors.primary
        case .secondary: return DesignTokens.Colors.surface
        case .tertiary: return .clear
        case .destructive: return DesignTokens.Colors.destructive
        }
    }
}

/// Where an icon-only button sits. Either way it's a 48pt circle with one
/// outline SF Symbol.
enum IconButtonSurface {
    /// Light grey on the white page.
    case page
    /// White, for a button over a photo or the live camera feed.
    case media

    var background: Color {
        self == .page ? DesignTokens.Colors.surface : DesignTokens.Colors.background
    }
}

extension View {
    /// A text CTA in the given role: a pill at `controlHeight`.
    func ctaStyle(_ role: CTARole = .primary) -> some View {
        foregroundStyle(role.foreground)
            .frame(minHeight: DesignTokens.Size.controlHeight)
            .background(role.background, in: Capsule())
            .contentShape(Capsule())
    }

    /// An icon-only CTA: the glyph centred on a 48pt circle. Give the button
    /// an `accessibilityLabel`.
    func ctaIcon(_ surface: IconButtonSurface = .page) -> some View {
        foregroundStyle(DesignTokens.Colors.foreground)
            .frame(width: DesignTokens.Size.iconButton, height: DesignTokens.Size.iconButton)
            .background(surface.background, in: Circle())
            .contentShape(Circle())
    }
}
