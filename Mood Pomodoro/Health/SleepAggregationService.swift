//
//  SleepAggregationService.swift
//  Mood Pomodoro
//

import Foundation

/// Turns a pile of HealthKit sleep intervals into nights and naps.
///
/// This is the whole risk of the feature and none of the platform: HealthKit
/// hands back overlapping samples from possibly several sources, with no
/// notion of "a night". So it lives here, as pure functions over value
/// types, and is tested without a device.
///
/// The rules, in order:
/// 1. **One source per session.** Several apps may describe the same night.
///    Mixing them would double-count, so one is chosen (see `preferredSource`).
/// 2. **Resolve overlaps by precedence, not by addition.** Any minute
///    belongs to exactly one stage — the most specific one claiming it.
///    `inBed` never wins, because it spans everything.
/// 3. **Total sleep is a measure of a union, never a sum of samples.**
///    Awake stretches are removed from it; `inBed` is reported apart and
///    never added.
/// 4. **A session ends where a long enough gap begins**, so a night and an
///    afternoon nap can never merge into one twelve-hour "sleep".
/// 5. **A session belongs to the day it ended** — the day the user woke up
///    and then lived.
/// 6. **A manual entry beats an imported one where they overlap**, and the
///    loser is marked rather than deleted — see `resolveOverlaps(sessions:)`.
enum SleepAggregationService {

    /// A gap at least this long starts a new session. Long enough to ride
    /// out a trip to the kitchen or a watch charging for half an hour,
    /// short enough that a morning and an afternoon sleep stay two things.
    static let sessionGap: TimeInterval = 60 * 60

    /// Below this, a session can still be a night — but only if it landed in
    /// the small hours (see `kind(for:)`).
    static let nightDurationThreshold: TimeInterval = 4 * 60 * 60

    /// Sleep this short is not reported at all: a two-minute "asleep" blip
    /// is noise, and showing it as a nap would be worse than saying nothing.
    static let minimumSessionDuration: TimeInterval = 10 * 60

    // MARK: - Entry point

    /// Everything HealthKit gave us, grouped into sessions.
    ///
    /// - Parameter intervalsBySource: raw intervals keyed by the source that
    ///   wrote them. Keeping them separated until a session is picked is
    ///   what makes rule 1 possible.
    static func sessions(
        from intervalsBySource: [SleepSourceKey: [SleepInterval]],
        calendar: Calendar = .current
    ) -> [SleepSessionSummary] {
        // Sessions are found on the union of *all* sources' time spans, so a
        // night that only one app recorded is still found. Which source
        // describes each session is decided afterwards, per session.
        let everything = intervalsBySource.values.flatMap { $0 }.filter { !$0.isEmpty }
        guard !everything.isEmpty else { return [] }

        var summaries: [SleepSessionSummary] = []
        for span in spans(of: everything) {
            let range = span.start...span.end
            let candidates = intervalsBySource.compactMapValues { intervals -> [SleepInterval]? in
                let clipped = intervals.compactMap { $0.clamped(to: range) }
                return clipped.isEmpty ? nil : clipped
            }
            guard let key = preferredSource(among: candidates),
                  let intervals = candidates[key],
                  let summary = summary(
                      of: intervals,
                      source: key,
                      origin: .healthKit,
                      calendar: calendar
                  )
            else { continue }
            summaries.append(summary)
        }
        return summaries.sorted { $0.start < $1.start }
    }

    /// One session's numbers, from intervals already known to belong
    /// together and to come from one source. Also the path a manual entry
    /// takes, with a single `unspecified` interval.
    static func summary(
        of intervals: [SleepInterval],
        source: SleepSourceKey? = nil,
        origin: SleepSource = .healthKit,
        calendar: Calendar = .current
    ) -> SleepSessionSummary? {
        let usable = intervals.filter { !$0.isEmpty }
        guard let first = usable.map(\.start).min(), let last = usable.map(\.end).max() else { return nil }

        let resolved = resolveOverlaps(usable)
        // Rule 3: a measure of the union, with awake removed. `inBed` is not
        // in `resolved` as an asleep stage, so it cannot inflate this.
        let asleep = resolved.filter { $0.stage.isAsleep }
        let totalSleep = asleep.reduce(0) { $0 + $1.duration }
        guard totalSleep >= minimumSessionDuration else { return nil }

        let awakeIntervals = resolved.filter { $0.stage == .awake }
        var stageDurations: [SleepStage: TimeInterval] = [:]
        for interval in resolved where interval.stage != .inBed {
            stageDurations[interval.stage, default: 0] += interval.duration
        }

        let inBed = union(usable.filter { $0.stage == .inBed }).reduce(0) { $0 + $1.duration }
        // The day the user woke up — see `SleepSessionSummary.day`.
        let day = calendar.startOfDay(for: last)

        return SleepSessionSummary(
            id: identity(start: first, end: last, origin: origin),
            day: day,
            kind: kind(start: first, end: last, totalSleep: totalSleep, calendar: calendar),
            source: origin,
            start: first,
            end: last,
            totalSleep: totalSleep,
            timeInBed: inBed > 0 ? inBed : nil,
            awake: awakeIntervals.reduce(0) { $0 + $1.duration },
            stageDurations: stageDurations,
            // Only meaningful where the source actually writes Awake
            // samples. A watch may not mark waking at the very start or end
            // of a night, so an absence of Awake is not proof of unbroken
            // sleep — which is why this stays nil rather than reporting 0.
            awakeningCount: awakeningCount(awake: awakeIntervals, within: first...last),
            intervals: resolved.filter { $0.stage != .inBed }.sorted { $0.start < $1.start },
            sourceName: source?.name,
            sourceBundleIdentifier: source?.bundleIdentifier,
            productType: source?.productType
        )
    }

