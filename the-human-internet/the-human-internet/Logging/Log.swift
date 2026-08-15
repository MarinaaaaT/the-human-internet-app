//
//  Log.swift
//  the-human-internet
//

import Foundation
import os

/// One `Logger` per functional area, all under the app's own subsystem.
/// Replaces `debugPrint`, which is stripped from nothing in release but also
/// goes nowhere useful — no `OSLog`, no telemetry, invisible the moment
/// nobody has Xcode attached. These persist into the system log, so a report
/// like "my photo never uploaded" can actually be diagnosed after the fact
/// via Console.app or `sysdiagnose` instead of requiring a live repro.
enum Log {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "com.marina.the-human-internet"

    static let auth = Logger(subsystem: subsystem, category: "auth")
    static let onboarding = Logger(subsystem: subsystem, category: "onboarding")
    static let camera = Logger(subsystem: subsystem, category: "camera")
    static let uploads = Logger(subsystem: subsystem, category: "uploads")
    static let photos = Logger(subsystem: subsystem, category: "photos")
    static let sharing = Logger(subsystem: subsystem, category: "sharing")
    static let settings = Logger(subsystem: subsystem, category: "settings")
    static let devMenu = Logger(subsystem: subsystem, category: "devMenu")
}
