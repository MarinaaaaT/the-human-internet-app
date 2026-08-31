//
//  MessageComposeView.swift
//  the-human-internet
//

import MessageUI
import SwiftUI

/// Presents `MFMessageComposeViewController` — the in-app Messages
/// composer — so the Messages icon never goes through the generic share
/// sheet.
///
/// Messages is the one destination that accepts pre-filled body text
/// from a third-party app, so the verification link can already be in the
/// draft with nothing to paste. Every other platform either rejects
/// third-party caption text by policy (Facebook, Instagram) or drops it
/// silently, which is why they keep the clipboard + instructions path.
///
/// It sends the link alone — no photo attachment. The link unfurls into
/// the Open Graph card, which carries the picture *and* stays tappable
/// through to the proof; an attached JPEG would be neither, since the
/// C2PA manifest doesn't survive being re-encoded downstream.
///
/// Presented on an invisible anchor view controller rather than as SwiftUI
/// `.sheet` content, mirroring `ActivityView` — see that file for why.
struct MessageComposeView: UIViewControllerRepresentable {
    @Binding var isPresented: Bool
    let body: String

    /// Whether this device can send messages at all. False on the
    /// Simulator, and on hardware with no Messages account configured —
    /// callers must fall back to the generic share sheet rather than
    /// presenting a composer that can't send.
    static var canSendText: Bool { MFMessageComposeViewController.canSendText() }

    func makeUIViewController(context: Context) -> UIViewController {
        UIViewController()
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {
        // Kept current so the coordinator's binding and completion handler
        // never act on a stale snapshot of this struct.
        context.coordinator.parent = self

        if isPresented, uiViewController.presentedViewController == nil {
            let composer = MFMessageComposeViewController()
            composer.messageComposeDelegate = context.coordinator
            composer.body = body
            uiViewController.present(composer, animated: true)
        } else if !isPresented, uiViewController.presentedViewController is MFMessageComposeViewController {
            uiViewController.presentedViewController?.dismiss(animated: true)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    final class Coordinator: NSObject, MFMessageComposeViewControllerDelegate {
        var parent: MessageComposeView

        init(_ parent: MessageComposeView) {
            self.parent = parent
        }

        func messageComposeViewController(
            _ controller: MFMessageComposeViewController,
            didFinishWith result: MessageComposeResult
        ) {
            controller.dismiss(animated: true) { [parent] in
                parent.isPresented = false
            }
        }
    }
}
