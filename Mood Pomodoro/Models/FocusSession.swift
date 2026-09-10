//
//  FocusSession.swift
//  Mood Pomodoro
//

import Foundation
import SwiftData

/// How a session came to exist. A `.manual` session was typed in after the
/// fact ("я с 10 до 12 училась") — it has one closed work segment, never
/// schedules check-ins, and is the only kind whose times the user edits.
enum SessionOrigin: String, Codable, Sendable {
    case timer
    case manual
}

@Model
final class FocusSession {
    /// CloudKit does not allow `@Attribute(.unique)`; identity is still `id`.
    var id: UUID = UUID()
    var activity: String = ""
    var startDate: Date = Date.now
    var endDate: Date?
    var checkInIntervalMinutes: Int = 10
    var stateRaw: String = SessionState.active.rawValue
    var originRaw: String = SessionOrigin.timer.rawValue
    var note: String?
    /// When the record was written. Equal to `startDate` for timer sessions;
    /// for a backdated one it is the moment the user remembered, while
    /// `startDate` stays the moment the activity actually began.
    var createdAt: Date = Date.now
    var updatedAt: Date = Date.now

    @Relationship(deleteRule: .cascade, inverse: \CheckIn.session)
    var checkIns: [CheckIn]? = []

    /// Every condition change during this session, oldest first is not
    /// guaranteed — sort by `timestamp` when order matters. See
    /// `activeConditions(asOf:)` for reconstructing "what was true when".
    @Relationship(deleteRule: .cascade, inverse: \ConditionEvent.session)
    var conditionEvents: [ConditionEvent]? = []

    /// Work/break segments — the source of truth for every duration
    /// computation below. See `SessionSegment` for why.
    @Relationship(deleteRule: .cascade, inverse: \SessionSegment.session)
    var segments: [SessionSegment]? = []

    init(
        id: UUID = UUID(),
        activity: String,
        startDate: Date = .now,
        checkInIntervalMinutes: Int
    ) {
        self.id = id
        self.activity = activity
        self.startDate = startDate
        self.endDate = nil
        self.checkInIntervalMinutes = checkInIntervalMinutes
        self.stateRaw = SessionState.active.rawValue
        self.createdAt = startDate
        self.updatedAt = startDate
    }

    func touch(at date: Date = .now) {
        updatedAt = date
    }

    var state: SessionState {
        get {
            if let decoded = SessionState(rawValue: stateRaw) {
                return decoded
            }
            // Legacy rows from before `stateRaw` existed: empty/unknown
            // decodes as completed once `endDate` is set, otherwise active.
            return endDate == nil ? .active : .completed
        }
        set { stateRaw = newValue.rawValue }
    }

    /// True while the session occupies the "current session" slot — active
    /// *or* paused. Matches the meaning `isActive` already had everywhere in
    /// the app (paused sessions were never treated as finished).
    var isActive: Bool { state == .active || state == .paused }
    var isPaused: Bool { state == .paused }

    var origin: SessionOrigin {
        get { SessionOrigin(rawValue: originRaw) ?? .timer }
        set { originRaw = newValue.rawValue }
    }

    var isManualEntry: Bool { origin == .manual }

    var checkInInterval: TimeInterval { TimeInterval(checkInIntervalMinutes * 60) }

    var sortedSegments: [SessionSegment] { (segments ?? []).sorted { $0.startDate < $1.startDate } }

    /// The still-open segment (work or break), if any. A well-formed active/
    /// paused session always has exactly one.
    var currentSegment: SessionSegment? { (segments ?? []).first { $0.endDate == nil } }

    /// Sum of every *work* segment's length, `.pause` segments excluded.
    /// This is "active work time" throughout the app — the number shown on
    /// the timer, and what notification scheduling is anchored to.
    func activeWorkDuration(asOf referenceDate: Date = .now) -> TimeInterval {
        sortedSegments.filter { $0.type == .work }.reduce(0) { $0 + $1.duration(asOf: referenceDate) }
    }

    /// Sum of every break segment's length.
    func breakDuration(asOf referenceDate: Date = .now) -> TimeInterval {
        sortedSegments.filter { $0.type == .pause }.reduce(0) { $0 + $1.duration(asOf: referenceDate) }
    }

    /// Total wall-clock span since start (active + break combined) — `endDate
    /// - startDate` once finished, `referenceDate - startDate` while ongoing.
    func totalDuration(asOf referenceDate: Date = .now) -> TimeInterval {
        max(0, (endDate ?? referenceDate).timeIntervalSince(startDate))
    }

    var numberOfBreaks: Int { (segments ?? []).filter { $0.type == .pause }.count }

    var averageBreakDuration: TimeInterval? {
        let breaks = (segments ?? []).filter { $0.type == .pause }.map { $0.duration() }
        guard !breaks.isEmpty else { return nil }
        return breaks.reduce(0, +) / Double(breaks.count)
    }

    var longestBreakDuration: TimeInterval? {
        (segments ?? []).filter { $0.type == .pause }.map { $0.duration() }.max()
    }

    /// Elapsed *active* time (excludes paused duration), as of `referenceDate`.
    /// Kept as its own name (rather than just calling sites use
    /// `activeWorkDuration` directly) since it reads better at call sites
    /// that mean "how long has the timer been running".
    func elapsedActiveTime(asOf referenceDate: Date = .now) -> TimeInterval {
        activeWorkDuration(asOf: referenceDate)
    }

    /// The anchor date check-in checkpoints are computed from. Shifts forward
    /// by however much break time has accumulated, so reminders stay tied to
    /// active time, not wall clock. Only meaningful while not currently
    /// paused (every break segment closed) — which is the only time callers
    /// use it (scheduling only ever happens in the `.active` state).
    var scheduleAnchor: Date {
        startDate.addingTimeInterval(breakDuration())
    }

    var sortedCheckIns: [CheckIn] {
        (checkIns ?? []).sorted { $0.timestamp < $1.timestamp }
    }

    var sortedConditionEvents: [ConditionEvent] {
        (conditionEvents ?? []).sorted { $0.timestamp < $1.timestamp }
    }

    /// Reconstructs which condition was active per category as of `date`:
    /// for each category, the most recent event at or before that moment.
    /// This is what makes a mid-session condition change ("switched to
    /// pu-erh at 10:45") retroactively correct for check-ins before that
    /// point — they simply never see the later event.
    func activeConditions(asOf date: Date) -> [ConditionSnapshotEntry] {
        let relevant = (conditionEvents ?? []).filter { $0.timestamp <= date }
        let latestPerCategory = Dictionary(grouping: relevant, by: \.categoryID)
            .compactMapValues { events in events.max { $0.timestamp < $1.timestamp } }
        return latestPerCategory.values
            .map(\.asSnapshotEntry)
            .sorted { $0.categoryName < $1.categoryName }
    }
}
