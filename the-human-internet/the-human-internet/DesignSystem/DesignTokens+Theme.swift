// Bridges the generated DesignTokens into Theme / Typography.
// Hand-written (not generated). Safe to edit.

import SwiftUI
import UIKit

extension Theme {
    /// Brand font for a token, scaled with Dynamic Type at the current size category.
    static func font(_ token: DesignTokens.TextStyleToken) -> Font {
        let scaled = UIFontMetrics(forTextStyle: token.textStyle.uiKit).scaledValue(for: token.size)
        return Theme.font(size: scaled, weight: DesignTokens.fontWeight)
    }
}

/// Applies a full type token: font (Dynamic Type), tracking and line spacing.
/// Usage: Text("Go show them.").textStyle(DesignTokens.TextStyles.body)
struct TextStyleModifier: ViewModifier {
    let token: DesignTokens.TextStyleToken
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize // re-renders when the user changes text size

    func body(content: Content) -> some View {
        _ = dynamicTypeSize // reading it makes SwiftUI re-evaluate when text size changes
        return content
            .font(Theme.font(token))
            .tracking(token.tracking)
            .lineSpacing(token.lineSpacing)
    }
}

extension View {
    func textStyle(_ token: DesignTokens.TextStyleToken) -> some View {
        modifier(TextStyleModifier(token: token))
    }

    /// An SF Symbol sized by a type token, so it scales with Dynamic Type
    /// alongside the text around it. Light weight, per the icon rule.
    /// Usage: Image(systemName: "camera").symbolStyle(DesignTokens.TextStyles.title)
    func symbolStyle(_ token: DesignTokens.TextStyleToken) -> some View {
        modifier(SymbolStyleModifier(token: token))
    }
}

struct SymbolStyleModifier: ViewModifier {
    let token: DesignTokens.TextStyleToken
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    func body(content: Content) -> some View {
        _ = dynamicTypeSize
        let scaled = UIFontMetrics(forTextStyle: token.textStyle.uiKit).scaledValue(for: token.size)
        return content.font(.system(size: scaled, weight: .light))
    }
}

extension Font.TextStyle {
    var uiKit: UIFont.TextStyle {
        switch self {
        case .largeTitle: return .largeTitle
        case .title: return .title1
        case .title2: return .title2
        case .title3: return .title3
        case .headline: return .headline
        case .subheadline: return .subheadline
        case .body: return .body
        case .callout: return .callout
        case .footnote: return .footnote
        case .caption: return .caption1
        case .caption2: return .caption2
        @unknown default: return .body
        }
    }
}

extension Animation {
    /// Brand reveal: opacity only, 750ms ease-out. Callers add `.delay(index * stagger)`.
    static var brandReveal: Animation { DesignTokens.Motion.easeOut(DesignTokens.Motion.slow) }
    /// Tap/hover reveals and crossfades: 300ms ease-out.
    static var brandBase: Animation { DesignTokens.Motion.easeOut(DesignTokens.Motion.base) }
}
