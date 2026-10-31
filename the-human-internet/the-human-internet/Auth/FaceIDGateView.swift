//
//  FaceIDGateView.swift
//  the-human-internet
//

import LocalAuthentication
import SwiftUI

/// Stands between a signed-in session and the app until `FaceIDCheck`
/// passes. Shown on every cold launch that restores a session (`RootView`),
/// never after a fresh Sign in with Apple.
///
/// It asks for Face ID as soon as it appears, so the usual path is a glance
/// and it's gone. Anything else leaves it up with the reason Face ID is
/// needed and a way forward: try again, open Settings, or log out. Never a
/// dead end.
struct FaceIDGateView: View {
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
        let copy = FaceIDGateCopy(outcome: outcome, biometryType: biometryType, device: UIDevice.current.model)
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
            await check()
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

    init(outcome: FaceIDOutcome?, biometryType: LABiometryType, device: String) {
        let name = biometryType == .touchID ? "Touch ID" : "Face ID"
        let why = "You sign in with \(name), which shows a real person is logging in."
        switch outcome {
        case nil, .passed, .cancelled, .interrupted:
            title = "Are you still there?"
            message = "Stay signed in by helping us check it's still you with \(name)."
            action = .check(title: "Use \(name)")
        case .failed:
            title = "\(name) didn't recognize you."
            message = "\(why) Your passcode can't stand in for it."
            action = .check(title: "Try again")
        case .lockedOut:
            title = "\(name) is locked."
            message = "Too many tries didn't match. Lock your \(device), unlock it with your passcode, then try again."
            action = .check(title: "Try again")
        case .notEnrolled:
            title = "Set up \(name) to continue."
            message = "\(why) Turn it on in Settings, under \(name) & Passcode, then come back."
            action = .check(title: "Try again")
        case .notAllowed:
            title = "\(name) is off for this app."
            message = "\(why) Turn it on for the human internet in Settings, then come back."
            action = .openSettings
        case .unavailable:
            title = "This \(device) can't use Face ID."
            message = "You sign in with Face ID, which shows a real person is logging in. The human internet needs a device that has it."
            action = nil
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

#Preview("Asking") {
    FaceIDGateView(onPass: {}, onLogOut: {})
}
