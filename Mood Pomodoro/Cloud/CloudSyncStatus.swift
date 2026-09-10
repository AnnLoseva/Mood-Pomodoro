//
//  CloudSyncStatus.swift
//  Mood Pomodoro
//
//  CloudKit is the remote source of truth; SwiftData is the on-device
//  cache. This type only reports whether that remote layer is reachable —
//  it never blocks Start Session.
//

import CloudKit
import Foundation
import Observation

@MainActor
@Observable
final class CloudSyncStatus {
    enum Kind: Equatable {
        case checking
        /// iCloud account is available and this process opened a CloudKit store.
        case available
        /// User is signed out of iCloud — local SwiftData still works.
        case signedOut
        /// Could not open a CloudKit store (no entitlement, restricted account,
        /// personal team, etc.). Local-only until CloudKit can be enabled.
        case localOnly
    }

    var kind: Kind = .checking

    func refresh(usingCloudKitStore: Bool) async {
        guard usingCloudKitStore else {
            kind = .localOnly
            return
        }
        do {
            let status = try await CKContainer.default().accountStatus()
            switch status {
            case .available:
                kind = .available
            case .noAccount, .couldNotDetermine, .temporarilyUnavailable:
                kind = .signedOut
            case .restricted:
                kind = .localOnly
            @unknown default:
                kind = .signedOut
            }
        } catch {
            kind = .localOnly
        }
    }
}
