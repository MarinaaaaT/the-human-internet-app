//
//  CameraSession.swift
//  the-human-internet
//

import AVFoundation
import Observation

enum CameraSessionError: Error {
    case captureFailed
    /// No usable camera input is configured — e.g. the Simulator, which has
    /// no camera hardware at all. Calling `capturePhoto` on an
    /// `AVCapturePhotoOutput` with no active connection raises a fatal,
    /// un-catchable AVFoundation exception rather than a Swift error, so
    /// this must be checked *before* capturing, not caught after.
    case noCameraAvailable
}

/// Owns the live `AVCaptureSession` behind `CameraCaptureView`: authorization,
/// session lifecycle, front/back toggle, and a single-shot photo capture.
@Observable
final class CameraSession: NSObject {
    enum AuthorizationState {
        case notDetermined
        case authorized
        case denied
    }

    private(set) var authorizationState: AuthorizationState = .notDetermined
    private(set) var position: AVCaptureDevice.Position = .back
    /// False on the Simulator (no camera hardware) and in the rare case a
    /// physical device has no usable camera for the current position.
    private(set) var isCameraAvailable = false

    let session = AVCaptureSession()
    private let photoOutput = AVCapturePhotoOutput()
    private var currentInput: AVCaptureDeviceInput?
    private var captureContinuation: CheckedContinuation<Data, Error>?

    override init() {
        super.init()
        session.sessionPreset = .photo
    }

    func requestAuthorizationIfNeeded() async {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            authorizationState = .authorized
        case .notDetermined:
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            authorizationState = granted ? .authorized : .denied
        default:
            authorizationState = .denied
        }
    }

    /// Safe to call repeatedly — no-ops once already running.
    func start() {
        guard authorizationState == .authorized, !session.isRunning else { return }
        configureSessionIfNeeded()
        // Apple's documented guidance: startRunning() is blocking, so it
        // must not run on the main thread.
        let session = session
        Task.detached(priority: .userInitiated) {
            session.startRunning()
        }
    }

    func stop() {
        guard session.isRunning else { return }
        let session = session
        Task.detached(priority: .userInitiated) {
            session.stopRunning()
        }
    }

    func flipCamera() {
        position = position == .back ? .front : .back
        configureInput(for: position)
    }

    func capturePhoto() async throws -> Data {
        // Must be checked here, before calling capturePhoto — AVFoundation
        // raises a fatal exception for capturing with no active connection,
        // which a Swift `catch` cannot intercept.
        guard photoOutput.connection(with: .video) != nil else {
            throw CameraSessionError.noCameraAvailable
        }
        return try await withCheckedThrowingContinuation { continuation in
            captureContinuation = continuation
            photoOutput.capturePhoto(with: AVCapturePhotoSettings(), delegate: self)
        }
    }

    private func configureSessionIfNeeded() {
        guard currentInput == nil else { return }
        configureInput(for: position)
        if session.canAddOutput(photoOutput) {
            session.addOutput(photoOutput)
        }
    }

    private func configureInput(for position: AVCaptureDevice.Position) {
        session.beginConfiguration()
        defer { session.commitConfiguration() }

        if let currentInput {
            session.removeInput(currentInput)
        }

        guard
            let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position),
            let input = try? AVCaptureDeviceInput(device: device),
            session.canAddInput(input)
        else {
            isCameraAvailable = false
            return
        }

        session.addInput(input)
        currentInput = input
        isCameraAvailable = true
    }
}

extension CameraSession: AVCapturePhotoCaptureDelegate {
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        let continuation = captureContinuation
        captureContinuation = nil

        if let error {
            continuation?.resume(throwing: error)
            return
        }
        guard let data = photo.fileDataRepresentation() else {
            continuation?.resume(throwing: CameraSessionError.captureFailed)
            return
        }
        continuation?.resume(returning: data)
    }
}
