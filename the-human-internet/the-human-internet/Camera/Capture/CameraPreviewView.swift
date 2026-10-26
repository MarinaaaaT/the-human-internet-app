//
//  CameraPreviewView.swift
//  the-human-internet
//

import AVFoundation
import SwiftUI

/// SwiftUI has no native live-camera view, so this wraps
/// `AVCaptureVideoPreviewLayer` the standard way: a `UIView` subclass whose
/// backing layer *is* the preview layer, via `layerClass`.
struct CameraPreviewView: UIViewRepresentable {
    let session: AVCaptureSession
    /// A tap on the preview, with where it landed in the view and the same
    /// spot in the camera's own space, for `CameraSession.focus(at:)`. The
    /// preview layer does that conversion because only it knows how much of
    /// the frame its aspect fill cropped away.
    var onTap: (_ location: CGPoint, _ devicePoint: CGPoint) -> Void = { _, _ in }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> PreviewUIView {
        let view = PreviewUIView()
        view.videoPreviewLayer.session = session
        view.videoPreviewLayer.videoGravity = .resizeAspectFill
        view.addGestureRecognizer(
            UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
        )
        context.coordinator.onTap = onTap
        return view
    }

    func updateUIView(_ uiView: PreviewUIView, context: Context) {
        context.coordinator.onTap = onTap
    }

    final class Coordinator: NSObject {
        var onTap: (CGPoint, CGPoint) -> Void = { _, _ in }

        @objc func handleTap(_ recognizer: UITapGestureRecognizer) {
            guard let view = recognizer.view as? PreviewUIView else { return }
            // The view's layer is the preview layer, so view and layer
            // coordinates are the same.
            let location = recognizer.location(in: view)
            onTap(location, view.videoPreviewLayer.captureDevicePointConverted(fromLayerPoint: location))
        }
    }

    final class PreviewUIView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }

        var videoPreviewLayer: AVCaptureVideoPreviewLayer {
            // Force-cast is safe: layerClass above guarantees this type.
            layer as! AVCaptureVideoPreviewLayer
        }
    }
}
