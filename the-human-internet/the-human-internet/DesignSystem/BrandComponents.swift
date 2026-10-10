// Brand components that mirror Android's BrandComponents.kt and the web's
// src/components/brand. Buttons and fields stay in Components.swift.
// Never hardcode colors, sizes or radii here; read DesignTokens.

import SwiftUI

// MARK: - Text pattern

/// Muted label over a black value. The core text pattern.
struct LabelValue: View {
    let label: String
    let value: String
    /// Proof metadata sets the value in `title`.
    var valueStyle: DesignTokens.TextStyleToken = DesignTokens.TextStyles.body

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(label).textStyle(DesignTokens.TextStyles.label)
                .foregroundStyle(DesignTokens.Colors.mutedForeground)
            Text(value).textStyle(valueStyle)
                .foregroundStyle(DesignTokens.Colors.foreground)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Cards

/// Flat light-gray card: no border, no shadow.
struct HumanCard<Content: View>: View {
    var radius: CGFloat = DesignTokens.Radius.lg
    var padding: CGFloat = DesignTokens.Space.s4
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(DesignTokens.Colors.surface, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
    }
}

/// Notification row: white square thumbnail + label/value, optional corner badge.
struct NotificationCard<Thumbnail: View, Badge: View>: View {
    let label: String
    let value: String
    @ViewBuilder var thumbnail: Thumbnail
    @ViewBuilder var badge: Badge

    var body: some View {
        HumanCard(padding: DesignTokens.Space.s3) {
            HStack(spacing: DesignTokens.Space.s4) {
                thumbnail
                    .frame(width: DesignTokens.Size.thumbnail, height: DesignTokens.Size.thumbnail)
                    .background(DesignTokens.Colors.background)
                    .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.sm, style: .continuous))
                LabelValue(label: label, value: value)
            }
        }
        .overlay(alignment: .topTrailing) { badge.offset(x: 10, y: -10) }
    }
}

extension NotificationCard where Badge == EmptyView {
    init(label: String, value: String, @ViewBuilder thumbnail: () -> Thumbnail) {
        self.init(label: label, value: value, thumbnail: thumbnail, badge: { EmptyView() })
    }
}

/// Proof metadata block shown under a verified photo.
struct ProofInfoCard: View {
    let device: String
    let date: String
    let time: String
    let os: String
    let place: String
    let coordinates: String

    var body: some View {
        HumanCard(radius: DesignTokens.Radius.md, padding: DesignTokens.Space.s4) {
            VStack(alignment: .leading, spacing: 2) {
                line(device)
                line(date, secondary: time)
                line(os)
                line(place, secondary: coordinates)
            }
        }
    }

    private func line(_ main: String, secondary: String? = nil) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(main).textStyle(DesignTokens.TextStyles.title)
                .foregroundStyle(DesignTokens.Colors.foreground)
            if let secondary {
                Text(secondary).textStyle(DesignTokens.TextStyles.caption)
                    .foregroundStyle(DesignTokens.Colors.mutedForeground)
            }
        }
    }
}

// MARK: - Badges

/// Count/streak badge, e.g. "3x". The ONLY place the blue highlight is used.
struct HighlightBadge: View {
    let text: String

    var body: some View {
        Text(text).textStyle(DesignTokens.TextStyles.caption)
            .foregroundStyle(DesignTokens.Colors.highlightForeground)
            .padding(.horizontal, DesignTokens.Space.s2)
            .frame(minWidth: 32, minHeight: 32)
            .background(DesignTokens.Colors.highlight, in: Capsule())
    }
}

/// The spiral mark in a small white circle = "verified". Never a check/shield/lock.
struct VerifiedBadge<Mark: View>: View {
    @ViewBuilder var mark: Mark

    var body: some View {
        mark
            .frame(width: 18, height: 18)
            .frame(width: 32, height: 32)
            .background(DesignTokens.Colors.background, in: Circle())
            .overlay(Circle().stroke(DesignTokens.Colors.border, lineWidth: 1))
            .accessibilityElement()
            .accessibilityLabel("Verified")
    }
}

extension VerifiedBadge where Mark == BrandMark {
    /// The usual badge: the BrandMark spiral.
    init() {
        self.init { BrandMark(size: 18) }
    }
}

/// 48pt light-gray circle with one SF Symbol. The label is required for VoiceOver.
struct HumanIconButton: View {
    let systemName: String
    let accessibilityLabel: String
    /// `.media` for a white circle over a photo or the camera feed.
    var surface: IconButtonSurface = .page
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .symbolStyle(DesignTokens.TextStyles.title)
                .ctaIcon(surface)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }
}

// MARK: - Motion

/// Brand reveal: opacity only, 750ms ease-out, staggered 800ms per index.
/// For brand moments (onboarding, success), not routine UI. Honors Reduce Motion.
struct BrandReveal<Content: View>: View {
    var index: Int = 0
    @ViewBuilder var content: Content
    @State private var visible = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        content
            .opacity(visible ? 1 : 0)
            .onAppear {
                if reduceMotion { visible = true; return }
                withAnimation(.brandReveal.delay(Double(index) * DesignTokens.Motion.stagger)) { visible = true }
            }
    }
}
