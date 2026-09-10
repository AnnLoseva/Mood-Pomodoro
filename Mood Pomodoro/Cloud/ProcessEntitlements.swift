//
//  ProcessEntitlements.swift
//  Mood Pomodoro
//
//  Personal teams cannot ship iCloud/CloudKit entitlements. Calling
//  CKContainer or NSUbiquitousKeyValueStore without them logs a hard
//  client bug. This build is local-only until a paid team attaches
//  `Mood Pomodoro.entitlements` in Signing & Capabilities.
//

import Foundation

enum ProcessEntitlements {
    /// Flip to `true` after Xcode Signing & Capabilities includes iCloud
    /// (CloudKit) on a paid Apple Developer team. The entitlements file is
    /// already at `Mood Pomodoro/Mood Pomodoro.entitlements`.
    static let supportsCloudKit = false

    static let supportsUbiquitousKeyValueStore = false
}
