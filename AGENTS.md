# AGENTS.md: UI rules for The Human Internet (iOS)

Read `DESIGN.md` before building or changing any UI. It explains the brand intent and is shared with web and Android.

## Where things live (`the-human-internet/the-human-internet/DesignSystem/`)
- `DesignTokens.swift`: **generated, never edit.** Colors, type scale, radius, spacing, sizes, shadow, motion. To change a value, edit `design-system/tokens.json` in the **web repo** and run `node design-system/build.mjs` there.
- `DesignTokens+Theme.swift`: `Theme.font(token)`, `.textStyle(token)`, `.symbolStyle(token)` (SF Symbols sized by the type scale), and the `.brandReveal` / `.brandBase` animations.
- `Theme.swift`: color and CTA roles (primary, secondary, tertiary, destructive) and `.ctaStyle` / `.ctaIcon`, built from `DesignTokens.Colors`.
- `Typography.swift`: `Theme.font(size:weight:)`. Use `Theme.font(DesignTokens.TextStyles.x)` or `.textStyle(...)`.
- `Components.swift`: buttons (`PrimaryButton`, `SecondaryButton`, `TertiaryButton`, `CTAButton`) and fields. `BrandComponents.swift`: LabelValue, HumanCard, NotificationCard, ProofInfoCard, HighlightBadge, VerifiedBadge, HumanIconButton, BrandReveal.
- `BrandMark.swift`: the spiral mark and the `Wordmark` (SVG assets `BrandMark`, `Wordmark`). `PhotoWatermarker.swift`: the watermark, a separate PNG shared with the signing Lambda.
- `DesignSystemStyleguide.swift`: the living styleguide (`#Preview`, or Developer Menu → Design System Styleguide).

## Hard rules
1. **No raw values in views.** Never write `Color(red:…)`, hex values, `.font(.system(size:))`, or magic numbers for padding, radius or size. Use `DesignTokens.*`, `Theme`, and `.textStyle(...)`. If a token you need doesn't exist, stop and ask. Don't invent one.
2. **Reuse before you create.** Check `Components.swift` and `BrandComponents.swift` first. Any new reusable view goes in one of those files **and** gets added to `DesignSystemStyleguide.swift`.
3. **One font weight.** Everything is Medium (`DesignTokens.fontWeight`). Never use `.bold()` or `.fontWeight(.semibold)`. Create hierarchy with the type scale and with `foreground` vs `mutedForeground`.
4. **Dynamic Type.** All text goes through `.textStyle(...)` so it scales with the user's text size. Check large accessibility sizes in previews.
5. **No new colors.** The UI is black, white, and light gray. `highlight` (blue) is only for small count/streak badges. Photos provide the color.
6. **"Verified" is always the spiral mark** (`BrandMark` / `VerifiedBadge`). Never use `checkmark`, `checkmark.seal`, `shield` or `lock` symbols to mean verified.
7. **Flat surfaces.** Cards are `surface` fill with no stroke and no shadow. `DesignTokens.Shadow` is only for sheets and popovers.
8. **Motion is opacity only.** Use `.brandBase` for taps and reveals, and `BrandReveal` for brand moments. No slide, scale or spring. Respect `accessibilityReduceMotion`.
9. **Icons are SF Symbols** at `.light` or `.regular` weight, outline (non-fill) variants. Every icon-only button needs an `accessibilityLabel`. Touch targets must be at least 44pt.
10. **Haptics:** use a soft impact on capture and on "Photo verified". Nowhere else unless asked.

## Copy voice
- Use short declarative sentences ending in periods, often in pairs: "Photo verified. Go show them."
- Use sentence case. The wordmark is always lowercase: "the human internet".
- Don't use "C2PA", "cryptographic", or "blockchain" in user-facing copy unless the screen is explicitly technical.

## Before you finish a UI change
- Open `DesignSystemStyleguide` and your screen in Xcode previews, in both default and accessibility (AX3) text sizes.
- Run the hardcoded-value check from the Xcode project folder (`the-human-internet/`), which should print nothing outside `DesignSystem/`:
  `grep -rnE "Color\(red:|#[0-9a-fA-F]{6}|\.system\(size:|\.bold\(\)|\.semibold" --include=*.swift the-human-internet | grep -v /DesignSystem/`
