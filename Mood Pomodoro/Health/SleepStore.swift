//
//  SleepStore.swift
//  Mood Pomodoro
//

import Foundation
import Observation
import SwiftData

/// Owns the device-local sleep cache and the import that fills it.
///
/// **The CloudKit rule lives here.** `LocalHealthStore` below opens a
/// *second* `ModelContainer` with `cloudKitDatabase: .none` and its own
/// file, holding `SleepRecord` and nothing else. The app's main container
/// (`PersistenceController`) is untouched, still syncs everything it always
/// did, and never learns that sleep exists — so no health data can reach
/// iCloud even by accident, which is what Apple's review guidelines require.
///
/// Because of that, views cannot reach sleep through `@Query`: that reads
/// the container in the environment, which is the CloudKit one. Sleep is
/// published from here instead, as plain value types, and the UI never sees
/// a `SleepRecord`.
@MainActor
@Observable
final class SleepStore {
    /// How far back the first import reads. A month is enough to make the
    /// diary and the month screen useful without pulling years of history
    /// the user never asked us to hold. Widening it is a one-line change;
    /// nothing else assumes this number.
    static let initialImportDays = 30

    private let container: ModelContainer
    private let context: ModelContext
    private let health = HealthKitSleepService()

    /// Every cached session, newest first. The one thing the UI reads.
    private(set) var sessions: [SleepSessionSummary] = []
    /// Cycle days from Health, as marks the diary can count alongside the
    /// user's own `CycleEntry` records.
    private(set) var cycleMarks: [CycleMark] = []
    /// Medication days from Health, keyed by day.
    private(set) var medicationDays: [Date: HealthMedicationDay] = [:]
    private(set) var isImporting = false
    /// When the last successful read from HealthKit finished.
    private(set) var lastImportedAt: Date?

