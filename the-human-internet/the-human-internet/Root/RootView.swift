//
//  RootView.swift
//  the-human-internet
//

import SwiftUI
import Supabase

struct RootView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.scenePhase) private var scenePhase
    @State private var isRestoringSession = true
    @State private var showDeveloperMenu = false
    /// A demo link that arrived while the stored session was still being
    /// restored — on a cold launch from the link itself. Run once that's
    /// done, so restoring the previous account can't land on top of it.
    @State private var isDemoEntryPending = false
    @State private var demoErrorMessage: String?
    var body: some View {
        Group {
            // Also while the demo link signs in: whatever was on screen goes,
            // so onboarding is built fresh at the profile step when it's done.
            if isRestoringSession || appState.isEnteringDemoAccount {
                ZStack {
                    Theme.background.ignoresSafeArea()
                    ProgressView()
                        .tint(Theme.foreground)
                }
            } else if let gate = appState.faceIDGate {
                // Nothing of the account shows until Face ID passes. Signing
                // out clears the gate along with everything else.
                FaceIDGateView(gate: gate) {
                    appState.faceIDGate = nil
                } onLogOut: {
                    try await appState.signOut(keepingPendingUploads: true)
                }
            } else if appState.isOnboarded {
                MainTabView()
            } else {
                OnboardingFlowView()
            }
        }
        // The default for any text that doesn't set its own — List rows,
        // alerts' callers, text fields. Explicit `.textStyle(...)`
        // calls override it.
        .textStyle(DesignTokens.TextStyles.body)
        // System buttons (toolbar items, alert actions) are CTAs too.
        .tint(Theme.foreground)
        .preferredColorScheme(.light)
        .onOpenURL { url in
            handle(url: url)
        }
        // Coming back from the background is the moment a verification that
        // resolved while the app was away should become visible. Nothing
        // pushes the webhook's write down to a running client, and `hydrate`
        // only runs at cold launch — so without this the new status first
        // appeared after a force-quit and relaunch.
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            Task { await appState.refreshVerificationStatus() }
        }
        .background(
            // `appState.isAdmin` only ever becomes true post-hydrate (i.e.
            // once signed in), so this is naturally inert on Welcome/onboarding
            // screens for everyone but an already-onboarded admin.
            ShakeDetector {
                guard appState.isAdmin, appState.faceIDGate == nil else { return }
                showDeveloperMenu = true
            }
        )
        .sheet(isPresented: $showDeveloperMenu) {
            DeveloperMenuView()
        }
        // Flow Triggers' Restart Onboarding flips `isOnboarded` from inside
        // the sheet. Close it, or onboarding starts hidden underneath it.
        .onChange(of: appState.isOnboarded) { _, isOnboarded in
            if !isOnboarded { showDeveloperMenu = false }
        }
        .alert(
            "Couldn't open the demo account",
            isPresented: Binding(get: { demoErrorMessage != nil }, set: { if !$0 { demoErrorMessage = nil } })
        ) {
            Button("OK") { demoErrorMessage = nil }
        } message: {
            Text(demoErrorMessage ?? "")
        }
        // Held back while the Face ID gate is up, so a photo link that cold
        // launched the app opens once it passes rather than over the gate.
        .fullScreenCover(item: Binding(
            get: { appState.faceIDGate == nil ? appState.deepLinkedPhoto : nil },
            set: { appState.deepLinkedPhoto = $0 }
        )) { deepLink in
            PhotoVerificationView(photoID: deepLink.id)
        }
        .task {
            // Supabase persists the session (Keychain-backed) across launches on its own.
            // `.initialSession` fires once, right after the client attempts to restore
            // it — but the loop keeps running for the life of the view afterward, since
            // a session revoked elsewhere (or a failed background token refresh) shows
            // up later on this same stream as `.signedOut`, and otherwise went unnoticed:
            // the app just kept showing stale local state and failing every request.
            for await state in supabase.auth.authStateChanges {
                switch state.event {
                case .initialSession:
                    if let userID = state.session?.user.id {
                        await resolveProfile(userID: userID)
                        // Every cold launch into a signed-in account asks
                        // for Face ID, after hydrating so it's known whether
                        // this is the demo account — which never signed in
                        // with Apple or Face ID, and says on every page
                        // that it proves nothing about who's holding it.
                        if !appState.isDemoAccount {
                            appState.faceIDGate = FaceIDGate(moment: .relaunch)
                        }
                    }
                    isRestoringSession = false
                    if isDemoEntryPending {
                        isDemoEntryPending = false
                        enterDemoAccount()
                    }
                case .signedOut:
                    // Ignore before the initial restore finishes — there's no prior
                    // session to have been revoked yet, and appState is already fresh.
                    guard !isRestoringSession else { continue }
                    appState.handleSessionInvalidated()
                default:
                    break
                }
            }
        }
    }

    /// Parses `thehumaninternet://photo/{id}`. Will swap to a Universal Link
    /// (`https://the-human-internet.com/{id}`) once the website hosts an
    /// apple-app-site-association file — this parsing/presentation logic stays
    /// the same either way.
    ///
    /// Also `thehumaninternet://demo`, which signs into the demo account —
    /// see `DemoAccount`.
    private func handle(url: URL) {
        if DemoAccount.isEntryLink(url) {
            if isRestoringSession {
                isDemoEntryPending = true
            } else {
                enterDemoAccount()
            }
            return
        }
        guard url.scheme == VerifiedPhoto.deepLinkScheme,
              url.host == VerifiedPhoto.deepLinkHost else { return }
        guard let id = UUID(uuidString: url.lastPathComponent) else { return }
        appState.deepLinkedPhoto = DeepLinkedPhoto(id: id)
    }

    private func enterDemoAccount() {
        guard !appState.isEnteringDemoAccount else { return }
        showDeveloperMenu = false
        Task {
            do {
                try await appState.enterDemoAccount()
                // The demo session has replaced the one the gate was
                // guarding. Only now: if entering fails, that account is
                // still signed in, so the gate has to stay up.
                appState.faceIDGate = nil
            } catch {
                Log.auth.error("Entering the demo account failed: \(error, privacy: .public)")
                demoErrorMessage = "Please try the link again."
            }
        }
    }

    /// A restored session only proves the identity is authenticated — it doesn't say
    /// whether onboarding was ever finished. Hydrate their `users` row (and photos)
    /// so `isOnboarded` and any previously-entered fields reflect reality, not a
    /// fresh default.
    private func resolveProfile(userID: UUID) async {
        do {
            try await appState.hydrate(userID: userID)
        } catch {
            Log.auth.error("Hydrate failed for \(userID, privacy: .public): \(error, privacy: .public)")
            appState.user = HumanUser(id: userID)
            appState.isOnboarded = false
        }
    }
}

#Preview {
    RootView()
        .environment(AppState())
}
