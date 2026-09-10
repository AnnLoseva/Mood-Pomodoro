//
//  SessionSegment.swift
//  Mood Pomodoro
//

import Foundation
import SwiftData

/// Whether a `SessionSegment` was spent working or on a break. Named to match
/// `SessionManager.pause()`/`resume()` rather than the spec's `.work`/`.break`
/// (`break` is a reserved word) — same semantics.
enum SegmentType: String, Codable, Sendable {
    case work
    case pause
}

/// One contiguous stretch of a session's timeline — either work or a break —
/// bounded by real timestamps. `FocusSession.state`/duration math is built
/// entirely out of these rather than a running `elapsedSeconds` counter, so
/// it survives app suspension/termination: reopening the app just re-reads
/// `startDate`/`endDate` off whatever segments already exist (see section 28
/// of the tracking spec — "не хранить elapsedSeconds, использовать segments").
/// `endDate == nil` means this is the currently-open segment.
@Model
final class SessionSegment {
    var id: UUID = UUID()
    var typeRaw: String = SegmentType.work.rawValue
    var startDate: Date = Date.now
    var endDate: Date?
    var createdAt: Date = Date.now
    var session: FocusSession?

    init(id: UUID = UUID(), type: SegmentType, startDate: Date = .now, endDate: Date? = nil) {
        self.id = id
        self.typeRaw = type.rawValue
        self.startDate = startDate
        self.endDate = endDate
        self.createdAt = startDate
    }

    var type: SegmentType {
        get { SegmentType(rawValue: typeRaw) ?? .work }
        set { typeRaw = newValue.rawValue }
    }

    /// This segment's length as of `referenceDate`: closed segments are
    /// capped at `endDate`, but a query *during* a later-closed segment
    /// (e.g. time-to-fatigue at a check-in) only counts up to that moment.
    func duration(asOf referenceDate: Date = .now) -> TimeInterval {
        let effectiveEnd = min(endDate ?? referenceDate, referenceDate)
        return max(0, effectiveEnd.timeIntervalSince(startDate))
    }
}
