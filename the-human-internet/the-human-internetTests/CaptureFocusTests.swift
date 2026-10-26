//
//  CaptureFocusTests.swift
//  the-human-internetTests
//

import AVFoundation
import Testing

@testable import the_human_internet

/// Tap to focus has to hold where it was tapped, hand control back when
/// reset, and do as much as a camera supports rather than nothing. The
/// Simulator has no camera, so a fake device records what was set.
struct CaptureFocusTests {
    private let tapped = CGPoint(x: 0.2, y: 0.7)

    @Test func aTapFocusesAndExposesThereAndHolds() {
        let device = FakeDevice()

        CaptureFocus.lock(device, at: tapped)

        #expect(device.focusPointOfInterest == tapped)
        #expect(device.focusMode == .autoFocus)
        #expect(device.exposurePointOfInterest == tapped)
        #expect(device.exposureMode == .autoExpose)
        #expect(device.isSubjectAreaChangeMonitoringEnabled)
        #expect(device.isLocked == false)
    }

    /// A point only takes effect when a mode is set after it.
    @Test func eachPointIsSetBeforeTheModeThatAppliesIt() {
        let device = FakeDevice()

        CaptureFocus.lock(device, at: tapped)

        #expect(device.changes == [.focusPoint, .focusMode, .exposurePoint, .exposureMode, .monitoring])
    }

    @Test func aCameraThatCantFocusOnAPointStillExposesThere() {
        let device = FakeDevice(supportsFocusPoint: false)

        CaptureFocus.lock(device, at: tapped)

        #expect(device.focusMode == .continuousAutoFocus)
        #expect(device.exposurePointOfInterest == tapped)
        #expect(device.exposureMode == .autoExpose)
    }

    @Test func resetHandsFocusBackToTheCamera() {
        let device = FakeDevice()
        CaptureFocus.lock(device, at: tapped)

        CaptureFocus.reset(device)

        #expect(device.focusPointOfInterest == CaptureFocus.center)
        #expect(device.focusMode == .continuousAutoFocus)
        #expect(device.exposurePointOfInterest == CaptureFocus.center)
        #expect(device.exposureMode == .continuousAutoExposure)
        #expect(!device.isSubjectAreaChangeMonitoringEnabled)
    }

    @Test func aDeviceThatWontLockIsLeftAlone() {
        let device = FakeDevice(locks: false)

        CaptureFocus.lock(device, at: tapped)

        #expect(device.changes.isEmpty)
    }
}

private final class FakeDevice: FocusableCaptureDevice {
    enum Change: Equatable {
        case focusPoint, focusMode, exposurePoint, exposureMode, monitoring
    }

    struct LockRefused: Error {}

    private let supportsFocusPoint: Bool
    private let locks: Bool
    private(set) var isLocked = false
    private(set) var changes: [Change] = []

    init(supportsFocusPoint: Bool = true, locks: Bool = true) {
        self.supportsFocusPoint = supportsFocusPoint
        self.locks = locks
    }

    var isFocusPointOfInterestSupported: Bool { supportsFocusPoint }
    var focusPointOfInterest = CaptureFocus.center { didSet { record(.focusPoint) } }
    var focusMode = AVCaptureDevice.FocusMode.continuousAutoFocus { didSet { record(.focusMode) } }
    func isFocusModeSupported(_ focusMode: AVCaptureDevice.FocusMode) -> Bool { true }

    var isExposurePointOfInterestSupported: Bool { true }
    var exposurePointOfInterest = CaptureFocus.center { didSet { record(.exposurePoint) } }
    var exposureMode = AVCaptureDevice.ExposureMode.continuousAutoExposure { didSet { record(.exposureMode) } }
    func isExposureModeSupported(_ exposureMode: AVCaptureDevice.ExposureMode) -> Bool { true }

    var isSubjectAreaChangeMonitoringEnabled = false { didSet { record(.monitoring) } }

    func lockForConfiguration() throws {
        guard locks else { throw LockRefused() }
        isLocked = true
    }

    func unlockForConfiguration() {
        isLocked = false
    }

    /// AVFoundation raises an exception for a change made without the lock.
    private func record(_ change: Change) {
        #expect(isLocked, "\(change) set without the configuration lock")
        changes.append(change)
    }
}