    /// Stable id for the same night across re-imports. Bounds rather than a
    /// sample UUID, because HealthKit replaces samples when the watch
    /// refines a night and the summary must replace itself too.
    static func identity(start: Date, end: Date, origin: SleepSource) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return "\(origin.rawValue)|\(formatter.string(from: start))|\(formatter.string(from: end))"
    }

    // MARK: - Manual vs imported (rule 6)

    /// The rule for two records claiming the same stretch of night: **a
    /// record the user typed herself wins over one imported from Apple
    /// Health.** Health is a cache of someone else's measurement; her own
    /// entry is the record, and she usually added it precisely because the
    /// import was wrong or missing.
    ///
    /// Everything is kept — nothing is deleted and nothing disappears from
    /// the day — but the loser is marked `isSuperseded` and is never added
    /// to a total, so one night can't be reported twice (the failure this
    /// exists to prevent: 8 hours slept, 16 hours shown).
    ///
    /// Order of preference, applied greedily so the answer never depends on
    /// input order:
    /// 1. manual before imported;
    /// 2. then the earlier start;
    /// 3. then the longer sleep;
    /// 4. then the id, so two devices agree.
    ///
    /// Two records that merely touch (one ends exactly where the next
    /// begins) do not overlap and both count.
    static func resolveOverlaps(sessions: [SleepSessionSummary]) -> [SleepSessionSummary] {
        let ordered = sessions.sorted { lhs, rhs in
            if lhs.source != rhs.source { return lhs.source == .manual }
            if lhs.start != rhs.start { return lhs.start < rhs.start }
            if lhs.totalSleep != rhs.totalSleep { return lhs.totalSleep > rhs.totalSleep }
            return lhs.id < rhs.id
        }

        var kept: [SleepSessionSummary] = []
        var resolved: [String: SleepSessionSummary] = [:]
        for session in ordered {
            guard resolved[session.id] == nil else { continue }
            var copy = session
            copy.isSuperseded = false
            copy.supersededBy = nil
            if let winner = kept.first(where: { $0.start < session.end && $0.end > session.start }) {
                copy.isSuperseded = true
                copy.supersededBy = winner.source
            } else {
                kept.append(copy)
            }
            resolved[copy.id] = copy
        }
        // Back into the caller's order, so nothing else has to re-sort.
        var emitted = Set<String>()
        return sessions.compactMap { emitted.insert($0.id).inserted ? resolved[$0.id] : nil }
    }

    // MARK: - Grouping (rule 4)

    /// The stretches of wall clock that hold sleep, split wherever nothing
    /// was recorded for `sessionGap`.
    static func spans(of intervals: [SleepInterval]) -> [(start: Date, end: Date)] {
        // Grouping runs on asleep and awake alike: a night's Awake samples
        // are part of that night, and an `inBed` stretch with no stages at
        // all is still one sleep.
        let sorted = intervals.sorted { $0.start < $1.start }
        var spans: [(start: Date, end: Date)] = []
        for interval in sorted {
            if var last = spans.last, interval.start.timeIntervalSince(last.end) < sessionGap {
                last.end = max(last.end, interval.end)
                spans[spans.count - 1] = last
            } else {
                spans.append((interval.start, interval.end))
            }
        }
        return spans
    }

    // MARK: - Overlap resolution (rule 2)

    /// Every minute assigned to exactly one stage: the one with the highest
    /// `precedence` claiming it. The result is sorted, non-overlapping, and
    /// independent of the input order — so the same night always produces
    /// the same numbers.
    ///
    /// `inBed` is carried through only where nothing else covers it, and is
    /// dropped from the stage totals by the caller; it exists here purely so
    /// that a night made *only* of `inBed` still has a span.
    static func resolveOverlaps(_ intervals: [SleepInterval]) -> [SleepInterval] {
        let usable = intervals.filter { !$0.isEmpty }
        guard !usable.isEmpty else { return [] }

        // Sweep over every boundary; for each elementary slice, keep the
        // winning stage. This is O(n log n) and, unlike subtracting
        // intervals pairwise, cannot leave slivers behind.
        var boundaries = Set<Date>()
        for interval in usable {
            boundaries.insert(interval.start)
            boundaries.insert(interval.end)
        }
        let points = boundaries.sorted()
        var pieces: [SleepInterval] = []
        for (start, end) in zip(points, points.dropFirst()) {
            let covering = usable.filter { $0.start < end && $0.end > start }
            guard let winner = covering.max(by: { lhs, rhs in
                lhs.stage.precedence == rhs.stage.precedence
                    ? lhs.start < rhs.start
                    : lhs.stage.precedence < rhs.stage.precedence
            }) else { continue }
            pieces.append(SleepInterval(stage: winner.stage, start: start, end: end))
        }

        // Glue adjacent pieces of the same stage back together so the stage
        // bar draws one block per stretch rather than one per boundary.
        var merged: [SleepInterval] = []
        for piece in pieces {
            if let last = merged.last, last.stage == piece.stage, last.end == piece.start {
                merged[merged.count - 1] = SleepInterval(stage: last.stage, start: last.start, end: piece.end)
            } else {
                merged.append(piece)
            }
        }
        return merged
    }

    /// Plain union of intervals, ignoring stage — for `timeInBed`, which is
    /// a span and not a stage.
    static func union(_ intervals: [SleepInterval]) -> [SleepInterval] {
        let sorted = intervals.filter { !$0.isEmpty }.sorted { $0.start < $1.start }
        var merged: [SleepInterval] = []
        for interval in sorted {
            if let last = merged.last, interval.start <= last.end {
                merged[merged.count - 1] = SleepInterval(
                    stage: last.stage,
                    start: last.start,
                    end: max(last.end, interval.end)
                )
            } else {
                merged.append(interval)
            }
        }
        return merged
    }

    // MARK: - Classification (rule 5 and night/nap)

    /// Night or nap. Deliberately crude and deliberately documented as a
    /// heuristic: it decides which line of the diary a sleep appears on, and
    /// nothing else.
    static func kind(
        start: Date,
        end: Date,
        totalSleep: TimeInterval,
        calendar: Calendar = .current
    ) -> SleepKind {
        if totalSleep >= nightDurationThreshold { return .night }
        // A short sleep that still covers the small hours is a (bad) night,
        // not an afternoon nap.
        return overlapsSmallHours(start: start, end: end, calendar: calendar) ? .night : .nap
    }

    /// Whether any part of the sleep fell between 01:00 and 05:00 local.
    private static func overlapsSmallHours(start: Date, end: Date, calendar: Calendar) -> Bool {
        var day = calendar.startOfDay(for: start)
        let limit = calendar.startOfDay(for: end)
        while day <= limit {
            if let from = calendar.date(byAdding: .hour, value: 1, to: day),
               let to = calendar.date(byAdding: .hour, value: 5, to: day),
               start < to, end > from {
                return true
            }
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return false
    }

    /// How many times waking interrupted the sleep — awake stretches that
    /// have sleep on both sides. Nil when the source recorded no Awake
    /// samples at all, because "none recorded" is not "slept straight
    /// through": an Apple Watch may simply not mark the edges of a night.
    static func awakeningCount(awake: [SleepInterval], within range: ClosedRange<Date>) -> Int? {
        guard !awake.isEmpty else { return nil }
        return awake.filter { $0.start > range.lowerBound && $0.end < range.upperBound }.count
    }

    // MARK: - Source selection (rule 1)

    /// Which source describes a session. Preference, in order:
    /// 1. one that recorded real stages (core/deep/REM) — the detail an
    ///    Apple Watch night has and a phone's does not;
    /// 2. among those, the one covering the most time.
    ///
    /// Note what this deliberately does *not* do: match a source's **name**
    /// against "Apple Watch". That string is user-facing and localized, and
    /// HealthKit offers no public, reliable "this came from a Watch" flag —
    /// `productType` is a hint we keep and show, not something to branch on.
    /// So the app prefers the *richer data* instead, which is the property
    /// actually wanted, and stays correct whatever the device is called.
    static func preferredSource(among candidates: [SleepSourceKey: [SleepInterval]]) -> SleepSourceKey? {
        func coverage(_ intervals: [SleepInterval]) -> TimeInterval {
            union(intervals.filter { $0.stage != .inBed }).reduce(0) { $0 + $1.duration }
        }
        func hasStages(_ intervals: [SleepInterval]) -> Bool {
            intervals.contains { [.core, .deep, .rem].contains($0.stage) }
        }
        let staged = candidates.filter { hasStages($0.value) }
        let pool = staged.isEmpty ? candidates : staged
        return pool.max { lhs, rhs in
            let left = coverage(lhs.value)
            let right = coverage(rhs.value)
            // Ties broken by identifier so two devices importing the same
            // data independently still agree on the answer.
            return left == right ? lhs.key.bundleIdentifier > rhs.key.bundleIdentifier : left < right
        }?.key
    }
}

/// Identifies who wrote a set of samples. A plain value so the aggregation
/// layer stays free of HealthKit types.
struct SleepSourceKey: Hashable, Sendable {
    let bundleIdentifier: String
    let name: String
    /// e.g. "Watch6,1" — recorded and shown for transparency. Never used to
    /// decide anything; see `preferredSource`.
    let productType: String?
}
