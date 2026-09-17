import Foundation
import Observation

@MainActor
@Observable
final class AnalyticsStore {
    var period: AnalyticsPeriod {
        didSet { persist(); scheduleRebuild() }
    }
    var snapshot: AnalyticsSnapshot = .empty
    var isRefreshing = false
    var errorMessage: String?
    var facts = AnalyticsFacts(
        checkIns: [], sessions: [], conditionEvents: [], hunger: [], food: [], emotions: [], impulses: [],
        support: [], cycle: [], sleep: [], categories: [], healthMedication: [:]
    )

    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var calendar = Calendar.current

    init() {
        if let raw = UserDefaults.standard.string(forKey: "analytics.period.kind"),
           let kind = AnalyticsPeriodKind(rawValue: raw) {
            var stored = AnalyticsPeriod(kind: kind)
            if kind == .custom {
                stored.customStart = UserDefaults.standard.object(forKey: "analytics.period.start") as? Date
                stored.customEnd = UserDefaults.standard.object(forKey: "analytics.period.end") as? Date
            }
            period = stored
        } else {
            period = .default
        }
    }

    func ingest(_ facts: AnalyticsFacts, calendar: Calendar = .current) {
        self.facts = facts
        self.calendar = calendar
        scheduleRebuild()
    }

    func scheduleRebuild() {
        generation += 1
        let token = generation
        let facts = facts
        let period = period
        let calendar = calendar
        isRefreshing = true
        errorMessage = nil
        Task.detached(priority: .userInitiated) {
            let now = Date.now
            let interval = period.interval(now: now, calendar: calendar, earliest: facts.earliest)
            let previous = period.kind == .all ? nil : period.previousInterval(of: interval, calendar: calendar)
            let built = AnalyticsEngine.build(facts: facts, interval: interval, previous: previous, calendar: calendar, now: now)
            await MainActor.run {
                guard AnalyticsEngine.shouldPublish(token: token, generation: self.generation) else { return }
                self.snapshot = built
                self.isRefreshing = false
            }
        }
    }

    private func persist() {
        UserDefaults.standard.set(period.kind.rawValue, forKey: "analytics.period.kind")
        UserDefaults.standard.set(period.customStart, forKey: "analytics.period.start")
        UserDefaults.standard.set(period.customEnd, forKey: "analytics.period.end")
    }
}
