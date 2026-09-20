//
//  AnalyticsSearch.swift
//  Mood Pomodoro
//
//  Fast local search over what the app already knows: the metrics, the
//  analytics sections, the factor and activity names of the chosen period,
//  a typed date, and — bounded by a fetch limit, never "load everything" —
//  the sessions themselves. No index to build or keep in sync, no ranking
//  model: at this size a scan of a few dozen entries per keystroke is free.
//

import Foundation
import SwiftData

struct AnalyticsSearchEntry: Identifiable, Hashable, Sendable {
    enum Kind: Sendable { case section, metric, activity, factor }

    let id: String
    let kind: Kind
    let title: String
    let subtitle: String?
    let symbol: String
    let route: AnalyticsRoute
    let keywords: [String]
}

enum AnalyticsSearch {
    // MARK: - Entries

    /// Sections and metrics: always searchable, whatever the period holds.
    static func staticEntries() -> [AnalyticsSearchEntry] {
        var out: [AnalyticsSearchEntry] = []
        for section in AnalyticsSection.allCases {
            out.append(AnalyticsSearchEntry(
                id: "section-\(section.rawValue)", kind: .section, title: section.title, subtitle: nil,
                symbol: section.symbol, route: .section(section), keywords: section.keywords
            ))
        }
        for metric in AnalyticsMetric.allCases {
            out.append(AnalyticsSearchEntry(
                id: "metric-\(metric.rawValue)", kind: .metric, title: metric.title, subtitle: metric.unitNote,
                symbol: metric.shape.symbolName(filled: true), route: .metric(metric),
                keywords: metricKeywords(metric)
            ))
        }
        out.append(AnalyticsSearchEntry(
            id: "sessions", kind: .section, title: L("Все сессии", "All sessions"), subtitle: nil,
            symbol: "clock.arrow.circlepath", route: .sessions(activity: nil),
            keywords: ["история", "сессия", "занятие", "history", "session"]
        ))
        return out
    }

    private static func metricKeywords(_ metric: AnalyticsMetric) -> [String] {
        switch metric {
        case .mood: return ["mood", "чувствую"]
        case .energy: return ["силы", "energy"]
        case .motivation: return ["motivation"]
        case .satiety: return ["голод", "hunger", "насыщение", "satiety"]
        case .appetite: return ["appetite"]
        case .sleep: return ["ночь", "sleep", "сон"]
        case .activity: return ["занятия", "сессии", "activities", "focus"]
        case .rest: return ["rest", "отдых"]
        case .work: return ["работа", "work"]
        case .study: return ["учёба", "study", "учеба"]
        }
    }

    /// Names that exist in the chosen period's snapshot.
    static func dynamicEntries(activities: [String], factors: [(name: String, category: UUID, categoryName: String)]) -> [AnalyticsSearchEntry] {
        var out: [AnalyticsSearchEntry] = []
        var seen = Set<String>()
        for name in activities {
            let canonical = canonicalData(name)
            guard seen.insert("a-\(canonical)").inserted else { continue }
            out.append(AnalyticsSearchEntry(
                id: "activity-\(canonical)", kind: .activity, title: Ldata(canonical), subtitle: L("занятие", "activity"),
                symbol: "leaf", route: .activity(canonical), keywords: [canonical]
            ))
        }
        for factor in factors {
            guard seen.insert("f-\(factor.category)-\(factor.name)").inserted else { continue }
            out.append(AnalyticsSearchEntry(
                id: "factor-\(factor.category)-\(factor.name)", kind: .factor, title: Ldata(factor.name),
                subtitle: Ldata(factor.categoryName), symbol: "cup.and.saucer",
                route: .factorCategory(factor.category), keywords: [factor.name, factor.categoryName]
            ))
        }
        return out
    }

    // MARK: - Matching

