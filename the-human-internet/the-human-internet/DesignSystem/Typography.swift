//
//  Typography.swift
//  the-human-internet
//

import SwiftUI
import CoreText
import Observation
import Supabase

extension Theme {
    /// The app's text font. Every `.font(...)` on text goes through here, so
    /// changing typefaces is a change to `Typography`, not to 80-odd views.
    ///
    /// `fixedSize` keeps the exact point sizes the `.system(size:)` calls it
    /// replaced had — this swaps the typeface and nothing else. SF Symbols
    /// (`Image(systemName:)`) deliberately stay on `.system`, which is what
    /// they're drawn to match.
    static func font(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .custom(Typography.shared.family.postScriptName(for: weight), fixedSize: size)
    }
}

enum FontFamily {
    /// The default, bundled with the app (SIL Open Font License — fine in a
    /// public repo and an App Store build). Registered via `UIAppFonts`.
    case interDisplay
    /// PP Neue Montreal, behind the `neue_font` flag. **Not bundled**: the
    /// files we hold are Pangram Pangram's free-for-personal-use release,
    /// whose EULA forbids public apps and public distribution, and this repo
    /// is public. They're downloaded at runtime from the private
    /// `licensed-fonts` bucket, whose storage policy follows the same flag —
    /// see `FeatureFlagKey.neueFont`.
    case neueMontreal

    /// Nearest available cut per weight. Neue Montreal's free set has no
    /// Medium or Bold: medium reads as Regular, and bold and heavier as
    /// Semibold.
    func postScriptName(for weight: Font.Weight) -> String {
        switch self {
        case .interDisplay:
            switch weight {
            case .medium: return "InterDisplay-Medium"
            case .semibold: return "InterDisplay-SemiBold"
            case .bold, .heavy, .black: return "InterDisplay-Bold"
            default: return "InterDisplay-Regular"
            }
        case .neueMontreal:
            switch weight {
            case .semibold, .bold, .heavy, .black: return "PPNeueMontreal-Semibold"
            default: return "PPNeueMontreal-Regular"
            }
        }
    }
}

/// Which family `Theme.font` draws with. `@Observable`, so every view whose
/// body called `Theme.font` re-renders when `family` changes — flipping the
/// flag in the dev menu restyles the app in place.
@Observable
final class Typography {
    static let shared = Typography()

    private(set) var family: FontFamily = .interDisplay

    /// Object names in the `licensed-fonts` bucket. Replacing the free files
    /// with the paid ones is a re-upload under these same names.
    static let neueMontrealObjects = [
        "PPNeueMontreal-Regular.otf",
        "PPNeueMontreal-Semibold.otf",
    ]
    static let licensedFontsBucket = "licensed-fonts"

    @ObservationIgnored private var wantsNeueMontreal = false
    @ObservationIgnored private var isNeueMontrealRegistered = false
    @ObservationIgnored private var loadTask: Task<Void, Never>?

    /// Called by `AppState` whenever the flag or `isAdmin` changes.
    /// Idempotent. Falls back to Inter Display on any failure — a missing
    /// file, the storage policy saying no, no network — and only switches
    /// once *every* weight is registered, so the app never mixes families.
    func setNeueMontrealEnabled(_ enabled: Bool) {
        guard enabled != wantsNeueMontreal else { return }
        wantsNeueMontreal = enabled
        loadTask?.cancel()

        guard enabled else {
            family = .interDisplay
            return
        }
        if isNeueMontrealRegistered {
            family = .neueMontreal
            return
        }
        loadTask = Task { @MainActor [weak self] in
            do {
                for name in Self.neueMontrealObjects {
                    let data = try await supabase.storage
                        .from(Self.licensedFontsBucket)
                        .download(path: name)
                    try Self.register(data, name: name)
                }
                guard let self, !Task.isCancelled else { return }
                self.isNeueMontrealRegistered = true
                if self.wantsNeueMontreal { self.family = .neueMontreal }
            } catch {
                Log.devMenu.error("Neue Montreal unavailable, staying on Inter Display: \(error, privacy: .public)")
            }
        }
    }

    /// Process-scoped and in memory — nothing is written to disk, so the
    /// files never outlive the session that was allowed to fetch them.
    private static func register(_ data: Data, name: String) throws {
        guard let provider = CGDataProvider(data: data as CFData),
              let font = CGFont(provider) else {
            throw FontLoadError.unreadable(name)
        }
        var error: Unmanaged<CFError>?
        if !CTFontManagerRegisterGraphicsFont(font, &error),
           let cfError = error?.takeRetainedValue(),
           CFErrorGetCode(cfError) != CTFontManagerError.alreadyRegistered.rawValue {
            throw cfError
        }
    }

    enum FontLoadError: Error {
        case unreadable(String)
    }
}
