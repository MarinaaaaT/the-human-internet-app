// Living styleguide. Shows every token and brand component in one scroll.
// Keep it in sync with Android's StyleguideScreen.kt and the web /styleguide:
// same sections, same order. When you add a component, add it here.
//
// Open the #Preview in Xcode, or push it from a debug menu.

import SwiftUI

struct DesignSystemStyleguide: View {
    var body: some View {
        ScrollView {
            content
        }
        .background(DesignTokens.Colors.background)
    }

    /// Everything on the page, outside the scroll view so it can be
    /// rendered on its own (snapshot tests, `ImageRenderer`).
    var content: some View {
            VStack(alignment: .leading, spacing: DesignTokens.Space.s12) {
                section("Brand reveal") {
                    BrandReveal(index: 0) { Wordmark(height: DesignTokens.Space.s6) }
                    BrandReveal(index: 1) { Text("Made by a human.").textStyle(DesignTokens.TextStyles.h1) }
                    BrandReveal(index: 2) { Text("Signed by a phone.").textStyle(DesignTokens.TextStyles.h1) }
                }

                section("Colors") {
                    swatch("background", DesignTokens.Colors.background)
                    swatch("surface", DesignTokens.Colors.surface)
                    swatch("surfaceHover", DesignTokens.Colors.surfaceHover)
                    swatch("foreground", DesignTokens.Colors.foreground)
                    swatch("mutedForeground", DesignTokens.Colors.mutedForeground)
                    swatch("subtleForeground (≥18pt only)", DesignTokens.Colors.subtleForeground)
                    swatch("border", DesignTokens.Colors.border)
                    swatch("highlight (badges only)", DesignTokens.Colors.highlight)
                    swatch("destructive (proposed)", DesignTokens.Colors.destructive)
                }

                section("Type · one weight (Medium)") {
                    typeRow("display", "Human.", DesignTokens.TextStyles.display)
                    typeRow("h1", "We just never signed it.", DesignTokens.TextStyles.h1)
                    typeRow("h2", "Verify your identity", DesignTokens.TextStyles.h2)
                    typeRow("h3", "Verify your identity", DesignTokens.TextStyles.h3)
                    typeRow("title", "iPhone 16 Pro Max", DesignTokens.TextStyles.title)
                    typeRow("body", "A white, spacious canvas gives creators the spotlight.", DesignTokens.TextStyles.body)
                    typeRow("label", "Weekly Streak", DesignTokens.TextStyles.label, color: DesignTokens.Colors.mutedForeground)
                    typeRow("caption", "37.7749° N, 122.4194° W", DesignTokens.TextStyles.caption, color: DesignTokens.Colors.mutedForeground)
                }

                section("Radius") {
                    HStack(spacing: DesignTokens.Space.s3) {
                        radiusTile("sm", DesignTokens.Radius.sm)
                        radiusTile("md", DesignTokens.Radius.md)
                        radiusTile("lg", DesignTokens.Radius.lg)
                        radiusTile("xl", DesignTokens.Radius.xl)
                        radiusTile("2xl", DesignTokens.Radius.x2xl)
                    }
                }

                section("Buttons · three CTA roles") {
                    PrimaryButton(title: "Share") {}
                    SecondaryButton(title: "Copy link") {}
                    TertiaryButton(title: "Not now") {}
                    CTAButton(title: "Delete photo", role: .destructive) {}
                    PrimaryButton(title: "Disabled", isEnabled: false) {}
                    HStack(spacing: DesignTokens.Space.s3) {
                        HumanIconButton(systemName: "plus", accessibilityLabel: "New photo") {}
                        HumanIconButton(systemName: "photo", accessibilityLabel: "Gallery") {}
                        HumanIconButton(systemName: "heart", accessibilityLabel: "Like") {}
                        HighlightBadge(text: "3x")
                        VerifiedBadge()
                    }
                }

                section("Fields") {
                    FieldLabel(text: "Display name")
                    HITextField(placeholder: "Sam Reyes", text: .constant(""))
                    FieldLabel(text: "Handle")
                    HITextField(placeholder: "", text: .constant("sam reyes"), error: "Handles can't contain spaces.")
                    RadioRow(title: "Public", subtitle: "Anyone with the link sees the photo.", isSelected: true) {}
                    RadioRow(title: "Humans Only", subtitle: "Only people on the human internet.", isSelected: false) {}
                }

                section("Cards") {
                    ProofInfoCard(device: "iPhone 16 Pro Max", date: "September 18, 2026", time: "3:42 PM",
                                  os: "iOS 19.0.1", place: "San Francisco, CA", coordinates: "37.7749° N, 122.4194° W")
                    NotificationCard(label: "Photo shared", value: "They know it's you.") {
                        Image("DoodleHand").resizable().scaledToFit()
                    }
                    NotificationCard(label: "Photo verified", value: "Go show them.") {
                        BrandMark(size: DesignTokens.Space.s8)
                    } badge: {
                        VerifiedBadge()
                    }
                    NotificationCard(label: "Weekly Streak", value: "Hard to miss you now.") {
                        Image("DoodleFlame").resizable().scaledToFit()
                    } badge: {
                        HighlightBadge(text: "3x")
                    }
                    HumanCard {
                        LabelValue(label: "HumanCard", value: "A grey surface on the white page. Nothing more.")
                    }
                }

                section("The mark") {
                    BrandMark(size: 120)
                        .frame(maxWidth: .infinity, minHeight: 200)
                        .overlay(RoundedRectangle(cornerRadius: DesignTokens.Radius.lg, style: .continuous)
                            .stroke(DesignTokens.Colors.border, lineWidth: 1))
                }
            }
            .padding(.horizontal, DesignTokens.Space.s4)
            .padding(.vertical, DesignTokens.Space.s8)
            .background(DesignTokens.Colors.background)
    }

    private func section<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: DesignTokens.Space.s3) {
            Text(title).textStyle(DesignTokens.TextStyles.caption)
                .foregroundStyle(DesignTokens.Colors.mutedForeground)
            content()
        }
    }

    private func swatch(_ name: String, _ color: Color) -> some View {
        HStack(spacing: DesignTokens.Space.s3) {
            RoundedRectangle(cornerRadius: DesignTokens.Radius.md, style: .continuous)
                .fill(color)
                .overlay(RoundedRectangle(cornerRadius: DesignTokens.Radius.md, style: .continuous)
                    .stroke(DesignTokens.Colors.border, lineWidth: 1))
                .frame(width: 40, height: 40)
            Text(name).textStyle(DesignTokens.TextStyles.label)
        }
    }

    private func typeRow(_ name: String, _ sample: String, _ token: DesignTokens.TextStyleToken,
                         color: Color = DesignTokens.Colors.foreground) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(name).textStyle(DesignTokens.TextStyles.caption)
                .foregroundStyle(DesignTokens.Colors.mutedForeground)
            Text(sample).textStyle(token).foregroundStyle(color)
        }
    }

    private func radiusTile(_ name: String, _ radius: CGFloat) -> some View {
        VStack(spacing: 4) {
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(DesignTokens.Colors.surface)
                .frame(width: 56, height: 56)
            Text(name).textStyle(DesignTokens.TextStyles.caption)
                .foregroundStyle(DesignTokens.Colors.mutedForeground)
        }
    }
}

#Preview {
    DesignSystemStyleguide()
}
