//
//  HealthKitSleepService.swift
//  Mood Pomodoro
//

import Foundation
import HealthKit

/// The only file in the app that knows HealthKit exists. Reads sleep, and
/// nothing else, and only ever reads: the app requests no share (write)
/// authorization and never puts a sample back into Health.
///
/// HealthKit is the source of truth. Everything the app keeps is a cache
/// that can be thrown away and rebuilt — see `SleepStore` — so a night the
/// watch refines later, or one the user deletes in Health, ends up
/// reflected here rather than frozen in our own copy.
///
/// Two platform limits worth stating plainly, because the UI is built
/// around them rather than around wishes:
/// * **Read authorization is deliberately opaque.** `authorizationStatus`
///   reports whether we have *asked*, never whether we were granted — Apple
///   hides that so an app cannot infer a diagnosis from a refusal. So "no
///   samples" can mean no permission, no watch, or no sleep, and the app
///   must never phrase it as "you didn't sleep".
/// * **Background delivery is a hint, not a schedule.** iOS decides when to
///   wake the app, and for a daily-frequency type that may be hours after
///   the watch syncs. So the app also refreshes when it comes to the
///   foreground, and neither path is treated as the only one.
@MainActor
final class HealthKitSleepService {
    private let store = HKHealthStore()

    private var sleepType: HKCategoryType { HKCategoryType(.sleepAnalysis) }
    private var menstrualFlowType: HKCategoryType { HKCategoryType(.menstrualFlow) }

    /// Medication logging only became readable by third-party apps in
    /// iOS 26. The project deploys to 17, so everything about medication is
    /// gated and simply absent on older systems — never faked from
    /// something else.
    @available(iOS 26.0, *)
    private var medicationType: HKSampleType { HKObjectType.medicationDoseEventType() }

    /// Medication is not asked for like sleep. Putting the dose-event type in
    /// `requestAuthorization(read:)` is what raises the uncaught
    /// `NSInvalidArgumentException` ("Authorization to read the following
    /// types is disallowed") — that type is never in this set. Medication
    /// goes through per-object authorization instead, see
    /// `requestMedicationAuthorization()`: Health shows the user her own
    /// medications and she picks which ones this app may read.
    ///
    /// Everything the ordinary sheet asks for, and nothing more. Cycle is
    /// here because the diary already tracks it by hand; Health simply fills
    /// in the days the user didn't mark herself.
    private var readTypes: Set<HKObjectType> {
        [sleepType, menstrualFlowType]
    }

    /// Set once the user has been through the medication sheet. Health hides
    /// what was granted, so this only says the question was put to her.
    private static let medicationAskedKey = "health.medication.asked"

    /// Where the incremental query left off, so a launch reads what changed
    /// rather than the whole history again. Anchors are per-device and
    /// meaningless anywhere else, so this belongs in `UserDefaults` and must
    /// never travel to another device.
    private static let anchorKey = "health.sleep.anchor"

    static var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    /// True once the user has been through the Health sheet for sleep. Not
    /// the same as "granted" — HealthKit will not tell us that for a read
    /// type, by design.
    var hasRequestedAuthorization: Bool {
        guard Self.isAvailable else { return false }
        return store.authorizationStatus(for: sleepType) != .notDetermined
    }

    /// Asks for read access to sleep, cycle and medication — and nothing
    /// else. Called when the user turns the integration on, never at first
    /// launch, where a Health sheet out of nowhere is just alarming.
    ///
    /// One sheet for all three because they are one feature to the user
    /// ("подключить Apple Health"), and because Health lets her refuse any
    /// of them individually right there.
    func requestAuthorization() async throws {
        guard Self.isAvailable else { throw HealthKitSleepError.unavailable }
        try await store.requestAuthorization(toShare: [], read: readTypes)
    }

    /// True once the user has been through the Health sheet at all. As with
    /// sleep, this says nothing about what was *granted* — HealthKit hides
    /// that for read types by design.
    var hasRequestedAnything: Bool {
        guard Self.isAvailable else { return false }
        return readTypes.contains { store.authorizationStatus(for: $0) != .notDetermined }
    }

    /// True when some type we now read has never been put in front of the
    /// user — which is what happens when the app starts reading something it
    /// didn't before, and someone who connected Health last month has only
    /// ever been asked about sleep. Asking again shows a sheet listing only
    /// the new types; the ones already answered are not re-asked.
    var hasUnaskedTypes: Bool {
        guard Self.isAvailable else { return false }
        return readTypes.contains { store.authorizationStatus(for: $0) == .notDetermined }
    }

    // MARK: - Reading

