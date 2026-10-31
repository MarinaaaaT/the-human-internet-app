//
//  FaceIDGateView.swift
//  the-human-internet
//

import LocalAuthentication
import SwiftUI

/// Why `FaceIDGateView` is up — `AppState.faceIDGate`.
struct FaceIDGate: Equatable {
    enum Moment: Equatable {
        /// A cold launch into a stored session.
        case relaunch
        /// Right after Sign in with Apple, into an account that had
        /// finished onboarding.
        case signIn
        /// Right after Sign in with Apple, into one that hadn't.
        case signUp
    }

    var moment: Moment
    /// How the check before the gate went, when there was one: after sign-in
    /// the prompt runs over the next screen first, and the gate only goes up
    /// if it doesn't pass. nil on a relaunch, where the gate asks itself.
    var outcome: FaceIDOutcome?
}

/// Stands between a signed-in session and the app until `FaceIDCheck`
/// passes (`RootView`, driven by `AppState.faceIDGate`).
///
/// On a cold launch it asks as soon as it appears, so the usual path is a
/// glance and it's gone. After Sign in with Apple the prompt has already
/// run over the next screen and not passed, so it opens on that outcome and
/// waits. Either way it says why Face ID is needed and offers a way forward:
/// try again, open Settings, or log out. Never a dead end.
struct FaceIDGateView: View {
    var gate: FaceIDGate
    var onPass: () -> Void
    var onLogOut: () async throws -> Void

    @Environment(\.scenePhase) private var scenePhase
    /// nil until the first check finishes.
    @State private var outcome: FaceIDOutcome?
    @State private var isChecking = false
    @State private var biometryType: LABiometryType = .faceID
    @State private var showLogOutConfirmation = false
    @State private var logOutErrorMessage: String?

    var body: some View {
        let copy = FaceIDGateCopy(moment: gate.moment, outcome: outcome, biometryType: biometryType, device: UIDevice.current.model)
        ZStack {
            Theme.background.ignoresSafeArea()
            VStack(spacing: DesignTokens.Space.s6) {
                Spacer()
                Image(systemName: biometryType == .touchID ? "touchid" : "faceid")
                    .symbolStyle(DesignTokens.TextStyles.h1)
                    .foregroundStyle(Theme.foreground)
                    .accessibilityHidden(true)
                Text(copy.title)
                    .textStyle(DesignTokens.TextStyles.h2)
                    .foregroundStyle(Theme.foreground)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, DesignTokens.Space.s8)
                Text(copy.message)
                    .textStyle(DesignTokens.TextStyles.body)
                    .foregroundStyle(Theme.mutedForeground)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, DesignTokens.Space.s8)
                Spacer()
                VStack(spacing: DesignTokens.Space.s2) {
                    if let action = copy.action {
                        PrimaryButton(title: action.title, isEnabled: !isChecking) {
                            perform(action)
                        }
                        TertiaryButton(title: "Log out") { showLogOutConfirmation = true }
                    } else {
                        // Nothing to try on this device, so leaving is the
                        // one way forward — and the screen's one CTA.
                        PrimaryButton(title: "Log out") { showLogOutConfirmation = true }
                    }
                }
                .padding(.horizontal, DesignTokens.Space.s8)
                .padding(.bottom, DesignTokens.Space.s12)
            }
        }
        .task {
            biometryType = FaceIDCheck.biometryType()
            outcome = gate.outcome
            // Not straight after a cancel or a miss: the user has just said
            // no, and the button is right there.
            if gate.outcome == nil || gate.outcome == .interrupted {
                await check()
            }
        }
        // Back from Settings, or from wherever the app was sent mid-prompt:
        // check again without making them tap. Not after a plain cancel —
        // the prompt closing makes the app active again too, and reopening
        // it would leave no way to say no.
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active, outcome?.checksAgainOnReturn == true else { return }
            Task { await check() }
        }
        .confirmationDialog("Log out of the human internet?", isPresented: $showLogOutConfirmation, titleVisibility: .visible) {
            Button("Log Out", role: .destructive) { logOut() }
            Button("Cancel", role: .cancel) {}
        }
        .alert(
            "Couldn't log out",
            isPresented: Binding(get: { logOutErrorMessage != nil }, set: { if !$0 { logOutErrorMessage = nil } })
        ) {
            Button("OK") { logOutErrorMessage = nil }
        } message: {
            Text(logOutErrorMessage ?? "Please try again.")
        }
    }

    private func check() async {
        guard !isChecking else { return }
        isChecking = true
        defer { isChecking = false }
        let result = await FaceIDCheck.run()
        biometryType = FaceIDCheck.biometryType()
        if result == .passed {
            onPass()
        } else {
            Log.auth.info("Face ID check didn't pass: \(String(describing: result), privacy: .public)")
            outcome = result
        }
    }

    private func perform(_ action: FaceIDGateCopy.Action) {
        switch action {
        case .check:
            Task { await check() }
        case .openSettings:
            if let url = URL(string: UIApplication.openSettingsURLString) {
                UIApplication.shared.open(url)
            }
        }
    }

    private func logOut() {
        Task {
            do {
                try await onLogOut()
            } catch {
                logOutErrorMessage = "Please try again."
                Log.auth.error("Sign-out from the Face ID gate failed: \(error, privacy: .public)")
            }
        }
    }
}