    /// Lower-case, no diacritics, "ё" written as "е" — so "учёба" finds "учеба".
    static func normalize(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .replacingOccurrences(of: "ё", with: "е")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Entries whose title or keywords contain every word of `query`, best
    /// first: a title that starts with the query, then one that contains it,
    /// then a keyword hit. Stable for equal ranks.
    static func match(_ query: String, in entries: [AnalyticsSearchEntry], limit: Int = 12) -> [AnalyticsSearchEntry] {
        let q = normalize(query)
        guard !q.isEmpty else { return [] }
        let words = q.split(separator: " ").map(String.init)

        var scored: [(entry: AnalyticsSearchEntry, rank: Int, order: Int)] = []
        for (order, entry) in entries.enumerated() {
            let title = normalize(entry.title)
            let keywords = entry.keywords.map(normalize)
            let haystack = ([title] + keywords).joined(separator: " ")
            guard words.allSatisfy({ haystack.contains($0) }) else { continue }
            let rank: Int
            if title.hasPrefix(q) { rank = 0 }
            else if title.contains(q) { rank = 1 }
            else if keywords.contains(where: { $0.hasPrefix(q) }) { rank = 2 }
            else { rank = 3 }
            scored.append((entry, rank, order))
        }
        return scored
            .sorted { ($0.rank, $0.order) < ($1.rank, $1.order) }
            .prefix(limit)
            .map(\.entry)
    }

    // MARK: - Dates

    /// A day typed as "12.03", "12.03.2026", "2026-03-12", "12 марта",
    /// "march 12", "вчера" or "today". Nil when the text is not a date.
    /// A day-and-month with no year means the latest such day not in the
    /// future.
    static func parseDay(_ query: String, calendar: Calendar = .current, now: Date = .now) -> Date? {
        let q = normalize(query)
        guard !q.isEmpty else { return nil }
        let today = calendar.startOfDay(for: now)

        switch q {
        case "сегодня", "today": return today
        case "вчера", "yesterday": return calendar.date(byAdding: .day, value: -1, to: today)
        default: break
        }

        func make(day: Int, month: Int, year: Int?) -> Date? {
            var parts = DateComponents(year: year ?? calendar.component(.year, from: today), month: month, day: day)
            guard let date = calendar.date(from: parts),
                  calendar.component(.day, from: date) == day, calendar.component(.month, from: date) == month else { return nil }
            if year == nil, date > today {
                parts.year = (parts.year ?? 0) - 1
                return calendar.date(from: parts).flatMap { calendar.component(.day, from: $0) == day ? $0 : nil }
            }
            return date
        }

        let numeric = q.split(whereSeparator: { ".-/".contains($0) }).map(String.init)
        if numeric.count >= 2, numeric.count <= 3, numeric.allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isNumber) }) {
            let numbers = numeric.compactMap(Int.init)
            guard numbers.count == numeric.count else { return nil }
            if numeric.count == 3, numeric[0].count == 4 {
                return make(day: numbers[2], month: numbers[1], year: numbers[0])
            }
            let year: Int? = numeric.count == 3 ? (numbers[2] < 100 ? 2000 + numbers[2] : numbers[2]) : nil
            return make(day: numbers[0], month: numbers[1], year: year)
        }

        // "12 марта" / "march 12".
        let words = q.split(separator: " ").map(String.init)
        guard words.count == 2 else { return nil }
        let dayWord = words.first { $0.allSatisfy(\.isNumber) }
        let monthWord = words.first { !$0.allSatisfy(\.isNumber) }
        guard let dayWord, let monthWord, let day = Int(dayWord), let month = monthNumber(monthWord) else { return nil }
        return make(day: day, month: month, year: nil)
    }

    private static let monthRoots: [(root: String, month: Int)] = [
        ("янв", 1), ("jan", 1), ("фев", 2), ("feb", 2), ("мар", 3), ("mar", 3),
        ("апр", 4), ("apr", 4), ("мая", 5), ("май", 5), ("may", 5), ("июн", 6), ("jun", 6),
        ("июл", 7), ("jul", 7), ("авг", 8), ("aug", 8), ("сен", 9), ("sep", 9),
        ("окт", 10), ("oct", 10), ("ноя", 11), ("nov", 11), ("дек", 12), ("dec", 12)
    ]

    private static func monthNumber(_ word: String) -> Int? {
        guard word.count >= 3 else { return nil }
        return monthRoots.first { word.hasPrefix($0.root) }?.month
    }
}

// MARK: - Sessions

/// Finished sessions matching a query — by activity name, the ToDo List task
/// it came from, its type, or the day it started. Every path is a bounded
/// fetch (`limit`), newest first, so opening the search on years of history
/// never loads more than a screenful.
@MainActor
enum SessionSearch {
    static func find(
        _ query: String,
        in context: ModelContext,
        calendar: Calendar = .current,
        now: Date = .now,
        limit: Int = 40
    ) -> [FocusSession] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return [] }
        var found: [UUID: FocusSession] = [:]

        func collect(_ descriptor: FetchDescriptor<FocusSession>) {
            var descriptor = descriptor
            descriptor.fetchLimit = limit
            for session in (try? context.fetch(descriptor)) ?? [] where !session.isActive {
                found[session.id] = session
            }
        }
        let newestFirst = [SortDescriptor(\FocusSession.startDate, order: .reverse)]

        // The stored name may be Russian while the user types English (and
        // vice versa): look for both spellings of a built-in name.
        let canonical = canonicalData(q)
        collect(FetchDescriptor(predicate: #Predicate { $0.activity.localizedStandardContains(q) }, sortBy: newestFirst))
        if canonical != q {
            collect(FetchDescriptor(predicate: #Predicate { $0.activity.localizedStandardContains(canonical) }, sortBy: newestFirst))
        }
        collect(FetchDescriptor(
            predicate: #Predicate { $0.sourceTaskTitle?.localizedStandardContains(q) == true },
            sortBy: newestFirst
        ))

        let normalized = AnalyticsSearch.normalize(q)
        for type in SessionType.allCases where AnalyticsSearch.normalize(type.label).hasPrefix(normalized) || AnalyticsSearch.normalize(type.shortLabel).hasPrefix(normalized) {
            let raw = type.rawValue
            collect(FetchDescriptor(predicate: #Predicate { $0.sessionTypeRaw == raw }, sortBy: newestFirst))
        }

        if let day = AnalyticsSearch.parseDay(q, calendar: calendar, now: now),
           let next = calendar.date(byAdding: .day, value: 1, to: day) {
            collect(FetchDescriptor(predicate: #Predicate { $0.startDate >= day && $0.startDate < next }, sortBy: newestFirst))
        }

        return found.values.sorted { $0.startDate > $1.startDate }.prefix(limit).map { $0 }
    }
}
