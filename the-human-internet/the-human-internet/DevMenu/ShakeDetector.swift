//
//  ShakeDetector.swift
//  the-human-internet
//

import SwiftUI
import UIKit

/// SwiftUI has no shake gesture; `motionEnded` only fires on a UIResponder in
/// the chain, so this bridges via an invisible UIViewController that becomes
/// first responder as soon as it appears.
struct ShakeDetector: UIViewControllerRepresentable {
    var onShake: () -> Void

    func makeUIViewController(context: Context) -> ShakeDetectingViewController {
        let controller = ShakeDetectingViewController()
        controller.onShake = onShake
        return controller
    }

    func updateUIViewController(_ uiViewController: ShakeDetectingViewController, context: Context) {
        uiViewController.onShake = onShake
    }

    final class ShakeDetectingViewController: UIViewController {
        var onShake: (() -> Void)?

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            becomeFirstResponder()
        }

        override var canBecomeFirstResponder: Bool { true }

        override func motionEnded(_ motion: UIEvent.EventSubtype, with event: UIEvent?) {
            if motion == .motionShake {
                onShake?()
            }
        }
    }
}
