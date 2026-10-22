//
//  Components.swift
//  the-human-internet
//
//  Buttons and fields. Brand components (cards, badges, the reveal) are in
//  BrandComponents.swift. Every value here comes from DesignTokens.
//

import SwiftUI

/// The three CTA roles as full-width pills. Use at most one primary per screen.
struct CTAButton: View {
    let title: String
    var role: CTARole = .primary
    var isEnabled: Bool = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .textStyle(DesignTokens.TextStyles.label)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, DesignTokens.Space.s6)
                .ctaStyle(role)
        }
        .buttonStyle(.plain)
        .opacity(isEnabled ? 1 : 0.5)
        .disabled(!isEnabled)
    }
}

/// Black pill.
struct PrimaryButton: View {
    let title: String
    var isEnabled: Bool = true
    let action: () -> Void

    var body: some View {
        CTAButton(title: title, role: .primary, isEnabled: isEnabled, action: action)
    }
}

/// Light-grey pill — the second of a pair.
struct SecondaryButton: View {
    let title: String
    var isEnabled: Bool = true
    let action: () -> Void

    var body: some View {
        CTAButton(title: title, role: .secondary, isEnabled: isEnabled, action: action)
    }
}

/// Text only, for low-emphasis actions ("Not now").
struct TertiaryButton: View {
    let title: String
    var isEnabled: Bool = true
    let action: () -> Void

    var body: some View {
        CTAButton(title: title, role: .tertiary, isEnabled: isEnabled, action: action)
    }
}

/// Grey field, no stroke. Pair with a `FieldLabel` above; pass `error` to
/// outline it and show the message below.
struct HITextField: View {
    let placeholder: String
    @Binding var text: String
    var keyboardType: UIKeyboardType = .default
    var error: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Space.s2) {
            TextField("", text: $text, prompt: Text(placeholder).foregroundStyle(Theme.subtleForeground))
                .keyboardType(keyboardType)
                .textStyle(DesignTokens.TextStyles.body)
                .foregroundStyle(Theme.foreground)
                .padding(.horizontal, DesignTokens.Space.s4)
                .frame(minHeight: DesignTokens.Size.controlHeight)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.md, style: .continuous))
                .overlay {
                    if error != nil {
                        RoundedRectangle(cornerRadius: DesignTokens.Radius.md, style: .continuous)
                            .stroke(Theme.destructive, lineWidth: 1)
                    }
                }
            if let error {
                Text(error)
                    .textStyle(DesignTokens.TextStyles.label)
                    .foregroundStyle(Theme.destructive)
            }
        }
    }
}

struct FieldLabel: View {
    let text: String

    var body: some View {
        Text(text)
            .textStyle(DesignTokens.TextStyles.label)
            .foregroundStyle(Theme.mutedForeground)
    }
}

struct SheetGrabber: View {
    var body: some View {
        Capsule()
            .fill(Theme.border)
            .frame(width: DesignTokens.Space.s8, height: DesignTokens.Space.s1)
            .frame(maxWidth: .infinity)
    }
}

struct RadioRow: View {
    let title: String
    var subtitle: String?
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: DesignTokens.Space.s3) {
                Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                    .symbolStyle(DesignTokens.TextStyles.body)
                    .foregroundStyle(Theme.foreground)
                VStack(alignment: .leading, spacing: 0) {
                    Text(title)
                        .textStyle(DesignTokens.TextStyles.body)
                        .foregroundStyle(Theme.foreground)
                    if let subtitle {
                        Text(subtitle)
                            .textStyle(DesignTokens.TextStyles.label)
                            .foregroundStyle(Theme.mutedForeground)
                    }
                }
                Spacer()
            }
            .frame(minHeight: DesignTokens.Size.minTouch)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// One row of a Settings page. With a `value`, a muted label over it (a
/// `LabelValue`); without one, a single line for an action like "Log out".
/// The trailing symbol says what a tap does: `chevron.right` opens a page,
/// `pencil` edits, `info.circle` explains, `arrow.up.right` opens a website.
struct SettingsRow: View {
    let title: String
    var value: String? = nil
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            SettingsRowLabel(title: title, value: value, systemImage: systemImage)
        }
        .buttonStyle(.plain)
    }
}

/// `SettingsRow` without the button, for a row that is a `NavigationLink`
/// or a `Menu` instead.
struct SettingsRowLabel: View {
    let title: String
    var value: String? = nil
    let systemImage: String

    var body: some View {
        HStack {
            if let value {
                LabelValue(label: title, value: value)
            } else {
                Text(title)
                    .textStyle(DesignTokens.TextStyles.body)
                    .foregroundStyle(Theme.foreground)
            }
            Spacer()
            Image(systemName: systemImage)
                .symbolStyle(DesignTokens.TextStyles.body)
                .foregroundStyle(value == nil ? Theme.foreground : Theme.mutedForeground)
        }
        .padding(.horizontal, DesignTokens.Space.s6)
        .padding(.vertical, DesignTokens.Space.s4)
        .contentShape(Rectangle())
    }
}

/// Lays its subviews out left to right, wrapping to a new line when the next
/// one won't fit — what CSS calls `flex-wrap`, which SwiftUI has no built-in
/// container for. An `HStack` would compress or clip instead.
///
/// Used for the social-handle chips on `PhotoVerificationView`, whose widths
/// depend on handles other people typed, so no fixed column count is right.
/// Wrapping beats a horizontal scroller there: the view is a
/// `fullScreenCover`, and a nested scroll view fights its dismiss gesture.
///
/// Subviews are measured at their ideal size (`.unspecified`), so anything
/// wider than the container gets its own row rather than being shrunk.
struct FlowLayout: Layout {
    var spacing: CGFloat = DesignTokens.Space.s2

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = rows(subviews: subviews, maxWidth: proposal.width ?? .infinity)
        let height = rows.reduce(0) { $0 + $1.height } + spacing * CGFloat(max(0, rows.count - 1))
        return CGSize(width: proposal.width ?? (rows.map(\.width).max() ?? 0), height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in rows(subviews: subviews, maxWidth: bounds.width) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private struct Row {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func rows(subviews: Subviews, maxWidth: CGFloat) -> [Row] {
        var rows: [Row] = []
        var current = Row()

        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let widthIfAdded = current.indices.isEmpty
                ? size.width
                : current.width + spacing + size.width

            // The `!current.indices.isEmpty` guard is what stops a subview
            // wider than the whole container from looping forever on an
            // empty row it can never fit into.
            if widthIfAdded > maxWidth, !current.indices.isEmpty {
                rows.append(current)
                current = Row(indices: [index], width: size.width, height: size.height)
            } else {
                current.indices.append(index)
                current.width = widthIfAdded
                current.height = max(current.height, size.height)
            }
        }

        if !current.indices.isEmpty { rows.append(current) }
        return rows
    }
}
