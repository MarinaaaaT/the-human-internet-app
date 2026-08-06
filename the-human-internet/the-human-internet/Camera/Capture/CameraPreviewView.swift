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

    func makeUIView(context: Context) -> PreviewUIView {
        let view = PreviewUIView()
        view.videoPreviewLayer.session = session
        view.videoPreviewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ uiView: PreviewUIView, context: Context) {}

    final class PreviewUIView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }

        var videoPreviewLayer: AVCaptureVideoPreviewLayer {
            // Force-cast is safe: layerClass above guarantees this type.
            layer as! AVCaptureVideoPreviewLayer
        }
    }
}
