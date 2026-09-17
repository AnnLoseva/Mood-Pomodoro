import Foundation

/// Shared analytics window. Start is inclusive, end is exclusive, and the
/// next day is always `Calendar.date(byAdding: .day)`, never +24h.
enum AnalyticsPeriodKind: String, CaseIterable, Identifiable, Sendable {
    case days7, days30, days90, year, all, custom
    var id: String { rawValue }

    var title: String {
        switch self {
        case .days7: return L("7 дней", "7 days")
        case .days30: return L("30 дней", "30 days")
        case .days90: return L("90 дней", "90 days")
        case .year: return L("1 год", "1 year")
        case .all: return L("Всё время", "All time")
        case .custom: return L("Свои даты", "Custom")
        }
    }
}

struct AnalyticsPeriod: Equatable, Sendable {
    var kind: AnalyticsPeriodKind
    var customStart: Date?
    var customEnd: Date?

    static let `default` = AnalyticsPeriod(kind: .days30)

    func interval(now: Date = .now, calendar: Calendar = .current, earliest: Date? = nil) -> DateInterval {
        let today = calendar.startOfDay(for: now)
        let endExclusive = calendar.date(byAdding: .day, value: 1, to: today) ?? today
        switch kind {
        case .days7:
            let start = calendar.date(byAdding: .day, value: -6, to: today) ?? today
            return DateInterval(start: start, end: endExclusive)
        case .days30:
            let start = calendar.date(byAdding: .day, value: -29, to: today) ?? today
            return DateInterval(start: start, end: endExclusive)
        case .days90:
            let start = calendar.date(byAdding: .day, value: -89, to: today) ?? today
            return DateInterval(start: start, end: endExclusive)
        case .year:
            let start = calendar.date(byAdding: .year, value: -1, to: today) ?? today
            return DateInterval(start: start, end: endExclusive)
        case .all:
            let start = calendar.startOfDay(for: earliest ?? today)
            return DateInterval(start: start, end: endExclusive)
        case .custom:
            let rawStart = customStart ?? today
            let rawEnd = customEnd ?? now
            let start = calendar.startOfDay(for: min(rawStart, rawEnd))
            let last = calendar.startOfDay(for: max(rawStart, rawEnd))
            let end = calendar.date(byAdding: .day, value: 1, to: last) ?? last
            return DateInterval(start: start, end: end)
        }
    }

    /// The immediately preceding window of the same *calendar* length.
    /// Seconds-based subtraction would drift across DST.
    func previousInterval(of current: DateInterval, calendar: Calendar = .current) -> DateInterval {
        let days = calendar.dateComponents([.day], from: current.start, to: current.end).day ?? 0
        let start = calendar.date(byAdding: .day, value: -days, to: current.start) ?? current.start
        return DateInterval(start: start, end: current.start)
    }

    func contains(_ date: Date, calendar: Calendar = .current) -> Bool {
        let interval = interval(calendar: calendar)
        return date >= interval.start && date < interval.end
    }
}

enum AnalyticsConfidence: String, Sendable {
    case insufficient
    case preliminary
    case descriptive

    init(independentCount: Int) {
        switch independentCount {
        case ..<5: self = .insufficient
        case 5..<14: self = .preliminary
        default: self = .descriptive
        }
    }

    var label: String {
        switch self {
        case .insufficient: return L("Недостаточно данных", "Not enough data")
        case .preliminary: return L("Предварительное наблюдение", "Preliminary observation")
        case .descriptive: return L("Описательная закономерность", "Descriptive pattern")
        }
    }

    var shortLabel: String {
        switch self {
        case .insufficient: return L("мало данных", "little data")
        case .preliminary: return L("предварительно", "preliminary")
        case .descriptive: return L("по наблюдениям", "from observations")
        }
    }

    var neededForPreliminary: Int { 5 }
}

struct AnalyticsScaleAverage: Equatable, Sendable {
    var average: Double?
    var dayCount: Int
    var observationCount: Int
    var confidence: AnalyticsConfidence
    var method: String

    static let empty = AnalyticsScaleAverage(
        average: nil,
        dayCount: 0,
        observationCount: 0,
        confidence: .insufficient,
        method: L("среднее дневных средних: каждый день с данными имеет вес 1", "mean of daily means: each day with data has weight 1")
    )
}
