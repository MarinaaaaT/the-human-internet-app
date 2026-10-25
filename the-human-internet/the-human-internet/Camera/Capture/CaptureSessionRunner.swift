//
//  CaptureSessionRunner.swift
//  the-human-internet
//

import AVFoundation
import os

/// The part of `AVCaptureSession` that `CaptureSessionRunner` drives, so
/// tests can stand in a fake with no camera behind it.
protocol RunnableCaptureSession: AnyObject {
    var isRunning: Bool { get }
    func startRunning()
    func stopRunning()
}

extension AVCaptureSession: RunnableCaptureSession {}

/// Starts and stops a capture session off the main thread, and always ends
/// in whichever state was asked for *last*, however fast the requests come.
///
/// This replaced `CameraSession.start()`/`stop()` each checking
/// `session.isRunning` on the main thread and then handing the blocking call
/// to its own detached task. `isRunning` only flips once that call returns,
/// so switching Camera → Profile → Camera quickly ran `stop()` (dispatched,
/// still in flight), then `start()`, which saw the session still running and
/// returned. The stop then landed and the preview froze until the tab was
/// switched again slowly (BUG-9). Two detached tasks weren't ordered either.
///
/// Here every request goes through one serial queue, so they can't reorder,
/// and each queued step checks `isRunning` on that queue, where it's
/// accurate because `startRunning()`/`stopRunning()` block until done. Each
/// step also reads the *latest* request, not the one that queued it. A burst
/// of tab switches therefore costs one start or stop plus at most one more,
/// rather than replaying the whole burst while the preview flickers.
final class CaptureSessionRunner {
    private let session: RunnableCaptureSession
    private let queue: DispatchQueue
    private let wantsRunning = OSAllocatedUnfairLock(initialState: false)

    init(session: RunnableCaptureSession, queue: DispatchQueue = DispatchQueue(label: "camera.session", qos: .userInitiated)) {
        self.session = session
        self.queue = queue
    }

    func setRunning(_ running: Bool) {
        wantsRunning.withLock { $0 = running }
        queue.async { [session, wantsRunning] in
            let wanted = wantsRunning.withLock { $0 }
            if wanted, !session.isRunning {
                session.startRunning()
            } else if !wanted, session.isRunning {
                session.stopRunning()
            }
        }
    }
}