/// What the gate says for each outcome. Separate from the view so
/// `FaceIDCheckTests` can check that every way of not passing explains
/// itself and offers a way on.
struct FaceIDGateCopy: Equatable {
    enum Action: Equatable {
        case check(title: String)
        case openSettings

        var title: String {
            switch self {
            case .check(let title): title
            case .openSettings: "Open Settings"
            }
        }
    }

    let title: String
    let message: String
    /// nil when there's nothing to try, and logging out is the way on.
    let action: Action?

    /// The way on is the same whatever the moment; what's said around it
    /// isn't. After sign-in every state is headed "Face ID required", with
    /// what to do in the message; on a relaunch each state has its own title.
    init(moment: FaceIDGate.Moment, outcome: FaceIDOutcome?, biometryType: LABiometryType, device: String) {
        let name = biometryType == .touchID ? "Touch ID" : "Face ID"

        switch outcome {
        case nil, .passed, .cancelled, .interrupted: action = .check(title: "Use \(name)")
        case .failed, .lockedOut, .notEnrolled: action = .check(title: "Try again")
        case .notAllowed: action = .openSettings
        case .unavailable: action = nil
        }

        switch moment {
        case .signIn, .signUp:
            let after = moment == .signUp ? "signing up" : "signing in"
            let required = "To prove you're a real person, we require a biometric check after \(after)."
            title = "\(outcome == .unavailable ? "Face ID" : name) required"
            message = switch outcome {
            case nil, .passed, .cancelled, .interrupted, .failed: required
            case .lockedOut: "\(required) Too many tries didn't match. Lock your \(device), unlock it with your passcode, then try again."
            case .notEnrolled: "\(required) Turn it on in Settings, under \(name) & Passcode, then come back."
            case .notAllowed: "\(required) Turn it on for the human internet in Settings, then come back."
            case .unavailable: "\(required) The human internet needs a device that has Face ID."
            }
        case .relaunch:
            let why = "You sign in with \(name), which shows a real person is logging in."
            switch outcome {
            case nil, .passed, .cancelled, .interrupted:
                title = "Are you still there?"
                message = "Stay signed in by helping us check it's still you with \(name)."
            case .failed:
                title = "\(name) didn't recognize you."
                message = "\(why) Your passcode can't stand in for it."
            case .lockedOut:
                title = "\(name) is locked."
                message = "Too many tries didn't match. Lock your \(device), unlock it with your passcode, then try again."
            case .notEnrolled:
                title = "Set up \(name) to continue."
                message = "\(why) Turn it on in Settings, under \(name) & Passcode, then come back."
            case .notAllowed:
                title = "\(name) is off for this app."
                message = "\(why) Turn it on for the human internet in Settings, then come back."
            case .unavailable:
                title = "This \(device) can't use Face ID."
                message = "You sign in with Face ID, which shows a real person is logging in. The human internet needs a device that has it."
            }
        }
    }
}

extension FaceIDOutcome {
    /// Outcomes fixed somewhere else — Settings, the lock screen, coming
    /// back to the app — so the gate checks again by itself on return.
    var checksAgainOnReturn: Bool {
        switch self {
        case .interrupted, .lockedOut, .notEnrolled, .notAllowed: true
        case .passed, .cancelled, .failed, .unavailable: false
        }
    }
}

#Preview("Relaunch") {
    FaceIDGateView(gate: FaceIDGate(moment: .relaunch), onPass: {}, onLogOut: {})
}

#Preview("After sign-up, cancelled") {
    FaceIDGateView(gate: FaceIDGate(moment: .signUp, outcome: .cancelled), onPass: {}, onLogOut: {})
}