    /// Every sleep sample overlapping `interval`, keyed by what wrote it.
    ///
    /// The predicate is `strictStartDate: false` on purpose: a night that
    /// began before the window still belongs to the morning inside it.
    func samples(in interval: DateInterval) async throws -> [SleepSourceKey: [SleepInterval]] {
        guard Self.isAvailable else { throw HealthKitSleepError.unavailable }
        let predicate = HKQuery.predicateForSamples(
            withStart: interval.start,
            end: interval.end,
            options: []
        )
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.categorySample(type: sleepType, predicate: predicate)],
            sortDescriptors: [SortDescriptor(\.startDate)]
        )
        return Self.group(try await descriptor.result(for: store))
    }

    /// What changed since the last read, plus the ids of samples that were
    /// deleted. Both matter: a night the user removed in Health has to
    /// disappear here too.
    ///
    /// Returns nil when there is no stored anchor yet — the caller should do
    /// a full read of its chosen window instead.
    func changes() async throws -> SleepChangeSet? {
        guard Self.isAvailable else { throw HealthKitSleepError.unavailable }
        guard let anchor = loadAnchor() else { return nil }
        let descriptor = HKAnchoredObjectQueryDescriptor(
            predicates: [.categorySample(type: sleepType)],
            anchor: anchor
        )
        let result = try await descriptor.result(for: store)
        save(anchor: result.newAnchor)
        return SleepChangeSet(
            added: Self.group(result.addedSamples),
            deletedCount: result.deletedObjects.count
        )
    }

    /// Establishes the anchor without pulling history through it, so the
    /// first incremental read after an import returns only what is new.
    func primeAnchor() async throws {
        guard Self.isAvailable else { return }
        let descriptor = HKAnchoredObjectQueryDescriptor(
            predicates: [.categorySample(type: sleepType)],
            anchor: nil
        )
        let result = try await descriptor.result(for: store)
        save(anchor: result.newAnchor)
    }

    // MARK: - Cycle

    /// Cycle days from Health, collapsed to one record per calendar day.
    ///
    /// Health stores the cycle-start flag as required metadata on these
    /// samples, so day 1 comes from Health itself rather than from the app
    /// guessing where a cycle began.
    func cycleDays(in interval: DateInterval, calendar: Calendar = .current) async throws -> [HealthCycleDay] {
        guard Self.isAvailable else { throw HealthKitSleepError.unavailable }
        let predicate = HKQuery.predicateForSamples(withStart: interval.start, end: interval.end, options: [])
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.categorySample(type: menstrualFlowType, predicate: predicate)],
            sortDescriptors: [SortDescriptor(\.startDate)]
        )
        var byDay: [Date: HealthCycleDay] = [:]
        for sample in try await descriptor.result(for: store) {
            let day = calendar.startOfDay(for: sample.startDate)
            // Raw values are read directly rather than through
            // `HKCategoryValueVaginalBleeding`, which is iOS 18+: the numbers
            // are unchanged from the older `HKCategoryValueMenstrualFlow`, so
            // this reads both without an availability gate.
            let flow = MenstrualFlow(rawValue: sample.value) ?? .unspecified
            let isStart = (sample.metadata?[HKMetadataKeyMenstrualCycleStart] as? Bool) ?? false
            if let existing = byDay[day] {
                // Several samples for one day: bleeding wins over "none",
                // and a start flag anywhere in the day marks the day.
                if flow.isBleeding, !existing.flow.isBleeding { existing.flow = flow }
                if isStart { existing.isCycleStart = true }
            } else {
                byDay[day] = HealthCycleDay(
                    day: day,
                    flow: flow,
                    isCycleStart: isStart,
                    sourceName: sample.sourceRevision.source.name,
                    calendar: calendar
                )
            }
        }
        return byDay.values.sorted { $0.day < $1.day }
    }

    // MARK: - Medication

    /// Whether this system can report medication logging at all. False below
    /// iOS 26, where the API simply does not exist — the UI says so rather
    /// than pretending the user never took anything.
    static var isMedicationAvailable: Bool {
        if #available(iOS 26.0, *) { return isAvailable }
        return false
    }

    var hasRequestedMedicationAccess: Bool {
        UserDefaults.standard.bool(forKey: Self.medicationAskedKey)
    }

    /// Asks Health which of the user's medications this app may read. The
    /// system shows the sheet every time it is called, so this is only ever
    /// reached from a tap (connect, or "Обновить") and once until answered —
    /// never at launch.
    func requestMedicationAuthorization() async {
        guard Self.isMedicationAvailable, #available(iOS 26.0, *) else { return }
        do {
            try await store.requestPerObjectReadAuthorization(for: HKObjectType.userAnnotatedMedicationType(), predicate: nil)
            UserDefaults.standard.set(true, forKey: Self.medicationAskedKey)
        } catch {
            // Dismissing the sheet is an answer too; she is asked again on
            // the next "Обновить".
            return
        }
    }

    /// Medication dose events from Health, collapsed to one record per day.
    ///
    /// Only *logged* statuses are counted. An untouched reminder
    /// (`notInteracted`), an undelivered notification, or a snooze says
    /// nothing about whether anything was taken, and is deliberately not
    /// read as a skip.
    func medicationDays(in interval: DateInterval, calendar: Calendar = .current) async throws -> [HealthMedicationDay] {
        guard Self.isMedicationAvailable, #available(iOS 26.0, *) else { return [] }
        let predicate = HKQuery.predicateForSamples(withStart: interval.start, end: interval.end, options: [])
        // HealthKit offers no typed `HKSamplePredicate` factory for dose
        // events, so this goes through the generic sample query and casts.
        // The cast is what keeps it honest: anything that is not a dose
        // event is skipped rather than guessed at.
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.sample(type: medicationType, predicate: predicate)],
            sortDescriptors: [SortDescriptor(\.startDate)]
        )
        var taken: [Date: Int] = [:]
        var skipped: [Date: Int] = [:]
        var names: [Date: String] = [:]
        for sample in try await descriptor.result(for: store) {
            guard let event = sample as? HKMedicationDoseEvent else { continue }
            let day = calendar.startOfDay(for: event.startDate)
            switch event.logStatus {
            case .taken:
                taken[day, default: 0] += 1
            case .skipped:
                skipped[day, default: 0] += 1
            default:
                // notInteracted / notificationNotSent / snoozed / notLogged
                // are not answers. Skip them rather than inventing one.
                continue
            }
            names[day] = event.sourceRevision.source.name
        }
        return Set(taken.keys).union(skipped.keys).sorted().map { day in
            HealthMedicationDay(
                day: day,
                takenCount: taken[day] ?? 0,
                skippedCount: skipped[day] ?? 0,
                sourceName: names[day],
                calendar: calendar
            )
        }
    }

    // MARK: - Observation

    /// Asks iOS to wake the app when sleep data changes. `onChange` fires on
    /// the main actor; it is a *signal only* — the handler must go and read
    /// the data, because the notification carries none.
    func startObserving(onChange: @escaping @Sendable () -> Void) {
        guard Self.isAvailable else { return }
        for type in [sleepType, menstrualFlowType] {
            let query = HKObserverQuery(sampleType: type, predicate: nil) { _, completionHandler, _ in
                onChange()
                // Must be called whatever happened, or iOS backs off and
                // eventually stops delivering.
                completionHandler()
            }
            store.execute(query)
            // These are daily-frequency types: iOS will not deliver more
            // often than once a day however small a frequency is asked for.
            store.enableBackgroundDelivery(for: type, frequency: .daily) { _, _ in }
        }
    }

    // MARK: - Anchor storage

    private func loadAnchor() -> HKQueryAnchor? {
        guard let data = UserDefaults.standard.data(forKey: Self.anchorKey) else { return nil }
        return try? NSKeyedUnarchiver.unarchivedObject(ofClass: HKQueryAnchor.self, from: data)
    }

    private func save(anchor: HKQueryAnchor) {
        guard let data = try? NSKeyedArchiver.archivedData(withRootObject: anchor, requiringSecureCoding: true) else { return }
        UserDefaults.standard.set(data, forKey: Self.anchorKey)
    }

    /// Forgets where we left off, so the next import rebuilds from scratch.
    func resetAnchor() {
        UserDefaults.standard.removeObject(forKey: Self.anchorKey)
    }

    // MARK: - Mapping

    /// HealthKit samples → our value types, grouped by source.
    ///
    /// Samples are kept apart by source rather than merged, because two apps
    /// describing the same night must not be added together — see
    /// `SleepAggregationService.preferredSource`.
    private static func group(_ samples: [HKCategorySample]) -> [SleepSourceKey: [SleepInterval]] {
        var grouped: [SleepSourceKey: [SleepInterval]] = [:]
        for sample in samples {
            guard let stage = stage(for: sample) else { continue }
            let revision = sample.sourceRevision
            let key = SleepSourceKey(
                bundleIdentifier: revision.source.bundleIdentifier,
                name: revision.source.name,
                productType: revision.productType ?? sample.device?.model
            )
            grouped[key, default: []].append(
                SleepInterval(stage: stage, start: sample.startDate, end: sample.endDate)
            )
        }
        return grouped
    }

    private static func stage(for sample: HKCategorySample) -> SleepStage? {
        switch HKCategoryValueSleepAnalysis(rawValue: sample.value) {
        case .inBed: return .inBed
        case .awake: return .awake
        case .asleepREM: return .rem
        case .asleepCore: return .core
        case .asleepDeep: return .deep
        case .asleepUnspecified: return .unspecified
        // `.asleep` is the pre-iOS-16 value and is what an iPhone, or an
        // older watchOS, still writes. It means "asleep, no detail".
        default: return HKCategoryValueSleepAnalysis(rawValue: sample.value) == nil ? nil : .unspecified
        }
    }
}

struct SleepChangeSet: Sendable {
    let added: [SleepSourceKey: [SleepInterval]]
    let deletedCount: Int

    var isEmpty: Bool { added.isEmpty && deletedCount == 0 }
}

enum HealthKitSleepError: Error {
    case unavailable
}
