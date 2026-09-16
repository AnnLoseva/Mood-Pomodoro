//
//  SleepRecord.swift
//  Mood Pomodoro
//

import Foundation
import SwiftData

/// A night or a nap, cached on this device.
///
/// **This model is local-only and must never be added to
/// `PersistenceController.schema`.** That schema is opened with
/// `cloudKitDatabase: .automatic`, which would sync every model in it to the
/// user's private iCloud database — and Apple's review guidelines forbid
/// storing personal health information in iCloud. Sleep therefore lives in
/// its own container (`LocalHealthStore`), backed by its own file, with
/// CloudKit explicitly off. Manual entries live here too: they are the same
/// kind of information, and keeping one class of sleep out of iCloud while
/// putting another in would be the worst of both worlds.
///
/// The practical consequence, which the UI states rather than hides: sleep
/// does not travel between the iPhone and the iPad. Each device reads it
/// from HealthKit itself, which is exactly what Apple intends.
///
/// For HealthKit-derived rows this is a **cache**, not a record: HealthKit
/// stays the source of truth, `deterministicKey` lets a re-import replace
/// the same night rather than duplicate it, and the whole table can be
/// deleted and rebuilt at any time. Manual rows are the exception — they are
/// the user's own data and are never touched by an import.
@Model
final class SleepRecord {
    var id: UUID = UUID()
    /// `SleepAggregationService.identity(...)` — stable for the same night
    /// across re-imports, so a night the watch refines later updates in
    /// place instead of appearing twice.
    var deterministicKey: String = ""
    /// The calendar day the user woke up; what the diary files it under.
    var day: Date = Date.now
    var startDate: Date = Date.now
    var endDate: Date = Date.now
    var kindRaw: String = SleepKind.night.rawValue
    var sourceRaw: String = SleepSource.healthKit.rawValue

    var totalSleep: TimeInterval = 0
    var timeInBed: TimeInterval?
    var awakeDuration: TimeInterval = 0
    var coreDuration: TimeInterval = 0
    var deepDuration: TimeInterval = 0
    var remDuration: TimeInterval = 0
    var unspecifiedDuration: TimeInterval = 0
    /// Nil where the source wrote no Awake samples — which is not the same
    /// as an unbroken night. See `SleepAggregationService.awakeningCount`.
    var awakeningCount: Int?

    /// How the night felt, if the user said. **The user's own answer**, on
    /// an imported night as much as on a typed one — which is why `apply`
    /// below never clears it and a re-import cannot lose it. Nil means she
    /// wasn't asked or didn't answer; it is never a middling three.
    var qualityRaw: String?

    /// The resolved, overlap-free stage intervals, for the stage bar. Stored
    /// as JSON rather than a relationship: they are presentation detail of
    /// one cached row, not entities of their own.
    var intervalsJSON: Data = Data()

    /// What HealthKit said wrote the samples. Shown as-is — the app never
    /// claims to know it was an Apple Watch.
    var sourceName: String?
    var sourceBundleIdentifier: String?
    var productType: String?

    var note: String?
    var importedAt: Date = Date.now
    var updatedAt: Date = Date.now

    init(summary: SleepSessionSummary, note: String? = nil) {
        self.id = UUID()
        self.note = note
        apply(summary)
        self.importedAt = .now
    }

    /// Overwrites everything the summary describes, keeping `id` and
    /// `importedAt`. This is how HealthKit stays the source of truth: a
    /// refined night replaces its cached numbers instead of adding a row.
    func apply(_ summary: SleepSessionSummary) {
        deterministicKey = summary.id
        day = summary.day
        startDate = summary.start
        endDate = summary.end
        kindRaw = summary.kind.rawValue
        sourceRaw = summary.source.rawValue
        totalSleep = summary.totalSleep
        timeInBed = summary.timeInBed
        awakeDuration = summary.awake
        coreDuration = summary.duration(of: .core)
        deepDuration = summary.duration(of: .deep)
        remDuration = summary.duration(of: .rem)
        unspecifiedDuration = summary.duration(of: .unspecified)
        awakeningCount = summary.awakeningCount
        intervals = summary.intervals
        sourceName = summary.sourceName
        sourceBundleIdentifier = summary.sourceBundleIdentifier
        productType = summary.productType
        updatedAt = .now
        // `qualityRaw` and `note` are deliberately absent: they are the
        // user's, not HealthKit's, and a refined night must not erase them.
    }

    var kind: SleepKind {
        get { SleepKind(rawValue: kindRaw) ?? .night }
        set { kindRaw = newValue.rawValue }
    }

    var source: SleepSource {
        get { SleepSource(rawValue: sourceRaw) ?? .healthKit }
        set { sourceRaw = newValue.rawValue }
    }

    var quality: SleepQuality? {
        get { qualityRaw.flatMap(SleepQuality.init(rawValue:)) }
        set { qualityRaw = newValue?.rawValue }
    }

    var intervals: [SleepInterval] {
        get {
            guard !intervalsJSON.isEmpty else { return [] }
            return (try? JSONDecoder().decode([StoredInterval].self, from: intervalsJSON))?
                .map { SleepInterval(stage: $0.stage, start: $0.start, end: $0.end) } ?? []
        }
        set {
            let stored = newValue.map { StoredInterval(stage: $0.stage, start: $0.start, end: $0.end) }
            intervalsJSON = (try? JSONEncoder().encode(stored)) ?? Data()
        }
    }

    var summary: SleepSessionSummary {
        SleepSessionSummary(
            id: deterministicKey,
            day: day,
            kind: kind,
            source: source,
            start: startDate,
            end: endDate,
            totalSleep: totalSleep,
            timeInBed: timeInBed,
            awake: awakeDuration,
            stageDurations: [
                .core: coreDuration,
                .deep: deepDuration,
                .rem: remDuration,
                .unspecified: unspecifiedDuration,
                .awake: awakeDuration
            ].filter { $0.value > 0 },
            awakeningCount: awakeningCount,
            intervals: intervals,
            sourceName: sourceName,
            sourceBundleIdentifier: sourceBundleIdentifier,
            productType: productType,
            quality: quality,
            note: note
        )
    }
}

/// `SleepInterval` is a plain value; this is just its `Codable` shape, kept
/// separate so the model's storage format doesn't constrain the value type.
private struct StoredInterval: Codable {
    let stage: SleepStage
    let start: Date
    let end: Date
}
