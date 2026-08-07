//
//  ActivityView.swift
//  the-human-internet
//

import SwiftUI

/// Presents `UIActivityViewController` directly via `present(_:animated:)`
/// on an invisible anchor view controller, rather than as SwiftUI `.sheet`
/// content. Wrapping it as sheet content nests it inside SwiftUI's own
/// presentation container — some share extensions (Instagram, X) crashed
/// under that extra layer, apparently expecting to be presented directly on
/// top of the host app's own view controller hierarchy.
struct ActivityView: UIViewControllerRepresentable {
    @Binding var isPresented: Bool
    let activityItems: [Any]
    var excludedActivityTypes: [UIActivity.ActivityType] = []
    /// Fires once the sheet is gone, whether the user completed a share or
    /// cancelled — the caller uses this to clean up any temp file it wrote
    /// for `activityItems`.
    var onComplete: (() -> Void)?

    func makeUIViewController(context: Context) -> UIViewController {
        UIViewController()
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {
        if isPresented, uiViewController.presentedViewController == nil, !activityItems.isEmpty {
            let activityVC = UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
            activityVC.excludedActivityTypes = excludedActivityTypes
            activityVC.completionWithItemsHandler = { _, _, _, _ in
                isPresented = false
                onComplete?()
            }
            // iPad/Mac Catalyst requires a popover source or this crashes —
            // harmless to set unconditionally on iPhone.
            if let popover = activityVC.popoverPresentationController {
                popover.sourceView = uiViewController.view
                popover.sourceRect = CGRect(
                    x: uiViewController.view.bounds.midX,
                    y: uiViewController.view.bounds.midY,
                    width: 0,
                    height: 0
                )
            }
            uiViewController.present(activityVC, animated: true)
        } else if !isPresented, uiViewController.presentedViewController is UIActivityViewController {
            uiViewController.presentedViewController?.dismiss(animated: true)
        }
    }
}