    /// The user's own switch. Nothing touches HealthKit until this is on,
    /// so the Health sheet never appears out of nowhere at first launch.
    var isHealthKitEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: Self.enabledKey) }
        set {
            UserDefaults.standard.set(newValue, forKey: Self.enabledKey)
            if !newValue { removeImportedSessions() }
        }
    }

    private static let enabledKey = "health.sleep.enabled"

    var isHealthKitAvailable: Bool { HealthKitSleepService.isAvailable }
    var hasAskedForPermission: Bool { health.hasRequestedAuthorization }

    init(container: ModelContainer = LocalHealthStore.container) {
        self.container = container
        self.context = container.mainContext
        reload()
    }

    // MARK: - Reading

    func reload() {
        let descriptor = FetchDescriptor<SleepRecord>(sortBy: [SortDescriptor(\.startDate, order: .reverse)])
        // Overlaps are resolved once, here, so every reader — the day card,
        // the month, the overall chart, analytics — sees the same
        // non-double-counted answer. See `resolveOverlaps(sessions:)`.
        sessions = SleepAggregationService.resolveOverlaps(
            sessions: ((try? context.fetch(descriptor)) ?? []).map(\.summary)
        )

        let cycle = FetchDescriptor<HealthCycleDay>(sortBy: [SortDescriptor(\.day)])
        cycleMarks = ((try? context.fetch(cycle)) ?? []).compactMap(\.mark)

        let medication = FetchDescriptor<HealthMedicationDay>(sortBy: [SortDescriptor(\.day)])
        medicationDays = Dictionary(
            ((try? context.fetch(medication)) ?? []).map { ($0.day, $0) },
            uniquingKeysWith: { _, newest in newest }
        )
    }

    /// Health's medication answer for a day, if it has one. The caller
    /// decides what to do with it — the user's own `SupportEntry` always
    /// wins where she marked the day herself.
    func medicationDay(for date: Date, calendar: Calendar = .current) -> HealthMedicationDay? {
        medicationDays[calendar.startOfDay(for: date)]
    }

    var isMedicationAvailable: Bool { HealthKitSleepService.isMedicationAvailable }

    /// One day's sleep, filed by the day the user woke up.
    func daySummary(for date: Date, calendar: Calendar = .current) -> SleepDaySummary {
        let day = calendar.startOfDay(for: date)
        let matching = sessions
            .filter { calendar.isDate($0.day, inSameDayAs: day) }
            .sorted { $0.start < $1.start }
        return SleepDaySummary(day: day, sessions: matching)
    }

    func sessions(in interval: DateInterval) -> [SleepSessionSummary] {
        sessions.filter { interval.contains($0.day) }.sorted { $0.start < $1.start }
    }

    // MARK: - Import

    /// Turns the integration on: asks for access, reads the initial window,
    /// then starts watching for changes.
    func connectHealthKit() async {
        guard isHealthKitAvailable else { return }
        do {
            try await health.requestAuthorization()
        } catch {
            // A refusal is a normal answer, not an error state to shout
            // about. The empty state already says what to do.
            return
        }
        isHealthKitEnabled = true
        await importInitialHistory()
        startObserving()
    }

    /// True when the app now reads something Health never asked the user
    /// about — e.g. she connected when only sleep was read, and cycle and
    /// medication came later. The card offers to ask rather than silently
    /// returning nothing.
    var needsAdditionalPermission: Bool { isHealthKitEnabled && health.hasUnaskedTypes }

    /// What the "Обновить" button does: asks about anything new first, so a
    /// refresh can never quietly do nothing because a type was never
    /// authorized. Only ever reached from a tap, never at launch.
    func refreshRequestingAccessIfNeeded() async {
        if needsAdditionalPermission {
            try? await health.requestAuthorization()
        }
        await refresh()
    }

    /// Full read of the recent window. Used on connect and whenever the
    /// cache has to be rebuilt from the source of truth.
    func importInitialHistory() async {
        guard isHealthKitEnabled, isHealthKitAvailable, !isImporting else { return }
        isImporting = true
        defer { isImporting = false }

        let end = Date.now
        guard let start = Calendar.current.date(byAdding: .day, value: -Self.initialImportDays, to: end) else { return }
        do {
            let interval = DateInterval(start: start, end: end)
            let grouped = try await health.samples(in: interval)
            let summaries = SleepAggregationService.sessions(from: grouped)
            replaceImported(with: summaries, from: start)
            await importDayRecords(in: interval)
            // Everything up to now is accounted for; the next incremental
            // read should return only what arrives after this point.
            try? await health.primeAnchor()
            lastImportedAt = .now
        } catch {
            return
        }
    }

    /// Cycle and medication for a window. Both are whole-day records with no
    /// grouping to do, so the window is simply re-read and replaced — which
    /// also means a day deleted in Health disappears here.
    private func importDayRecords(in interval: DateInterval, calendar: Calendar = .current) async {
        if let days = try? await health.cycleDays(in: interval, calendar: calendar) {
            replace(HealthCycleDay.self, in: interval, with: days) { $0.day }
        }
        if let days = try? await health.medicationDays(in: interval, calendar: calendar) {
            replace(HealthMedicationDay.self, in: interval, with: days) { $0.day }
        }
        save()
    }

    /// Swaps a window's worth of cached day records for what Health now
    /// says. Safe because these are caches, not records.
    private func replace<Model: PersistentModel>(
        _ type: Model.Type,
        in interval: DateInterval,
        with fresh: [Model],
        day: (Model) -> Date
    ) {
        let existing = (try? context.fetch(FetchDescriptor<Model>())) ?? []
        for record in existing where interval.contains(day(record)) {
            context.delete(record)
        }
        for record in fresh { context.insert(record) }
    }

    /// The cheap path, for a foreground return or a background nudge: ask
    /// what changed, and re-read only the days it touched.
    ///
    /// A change is a *signal*, never data — HealthKit tells us something
    /// moved, and we then go and read the affected days properly, because a
    /// changed sample may belong to a night whose other samples did not
    /// change at all.
    func refresh() async {
        guard isHealthKitEnabled, isHealthKitAvailable, !isImporting else { return }
        // Cycle and medication are whole-day records with no anchor of their
        // own, so they are re-read every time rather than gated on the sleep
        // anchor: a day logged only in Cycle Tracking produces no sleep
        // change at all, and gating this on one would never import it.
        await importRecentDayRecords()
        do {
            guard let changes = try await health.changes() else {
                // No anchor yet — nothing has been imported on this device.
                await importInitialHistory()
                return
            }
            guard !changes.isEmpty else {
                lastImportedAt = .now
                return
            }
            // Deletions carry no dates, so any deletion means the safest
            // thing is to rebuild the window rather than guess which night
            // vanished.
            guard changes.deletedCount == 0 else {
                await rebuild()
                return
            }
            await reimport(daysTouchedBy: changes.added)
            lastImportedAt = .now
        } catch {
            return
        }
    }

    /// Re-reads cycle and medication over the recent window. Cheap: two
    /// whole-day queries with no grouping, and the window is replaced
    /// wholesale so a day deleted in Health disappears here too.
    private func importRecentDayRecords() async {
        let end = Date.now
        guard let start = Calendar.current.date(byAdding: .day, value: -Self.initialImportDays, to: end) else { return }
        await importDayRecords(in: DateInterval(start: start, end: end))
    }

    /// Throws the cache away and reads it again from HealthKit. Safe by
    /// definition — nothing here is a record, only a copy.
    func rebuild() async {
        health.resetAnchor()
        await importInitialHistory()
    }

    /// Re-reads whole days around whatever changed. Reading the day rather
    /// than the sample is what keeps a refined night one session instead of
    /// two: the aggregation needs all of that night's samples, not just the
    /// one that moved.
    private func reimport(daysTouchedBy added: [SleepSourceKey: [SleepInterval]]) async {
        let touched = added.values.flatMap { $0 }
        guard let earliest = touched.map(\.start).min(), let latest = touched.map(\.end).max() else { return }
        let calendar = Calendar.current
        // A night starts the evening before the day it belongs to, so the
        // window is widened by a day on each side before re-reading.
        guard let from = calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: earliest)),
              let to = calendar.date(byAdding: .day, value: 2, to: calendar.startOfDay(for: latest))
        else { return }

        isImporting = true
        defer { isImporting = false }
        do {
            let grouped = try await health.samples(in: DateInterval(start: from, end: to))
            let summaries = SleepAggregationService.sessions(from: grouped)
            replaceImported(with: summaries, from: from, to: to)
        } catch {
            return
        }
    }

    // MARK: - Cache writes

    /// Replaces the imported rows in a window with what HealthKit now says.
    /// Manual entries are never touched: they are the user's own data, not a
    /// cache of anyone else's.
    func replaceImported(with summaries: [SleepSessionSummary], from: Date, to: Date = .distantFuture) {
        let existing = importedRecords().filter { $0.startDate >= from && $0.startDate < to }
        var byKey = Dictionary(existing.map { ($0.deterministicKey, $0) }, uniquingKeysWith: { first, _ in first })

        var importedKeys = Set<String>()
        for summary in summaries where importedKeys.insert(summary.id).inserted {
            if let record = byKey.removeValue(forKey: summary.id) {
                record.apply(summary)
            } else {
                let record = SleepRecord(summary: summary)
                // A watch that refines a night shifts its bounds, which
                // changes its key — the same night arrives as a "new" one.
                // Carry the user's own answers over to it rather than
                // losing a rating to a background refresh.
                if let previous = byKey.values.first(where: {
                    $0.startDate < summary.end && $0.endDate > summary.start
                }) {
                    record.qualityRaw = previous.qualityRaw
                    record.note = previous.note
                }
                context.insert(record)
            }
        }
        // Whatever HealthKit no longer reports in this window is gone from
        // the source of truth, so it goes from the cache too.
        for orphan in byKey.values { context.delete(orphan) }
        save()
    }

    private func importedRecords() -> [SleepRecord] {
        let raw = SleepSource.healthKit.rawValue
        let descriptor = FetchDescriptor<SleepRecord>(predicate: #Predicate { $0.sourceRaw == raw })
        return (try? context.fetch(descriptor)) ?? []
    }

    /// Turning the integration off removes what came from Health, and only
    /// that — anything typed by hand stays.
    private func removeImportedSessions() {
        for record in importedRecords() { context.delete(record) }
        for record in (try? context.fetch(FetchDescriptor<HealthCycleDay>())) ?? [] { context.delete(record) }
        for record in (try? context.fetch(FetchDescriptor<HealthMedicationDay>())) ?? [] { context.delete(record) }
        health.resetAnchor()
        save()
    }

    // MARK: - Manual entries

    /// A night the watch missed. Stored locally like everything else here,
    /// and deliberately **not** written back into HealthKit: this
    /// integration is read-only, and the app has no business putting its own
    /// estimate into the user's health record.
    @discardableResult
    func addManualSleep(
        start: Date,
        end: Date,
        kind: SleepKind? = nil,
        quality: SleepQuality? = nil,
        note: String? = nil,
        calendar: Calendar = .current
    ) -> SleepSessionSummary? {
        guard end > start else { return nil }
        let interval = SleepInterval(stage: .unspecified, start: start, end: end)
        guard var summary = SleepAggregationService.summary(
            of: [interval],
            origin: .manual,
            calendar: calendar
        ) else { return nil }
        if let kind, kind != summary.kind {
            summary = summary.with(kind: kind)
        }
        let record = manualRecord(key: summary.id) ?? SleepRecord(summary: summary, note: note)
        record.apply(summary)
        record.note = note
        record.quality = quality
        if record.modelContext == nil { context.insert(record) }
        save()
        return summary
    }

    func updateManualSleep(
        id: String,
        start: Date,
        end: Date,
        kind: SleepKind? = nil,
        quality: SleepQuality? = nil,
        note: String?,
        calendar: Calendar = .current
    ) {
        guard end > start, let record = manualRecord(key: id) else { return }
        let interval = SleepInterval(stage: .unspecified, start: start, end: end)
        guard var summary = SleepAggregationService.summary(
            of: [interval],
            origin: .manual,
            calendar: calendar
        ) else { return }
        if let kind, kind != summary.kind {
            summary = summary.with(kind: kind)
        }
        record.apply(summary)
        record.quality = quality
        record.note = note
        save()
    }

    /// The subjective rating, which belongs to *any* night — including one
    /// Apple Health recorded. It is stored beside the imported numbers and
    /// never mixed into them, and a re-import keeps it (see
    /// `SleepRecord.apply` and `replaceImported`).
    func setQuality(_ quality: SleepQuality?, forSleepID id: String) {
        guard let record = record(key: id) else { return }
        record.quality = quality
        record.updatedAt = .now
        save()
    }

    func deleteSleep(id: String) {
        guard let record = record(key: id) else { return }
        context.delete(record)
        save()
    }

    func manualRecord(key: String) -> SleepRecord? {
        record(key: key).flatMap { $0.source == .manual ? $0 : nil }
    }

    private func record(key: String) -> SleepRecord? {
        let descriptor = FetchDescriptor<SleepRecord>(predicate: #Predicate { $0.deterministicKey == key })
        return (try? context.fetch(descriptor)).flatMap(\.first)
    }

    /// Whether HealthKit already describes sleep overlapping this stretch —
    /// so a manual entry can warn instead of quietly making one night into
    /// sixteen hours.
    func importedSleepOverlaps(start: Date, end: Date, ignoring id: String? = nil) -> SleepSessionSummary? {
        sessions.first { session in
            session.source == .healthKit && session.id != id && session.start < end && session.end > start
        }
    }

    // MARK: - Observation

    /// Starts listening for HealthKit changes. The handler only schedules a
    /// refresh; the data itself is always read back from HealthKit.
    func startObserving() {
        guard isHealthKitEnabled, isHealthKitAvailable else { return }
        health.startObserving { [weak self] in
            Task { @MainActor in await self?.refresh() }
        }
    }

    private func save() {
        try? context.save()
        reload()
    }
}

extension SleepSessionSummary {
    /// Only the night/nap call is ever overridden, and only by the user on
    /// her own manual entry — the automatic heuristic is a guess about
    /// presentation, and she is allowed to disagree with it.
    func with(kind: SleepKind) -> SleepSessionSummary {
        SleepSessionSummary(
            id: id,
            day: day,
            kind: kind,
            source: source,
            start: start,
            end: end,
            totalSleep: totalSleep,
            timeInBed: timeInBed,
            awake: awake,
            stageDurations: stageDurations,
            awakeningCount: awakeningCount,
            intervals: intervals,
            sourceName: sourceName,
            sourceBundleIdentifier: sourceBundleIdentifier,
            productType: productType,
            quality: quality,
            isSuperseded: isSuperseded,
            supersededBy: supersededBy,
            note: note
        )
    }
}

/// The second, **local-only** SwiftData container.
///
/// Separate from `PersistenceController` on purpose and by requirement:
/// * `cloudKitDatabase: .none` — health data must not go to iCloud;
/// * its own store file, so it can never be swept into the CloudKit
///   container's schema by someone adding a model in the wrong place;
/// * in-memory under tests, like the rest of the app.
///
/// If this ever fails to open, sleep degrades to "unavailable" rather than
/// taking the app down — it is a cache of data that still exists in Health.
enum LocalHealthStore {
    static let schema = Schema([SleepRecord.self, HealthCycleDay.self, HealthMedicationDay.self])

    static let container: ModelContainer = {
        let runningTests = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
        let configuration = ModelConfiguration(
            "LocalHealth",
            schema: schema,
            isStoredInMemoryOnly: runningTests || ProcessInfo.processInfo.environment["MOOD_UI_TESTING"] == "1",
            // Explicit, not defaulted: omitting this would mean `.automatic`,
            // which is exactly the mistake this container exists to prevent.
            cloudKitDatabase: .none
        )
        if let container = try? ModelContainer(for: schema, configurations: [configuration]) {
            return container
        }
        let fallback = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        // Force-try is confined to an in-memory store of one model, which
        // cannot fail for the reasons a file-backed one can.
        return try! ModelContainer(for: schema, configurations: [fallback])
    }()
}
