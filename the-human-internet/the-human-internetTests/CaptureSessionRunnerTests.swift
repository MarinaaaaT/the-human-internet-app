//
//  CaptureSessionRunnerTests.swift
//  the-human-internetTests
//

import Foundation
import os
import Testing

@testable import the_human_internet

/// Switching between the Camera and Profile tabs quickly must leave the
/// camera in whichever state was asked for last (BUG-9: it froze). The fake
/// session holds each start/stop until released, standing in for
/// AVFoundation's calls taking hundreds of milliseconds, so a test can switch
/// tabs while one is still in flight.
struct CaptureSessionRunnerTests {
    private let queue = DispatchQueue(label: "test.camera.session")

    @Test func switchingBackWhileAStopIsInFlightLeavesTheCameraRunning() {
        let session = FakeSession(running: true)
        let runner = CaptureSessionRunner(session: session, queue: queue)

        runner.setRunning(false)
        session.callBegan.wait()
        // What the old start() read on the main thread, and returned on.
        #expect(session.isRunning)
        runner.setRunning(true)
        session.release()
        queue.sync {}

        #expect(session.isRunning)
    }

    @Test func leavingWhileAStartIsInFlightLeavesTheCameraStopped() {
        let session = FakeSession(running: false)
        let runner = CaptureSessionRunner(session: session, queue: queue)

        runner.setRunning(true)
        session.callBegan.wait()
        runner.setRunning(false)
        session.release()
        queue.sync {}

        #expect(!session.isRunning)
    }

    @Test func aBurstOfSwitchesIsNotReplayed() {
        let session = FakeSession(running: false)
        let runner = CaptureSessionRunner(session: session, queue: queue)

        runner.setRunning(true)
        session.callBegan.wait()
        for _ in 0..<5 {
            runner.setRunning(false)
            runner.setRunning(true)
        }
        session.release()
        queue.sync {}

        #expect(session.isRunning)
        #expect(session.starts == 1)
        #expect(session.stops == 0)
    }
}

private final class FakeSession: RunnableCaptureSession {
    private struct State {
        var isRunning: Bool
        var starts = 0
        var stops = 0
    }

    private let state: OSAllocatedUnfairLock<State>
    private let held = DispatchGroup()
    /// Signalled as each start or stop begins.
    let callBegan = DispatchSemaphore(value: 0)

    init(running: Bool) {
        state = OSAllocatedUnfairLock(initialState: State(isRunning: running))
        held.enter()
    }

    var isRunning: Bool { state.withLock { $0.isRunning } }
    var starts: Int { state.withLock { $0.starts } }
    var stops: Int { state.withLock { $0.stops } }

    func startRunning() { transition(toRunning: true) }
    func stopRunning() { transition(toRunning: false) }

    /// Lets the call in flight, and every later one, complete. Call once.
    func release() { held.leave() }

    private func transition(toRunning running: Bool) {
        callBegan.signal()
        held.wait()
        state.withLock {
            $0.isRunning = running
            if running { $0.starts += 1 } else { $0.stops += 1 }
        }
    }
}
