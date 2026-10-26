//
//  CaptureFocus.swift
//  the-human-internet
//

import AVFoundation

/// The part of `AVCaptureDevice` that focusing touches, so tests can stand
/// in a fake with no camera behind it.
protocol FocusableCaptureDevice: AnyObject {
    var isFocusPointOfInterestSupported: Bool { get }
    var focusPointOfInterest: CGPoint { get set }
    var focusMode: AVCaptureDevice.FocusMode { get set }
    func isFocusModeSupported(_ focusMode: AVCaptureDevice.FocusMode) -> Bool

    var isExposurePointOfInterestSupported: Bool { get }
    var exposurePointOfInterest: CGPoint { get set }
    var exposureMode: AVCaptureDevice.ExposureMode { get set }
    func isExposureModeSupported(_ exposureMode: AVCaptureDevice.ExposureMode) -> Bool

    var isSubjectAreaChangeMonitoringEnabled: Bool { get set }
    func lockForConfiguration() throws
    func unlockForConfiguration()
}

extension AVCaptureDevice: FocusableCaptureDevice {}

/// Tap to focus, as the system Camera app does it: a tap focuses and exposes
/// once on that spot and holds there, until the scene changes enough that
/// the hold is stale, when the camera goes back to choosing for itself.
///
/// Points are in the device's own space, (0,0) top-left to (1,1)
/// bottom-right of the sensor in landscape. Get one from
/// `AVCaptureVideoPreviewLayer.captureDevicePointConverted(fromLayerPoint:)`,
/// which accounts for the preview's aspect-fill crop and orientation.
enum CaptureFocus {
    static let center = CGPoint(x: 0.5, y: 0.5)

    /// Focuses and exposes on `point` once, then holds. Turns on subject-area
    /// monitoring, so `AVCaptureDevice.subjectAreaDidChangeNotification`
    /// fires when the scene moves on; answer it with `reset(_:)`.
    static func lock(_ device: FocusableCaptureDevice, at point: CGPoint) {
        configure(device) {
            // The point only takes effect when a mode is set after it, so the
            // order of each pair matters. A camera that can't focus on a
            // point (some front cameras) still exposes there.
            if device.isFocusPointOfInterestSupported, device.isFocusModeSupported(.autoFocus) {
                device.focusPointOfInterest = point
                device.focusMode = .autoFocus
            }
            if device.isExposurePointOfInterestSupported, device.isExposureModeSupported(.autoExpose) {
                device.exposurePointOfInterest = point
                device.exposureMode = .autoExpose
            }
            device.isSubjectAreaChangeMonitoringEnabled = true
        }
    }

    /// Hands focus and exposure back to the camera, centred and continuous,
    /// which is where a camera starts.
    static func reset(_ device: FocusableCaptureDevice) {
        configure(device) {
            if device.isFocusPointOfInterestSupported {
                device.focusPointOfInterest = center
            }
            if device.isFocusModeSupported(.continuousAutoFocus) {
                device.focusMode = .continuousAutoFocus
            }
            if device.isExposurePointOfInterestSupported {
                device.exposurePointOfInterest = center
            }
            if device.isExposureModeSupported(.continuousAutoExposure) {
                device.exposureMode = .continuousAutoExposure
            }
            device.isSubjectAreaChangeMonitoringEnabled = false
        }
    }

    private static func configure(_ device: FocusableCaptureDevice, _ changes: () -> Void) {
        do {
            try device.lockForConfiguration()
        } catch {
            // Another client holds the device. The camera keeps focusing on
            // its own, so a missed tap is the whole cost.
            Log.camera.error("Couldn't lock camera to focus: \(error, privacy: .public)")
            return
        }
        defer { device.unlockForConfiguration() }
        changes()
    }
}
