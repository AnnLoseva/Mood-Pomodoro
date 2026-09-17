import Foundation

enum AnalyticsEngine: Sendable {
    static let dayMethod = L(
        "среднее дневных средних: каждый день с данными имеет вес 1",
        "mean of daily means: each day with data has weight 1"
    )
    static let sessionMethod = L(
        "среднее сеансов: каждый сеанс имеет вес 1",
        "mean of sessions: each session has weight 1"
    )
    static let mealMethod = L(
        "среднее приёмов пищи: каждый приём имеет вес 1",
        "mean of meals: each meal has weight 1"
    )
    static let nightMethod = L(
        "среднее ночей: каждая ночь имеет вес 1",
        "mean of nights: each night has weight 1"
    )

    static let emptyFacts = AnalyticsFacts(
        checkIns: [], sessions: [], conditionEvents: [], hunger: [], food: [],
        emotions: [], impulses: [], support: [], cycle: [], sleep: [],
        categories: [], healthMedication: [:]
    )

    static func build(
        facts: AnalyticsFacts,
        interval: DateInterval,
        previous: DateInterval?,
        calendar: Calendar,
        now: Date = .now
    ) -> AnalyticsSnapshot {
        PerfSignpost.interval("analytics.snapshot") {
            assemble(facts: facts, interval: interval, previous: previous, calendar: calendar, now: now)
        }
    }

    private static func assemble(
        facts: AnalyticsFacts,
        interval: DateInterval,
        previous: DateInterval?,
        calendar: Calendar,
        now: Date
    ) -> AnalyticsSnapshot {
        let days = buildDays(facts: facts, interval: interval, calendar: calendar, now: now)
        let previousDays = previous.map { buildDays(facts: facts, interval: $0, calendar: calendar, now: now) } ?? []
        let overview = buildOverview(days: days, previousDays: previousDays, interval: interval, calendar: calendar)
        let trajectory = buildTrajectory(facts: facts, interval: interval, now: now)
        return AnalyticsSnapshot(
            builtAt: now,
            interval: interval,
            days: days,
            overview: overview,
            activities: buildActivities(facts: facts, interval: interval, calendar: calendar, baselineMood: overview.mood.average, now: now),
            factors: buildFactors(facts: facts, days: days, calendar: calendar, baselineMood: overview.mood.average),
            reasons: buildReasons(facts: facts, interval: interval),
            food: buildFood(facts: facts, days: days, interval: interval, calendar: calendar),
            sleep: buildSleep(facts: facts, days: days, previousDays: previousDays, interval: interval, calendar: calendar),
            emotions: buildEmotions(days: days),
            impulses: buildImpulses(days: days),
            trajectory: trajectory,
            declineNote: declineNote(facts: facts, interval: interval, now: now)
        )
    }

    // MARK: - Days

    static func buildDays(
        facts: AnalyticsFacts,
        interval: DateInterval,
        calendar: Calendar,
        now: Date
    ) -> [AnalyticsDayRow] {
        var day = interval.start
        var rows: [AnalyticsDayRow] = []
        let checkIns = Dictionary(grouping: facts.checkIns.filter { $0.timestamp >= interval.start && $0.timestamp < interval.end }) {
            calendar.startOfDay(for: $0.timestamp)
        }
        let hunger = Dictionary(grouping: facts.hunger.filter { $0.eventDate >= interval.start && $0.eventDate < interval.end }) {
            calendar.startOfDay(for: $0.eventDate)
        }
        let food = Dictionary(grouping: facts.food.filter { $0.eventDate >= interval.start && $0.eventDate < interval.end }) {
            calendar.startOfDay(for: $0.eventDate)
        }
        let emotions = Dictionary(grouping: facts.emotions.filter { $0.eventDate >= interval.start && $0.eventDate < interval.end }) {
            calendar.startOfDay(for: $0.eventDate)
        }
        let impulses = Dictionary(grouping: facts.impulses.filter { $0.eventDate >= interval.start && $0.eventDate < interval.end }) {
            calendar.startOfDay(for: $0.eventDate)
        }
        var support: [Date: String] = [:]
        for item in facts.support {
            support[calendar.startOfDay(for: item.day)] = item.statusRaw
        }
        let med = facts.healthMedication
        let sleepResolved = SleepAggregationService.resolveOverlaps(sessions: facts.sleep).filter { !$0.isSuperseded }
        let sleepByDay = Dictionary(grouping: sleepResolved.filter { $0.day >= interval.start && $0.day < interval.end }) {
            calendar.startOfDay(for: $0.day)
        }
        let marks = facts.cycle.map {
            CycleMark(
                day: $0.day,
                kind: CycleEventKind(rawValue: $0.kindRaw) ?? .periodDay,
                source: SleepSource(rawValue: $0.sourceRaw) ?? .manual
            )
        }
        let typeDurations = splitSessionDurations(facts.sessions, interval: interval, calendar: calendar, now: now)
        let sessionCounts = sessionCountsByDay(facts.sessions, interval: interval, calendar: calendar, now: now)

        while day < interval.end {
            let next = calendar.date(byAdding: .day, value: 1, to: day) ?? interval.end
            let dayCheckIns = (checkIns[day] ?? []).sorted { $0.timestamp < $1.timestamp }
            let dayHunger = hunger[day] ?? []
            let dayFood = food[day] ?? []
            let dayEmotions = emotions[day] ?? []
            let dayImpulses = impulses[day] ?? []
            let night = (sleepByDay[day] ?? []).filter { $0.kind == .night }
            let naps = (sleepByDay[day] ?? []).filter { $0.kind == .nap }
            let nightSleep = night.isEmpty ? nil : night.reduce(0.0) { $0 + $1.totalSleep }
            let supportRaw = support[day] ?? med[day]
            let durations = typeDurations[day] ?? [:]
            let row = AnalyticsDayRow(
                day: day,
                mood: timeWeightedAverage(
                    points: dayCheckIns.map { ($0.timestamp, $0.mood) },
                    start: day,
                    end: next,
                    maxGap: AnalyticsService.maximumMoodGap
                ),
                moodCount: dayCheckIns.count,
                energy: mean(dayCheckIns.compactMap(\.energy)),
                energyCount: dayCheckIns.compactMap(\.energy).count,
                motivation: mean(dayCheckIns.compactMap(\.motivation)),
                motivationCount: dayCheckIns.compactMap(\.motivation).count,
                hunger: mean(dayHunger.compactMap(\.hunger)),
                hungerCount: dayHunger.compactMap(\.hunger).count,
                appetite: mean(dayHunger.compactMap(\.appetite)),
                appetiteCount: dayHunger.compactMap(\.appetite).count,
                sleepSeconds: nightSleep,
                napSeconds: naps.reduce(0) { $0 + $1.totalSleep },
                sleepQuality: mean(night.compactMap { $0.quality.map(\.scale) }),
                awakeningCount: {
                    let values = night.compactMap(\.awakeningCount)
                    return values.isEmpty ? nil : values.reduce(0, +)
                }(),
                bedtime: night.map(\.start).min(),
                wakeTime: night.map(\.end).max(),
                deepSeconds: {
                    let values = night.map { $0.duration(of: .deep) }.filter { $0 > 0 }
                    return values.isEmpty ? nil : values.reduce(0, +) / Double(values.count)
                }(),
                remSeconds: {
                    let values = night.map { $0.duration(of: .rem) }.filter { $0 > 0 }
                    return values.isEmpty ? nil : values.reduce(0, +) / Double(values.count)
                }(),
                coreSeconds: {
                    let values = night.map { $0.duration(of: .core) }.filter { $0 > 0 }
                    return values.isEmpty ? nil : values.reduce(0, +) / Double(values.count)
                }(),
                totalStagedSleep: {
                    let values = night.filter { $0.duration(of: .deep) + $0.duration(of: .rem) + $0.duration(of: .core) > 0 }
                    return values.isEmpty ? nil : values.reduce(0) { $0 + $1.totalSleep } / Double(values.count)
                }(),
                isPeriodDay: AnalyticsService.isPeriodDay(day, marks: marks, calendar: calendar),
                cycleDay: AnalyticsService.cycleDay(for: day, marks: marks, calendar: calendar),
                supportRaw: supportRaw,
                mealCount: dayFood.count,
                treatCount: dayFood.filter { $0.categoryRaw == FoodCategory.treat.rawValue }.count,
                emotions: Set(dayEmotions.flatMap(\.emotions)),
                impulseCount: dayImpulses.count,
                impulseCategories: Set(dayImpulses.map(\.categoryRaw)),
                factorKeys: Set((checkIns[day] ?? []).flatMap(\.conditions).map { factorID(category: $0.categoryID, option: $0.optionID) }),
                durationByType: durations,
                sessionCount: sessionCounts[day] ?? 0
            )
            if !isEmpty(row) { rows.append(row) }
            day = next
        }
        return rows
    }

    static func isEmpty(_ row: AnalyticsDayRow) -> Bool {
        row.moodCount == 0 && row.energyCount == 0 && row.motivationCount == 0
            && row.hungerCount == 0 && row.appetiteCount == 0 && row.sleepSeconds == nil
            && row.napSeconds == 0 && row.supportRaw == nil && !row.isPeriodDay
            && row.mealCount == 0 && row.emotions.isEmpty && row.impulseCount == 0
            && row.durationByType.isEmpty && row.sessionCount == 0
    }

    /// Split session *active* duration across calendar days using Calendar, so
    /// a session that crosses midnight is not dumped entirely on its start day.
    static func splitSessionDurations(
        _ sessions: [AnalyticsSessionFact],
        interval: DateInterval,
        calendar: Calendar,
        now: Date
    ) -> [Date: [String: TimeInterval]] {
        var result: [Date: [String: TimeInterval]] = [:]
        for session in sessions {
            let end = session.end ?? now
            guard session.start < interval.end && end > interval.start else { continue }
            let key = session.typeRaw ?? "unassigned"
            let wall = max(end.timeIntervalSince(session.start), 0.001)
            var cursor = max(session.start, interval.start)
            let stop = min(end, interval.end)
            while cursor < stop {
                let day = calendar.startOfDay(for: cursor)
                let next = min(calendar.date(byAdding: .day, value: 1, to: day) ?? stop, stop)
                let slice = next.timeIntervalSince(cursor)
                if slice > 0 {
                    result[day, default: [:]][key, default: 0] += session.activeDuration * (slice / wall)
                }
                cursor = next
            }
        }
        return result
    }

    static func sessionCountsByDay(
        _ sessions: [AnalyticsSessionFact],
        interval: DateInterval,
        calendar: Calendar,
        now: Date
    ) -> [Date: Int] {
        var result: [Date: Int] = [:]
        for session in sessions {
            let end = session.end ?? now
            guard session.start < interval.end && end > interval.start else { continue }
            var cursor = max(session.start, interval.start)
            let stop = min(end, interval.end)
            var seen = Set<Date>()
            while cursor < stop {
                let day = calendar.startOfDay(for: cursor)
                if seen.insert(day).inserted {
                    result[day, default: 0] += 1
                }
                cursor = calendar.date(byAdding: .day, value: 1, to: day) ?? stop
            }
        }
        return result
    }

    // MARK: - Overview

    static func buildOverview(
        days: [AnalyticsDayRow],
        previousDays: [AnalyticsDayRow],
        interval: DateInterval,
        calendar: Calendar
    ) -> AnalyticsOverview {
        let calendarDays = countDays(in: interval, calendar: calendar)
        let mood = scaleAverage(days.map(\.mood), observations: days.map(\.moodCount))
        let energy = scaleAverage(days.map(\.energy), observations: days.map(\.energyCount))
        let motivation = scaleAverage(days.map(\.motivation), observations: days.map(\.motivationCount))
        let hunger = scaleAverage(days.map(\.hunger), observations: days.map(\.hungerCount))
        let appetite = scaleAverage(days.map(\.appetite), observations: days.map(\.appetiteCount))
        let prevMood = scaleAverage(previousDays.map(\.mood), observations: previousDays.map(\.moodCount))
        let prevEnergy = scaleAverage(previousDays.map(\.energy), observations: previousDays.map(\.energyCount))
        let prevMotivation = scaleAverage(previousDays.map(\.motivation), observations: previousDays.map(\.motivationCount))
        let prevSleep = mean(previousDays.compactMap(\.sleepSeconds))
        let sleep = mean(days.compactMap(\.sleepSeconds))
        var deltas: [AnalyticsDelta] = []
        func addDelta(key: String, title: String, current: AnalyticsScaleAverage, previous: AnalyticsScaleAverage, threshold: Double = 0.15) {
            guard let c = current.average, let p = previous.average else { return }
            let independent = min(current.dayCount, previous.dayCount)
            let confidence = AnalyticsConfidence(independentCount: independent)
            guard confidence != .insufficient, abs(c - p) >= threshold else { return }
            deltas.append(AnalyticsDelta(
                key: key, title: title, current: c, previous: p, difference: c - p,
                currentDays: current.dayCount, previousDays: previous.dayCount, confidence: confidence
            ))
        }
        addDelta(key: "mood", title: L("Настроение", "Mood"), current: mood, previous: prevMood)
        addDelta(key: "energy", title: L("Энергия", "Energy"), current: energy, previous: prevEnergy)
        addDelta(key: "motivation", title: L("Мотивация", "Motivation"), current: motivation, previous: prevMotivation)
        if let sleep, let prevSleep, abs(sleep - prevSleep) >= 15 * 60 {
            let independent = min(days.compactMap(\.sleepSeconds).count, previousDays.compactMap(\.sleepSeconds).count)
            let confidence = AnalyticsConfidence(independentCount: independent)
            if confidence != .insufficient {
                deltas.append(AnalyticsDelta(
                    key: "sleep",
                    title: L("Сон", "Sleep"),
                    current: sleep,
                    previous: prevSleep,
                    difference: sleep - prevSleep,
                    currentDays: days.compactMap(\.sleepSeconds).count,
                    previousDays: previousDays.compactMap(\.sleepSeconds).count,
                    confidence: confidence
                ))
            }
        }
        return AnalyticsOverview(
            periodLabel: "\(formatDay(interval.start, calendar)) – \(formatDay(calendar.date(byAdding: .day, value: -1, to: interval.end) ?? interval.start, calendar))",
            periodStart: interval.start,
            periodEndExclusive: interval.end,
            dayCount: calendarDays,
            daysWithData: days.count,
            coverage: calendarDays == 0 ? 0 : Double(days.count) / Double(calendarDays),
            mood: mood,
            energy: energy,
            motivation: motivation,
            hunger: hunger,
            appetite: appetite,
            checkInCount: days.reduce(0) { $0 + $1.moodCount },
            sessionCount: days.reduce(0) { $0 + $1.sessionCount },
            nightCount: days.filter { $0.sleepSeconds != nil }.count,
            mealCount: days.reduce(0) { $0 + $1.mealCount },
            emotionDayCount: days.filter { !$0.emotions.isEmpty }.count,
            impulseDayCount: days.filter { $0.impulseCount > 0 }.count,
            periodDayCount: days.filter(\.isPeriodDay).count,
            supportTakenDays: days.filter { $0.supportRaw == SupportStatus.taken.rawValue }.count,
            supportSkippedDays: days.filter { $0.supportRaw == SupportStatus.notTaken.rawValue }.count,
            restSeconds: days.reduce(0) { $0 + ($1.durationByType[SessionType.rest.rawValue] ?? 0) },
            workSeconds: days.reduce(0) { $0 + ($1.durationByType[SessionType.obligatoryWork.rawValue] ?? 0) },
            studySeconds: days.reduce(0) { $0 + ($1.durationByType[SessionType.study.rawValue] ?? 0) },
            untypedSeconds: days.reduce(0) { $0 + ($1.durationByType["unassigned"] ?? 0) },
            averageSleepSeconds: sleep,
            deltas: deltas
        )
    }

    // MARK: - Activities

    static func buildActivities(
        facts: AnalyticsFacts,
        interval: DateInterval,
        calendar: Calendar,
        baselineMood: Double?,
        now: Date
    ) -> [AnalyticsActivityRow] {
        let sessions = facts.sessions.filter { $0.start < interval.end && ($0.end ?? now) > interval.start }
        let checkInsBySession = Dictionary(grouping: facts.checkIns) { $0.sessionID }
        let standalone = facts.checkIns.filter { $0.sessionID == nil }.sorted { $0.timestamp < $1.timestamp }
        let grouped = Dictionary(grouping: sessions) { canonicalData($0.activity) + "|" + ($0.typeRaw ?? "unassigned") }
        return grouped.map { key, group in
            let sessionMoods = group.map { mean((checkInsBySession[$0.id] ?? []).map(\.mood)) }
            let sessionEnergy = group.map { mean((checkInsBySession[$0.id] ?? []).compactMap(\.energy)) }
            let sessionMotivation = group.map { mean((checkInsBySession[$0.id] ?? []).compactMap(\.motivation)) }
            let before = group.map { session in
                nearestMood(in: standalone, around: session.start, window: AnalyticsService.mealLinkWindow, after: false)
                    ?? (checkInsBySession[session.id] ?? []).sorted { $0.timestamp < $1.timestamp }.first?.mood
            }
            let during = sessionMoods
            let after = group.map { session in
                let end = session.end ?? now
                return nearestMood(in: standalone, around: end, window: AnalyticsService.mealLinkWindow, after: true)
                    ?? (checkInsBySession[session.id] ?? []).sorted { $0.timestamp < $1.timestamp }.last?.mood
            }
            let moodAvg = scaleAverage(sessionMoods, observations: group.map { (checkInsBySession[$0.id] ?? []).count }, method: sessionMethod)
            let days = Set(group.map { calendar.startOfDay(for: $0.start) }).count
            let total = group.reduce(0.0) { $0 + $1.activeDuration }
            let first = group[0]
            var weekly: [Date: (TimeInterval, Int)] = [:]
            for session in group {
                let week = calendar.dateInterval(of: .weekOfYear, for: session.start)?.start ?? calendar.startOfDay(for: session.start)
                let current = weekly[week] ?? (0, 0)
                weekly[week] = (current.0 + session.activeDuration, current.1 + 1)
            }
            return AnalyticsActivityRow(
                id: key,
                name: first.activity,
                typeRaw: first.typeRaw,
                sessionCount: group.count,
                dayCount: days,
                totalSeconds: total,
                averageSeconds: group.isEmpty ? 0 : total / Double(group.count),
                mood: moodAvg,
                energy: scaleAverage(sessionEnergy, observations: group.map { (checkInsBySession[$0.id] ?? []).compactMap(\.energy).count }, method: sessionMethod),
                motivation: scaleAverage(sessionMotivation, observations: group.map { (checkInsBySession[$0.id] ?? []).compactMap(\.motivation).count }, method: sessionMethod),
                moodBefore: scaleAverage(before, observations: Array(repeating: 1, count: before.count), method: sessionMethod),
                moodDuring: scaleAverage(during, observations: group.map { (checkInsBySession[$0.id] ?? []).count }, method: sessionMethod),
                moodAfter: scaleAverage(after, observations: Array(repeating: 1, count: after.count), method: sessionMethod),
                moodDelta: moodAvg.average.flatMap { avg in baselineMood.map { avg - $0 } },
                weekly: weekly.keys.sorted().map {
                    let value = weekly[$0] ?? (0, 0)
                    return AnalyticsWeekPoint(weekStart: $0, seconds: value.0, sessionCount: value.1)
                },
                confidence: AnalyticsConfidence(independentCount: group.count)
            )
        }
        .sorted { $0.totalSeconds > $1.totalSeconds }
    }

    // MARK: - Factors

    static func buildFactors(
        facts: AnalyticsFacts,
        days: [AnalyticsDayRow],
        calendar: Calendar,
        baselineMood: Double?
    ) -> [AnalyticsFactorRow] {
        var dayIndex: [String: [Date]] = [:]
        var sessionIndex: [String: Set<UUID>] = [:]
        var observationIndex: [String: Int] = [:]
        var moodByKey: [String: [Double]] = [:]
        var energyByKey: [String: [Double]] = [:]
        var motivationByKey: [String: [Double]] = [:]
        var meta: [String: AnalyticsConditionFact] = [:]
        var minutesToDifficult: [String: [Double]] = [:]

        let checkInsByDay = Dictionary(grouping: facts.checkIns) { calendar.startOfDay(for: $0.timestamp) }
        let eventsBySession = Dictionary(grouping: facts.conditionEvents) { $0.sessionID }
        let checkInsBySession = Dictionary(grouping: facts.checkIns) { $0.sessionID }

        for day in days {
            var seen = Set<String>()
            for checkIn in checkInsByDay[day.day] ?? [] {
                for condition in checkIn.conditions {
                    let key = factorID(category: condition.categoryID, option: condition.optionID)
                    meta[key] = condition
                    observationIndex[key, default: 0] += 1
                    if let sessionID = checkIn.sessionID { sessionIndex[key, default: []].insert(sessionID) }
                    if seen.insert(key).inserted {
                        dayIndex[key, default: []].append(day.day)
                        if let mood = day.mood { moodByKey[key, default: []].append(mood) }
                        if let energy = day.energy { energyByKey[key, default: []].append(energy) }
                        if let motivation = day.motivation { motivationByKey[key, default: []].append(motivation) }
                    }
                }
            }
        }

        for (sessionID, events) in eventsBySession {
            guard let sessionID else { continue }
            let checkIns = (checkInsBySession[sessionID] ?? []).sorted { $0.timestamp < $1.timestamp }
            for event in events {
                let key = factorID(category: event.categoryID, option: event.optionID)
                guard let firstDifficult = checkIns.first(where: {
                    $0.timestamp >= event.timestamp && ($0.moodRaw == Mood.tired.rawValue || $0.moodRaw == Mood.veryBad.rawValue)
                }) else { continue }
                minutesToDifficult[key, default: []].append(firstDifficult.timestamp.timeIntervalSince(event.timestamp) / 60)
            }
        }

        return meta.keys.sorted().compactMap { key in
            guard let condition = meta[key] else { return nil }
            let dayCount = dayIndex[key]?.count ?? 0
            let mood = scaleAverage(moodByKey[key] ?? [], observations: Array(repeating: 1, count: moodByKey[key]?.count ?? 0))
            let needed = max(0, AnalyticsConfidence.insufficient.neededForPreliminary - dayCount)
            return AnalyticsFactorRow(
                id: key,
                categoryID: condition.categoryID,
                optionID: condition.optionID,
                categoryName: condition.categoryName,
                optionName: condition.optionName,
                icon: condition.icon,
                iconImageName: condition.iconImageName,
                categoryEnabled: condition.categoryEnabled,
                dayCount: dayCount,
                sessionCount: sessionIndex[key]?.count ?? 0,
                observationCount: observationIndex[key] ?? 0,
                mood: mood,
                energy: scaleAverage(energyByKey[key] ?? [], observations: Array(repeating: 1, count: energyByKey[key]?.count ?? 0)),
                motivation: scaleAverage(motivationByKey[key] ?? [], observations: Array(repeating: 1, count: motivationByKey[key]?.count ?? 0)),
                moodDelta: mood.average.flatMap { avg in baselineMood.map { avg - $0 } },
                minutesToDifficult: mean(minutesToDifficult[key] ?? []),
                neededForPreliminary: needed,
                confidence: AnalyticsConfidence(independentCount: dayCount)
            )
        }
        .sorted { ($0.moodDelta ?? -999) > ($1.moodDelta ?? -999) }
    }

    static func factorID(category: UUID, option: UUID) -> String {
        "\(category.uuidString)|\(option.uuidString)"
    }

    // MARK: - Reasons

    static func buildReasons(facts: AnalyticsFacts, interval: DateInterval) -> [AnalyticsReasonRow] {
        let inPeriod = facts.checkIns.filter { $0.timestamp >= interval.start && $0.timestamp < interval.end }
        let byMood = Dictionary(grouping: inPeriod, by: \.moodRaw)
        var rows: [AnalyticsReasonRow] = []
        for (moodRaw, group) in byMood {
            let answered = group.filter { reason in
                guard let text = reason.reason else { return false }
                return !text.isEmpty
            }
            let counts = Dictionary(grouping: answered.compactMap(\.reason), by: { $0 }).mapValues(\.count)
            for (reason, count) in counts {
                rows.append(AnalyticsReasonRow(
                    moodRaw: moodRaw,
                    reason: reason,
                    count: count,
                    moodTotal: group.count,
                    answeredTotal: answered.count,
                    percentageOfAnswered: answered.isEmpty ? 0 : Double(count) / Double(answered.count)
                ))
            }
        }
        return rows.sorted { $0.count > $1.count }
    }

    // MARK: - Food

    static func buildFood(
        facts: AnalyticsFacts,
        days: [AnalyticsDayRow],
        interval: DateInterval,
        calendar: Calendar
    ) -> AnalyticsFoodSummary {
        let meals = facts.food.filter { $0.eventDate >= interval.start && $0.eventDate < interval.end }
            .sorted { $0.eventDate < $1.eventDate }
        let hunger = facts.hunger.filter { $0.eventDate >= interval.start && $0.eventDate < interval.end }
            .sorted { $0.eventDate < $1.eventDate }
        let checkIns = facts.checkIns.filter { $0.timestamp >= interval.start && $0.timestamp < interval.end }
            .sorted { $0.timestamp < $1.timestamp }
        let window = AnalyticsService.mealLinkWindow
        var hungerBefore: [Double] = []
        var appetiteFilled = 0
        var moodBefore: [Double] = []
        var moodAfter: [Double] = []
        var fullnessAfter: [Double] = []
        var usedHungerIDs = Set<UUID>()
        var usedCheckInIDs = Set<UUID>()

        struct MealStats {
            var hunger: Double?
            var moodBefore: Double?
            var moodAfter: Double?
            var fullness: Double?
        }
        var perMeal: [UUID: MealStats] = [:]

        for meal in meals {
            var stats = MealStats(fullness: meal.fullness)
            if let match = last(in: hunger, before: meal.eventDate, window: window, where: { $0.hunger != nil && !usedHungerIDs.contains($0.id) }) {
                usedHungerIDs.insert(match.id)
                stats.hunger = match.hunger
                hungerBefore.append(match.hunger!)
                if match.appetite != nil { appetiteFilled += 1 }
            }
            if let before = last(in: checkIns, before: meal.eventDate, window: window, where: { !usedCheckInIDs.contains($0.id) }) {
                usedCheckInIDs.insert(before.id)
                stats.moodBefore = before.mood
                moodBefore.append(before.mood)
            }
            if let after = first(in: checkIns, after: meal.eventDate, window: window, where: { !usedCheckInIDs.contains($0.id) }) {
                usedCheckInIDs.insert(after.id)
                stats.moodAfter = after.mood
                moodAfter.append(after.mood)
            }
            if let fullness = meal.fullness { fullnessAfter.append(fullness) }
            perMeal[meal.id] = stats
        }

        var pairCounts: [String: Int] = [:]
        for entry in hunger {
            guard let h = entry.hunger, let a = entry.appetite else { continue }
            let key = "\(Int(h))|\(Int(a))"
            pairCounts[key, default: 0] += 1
        }
        let cells = pairCounts.map { key, count in
            let parts = key.split(separator: "|")
            return AnalyticsGridCell(hungerKey: String(parts[0]), appetiteKey: String(parts[1]), count: count)
        }
        let calendarDays = max(1, countDays(in: interval, calendar: calendar))
        let treatCount = meals.filter { $0.categoryRaw == FoodCategory.treat.rawValue }.count
        let byCategory = Dictionary(grouping: meals, by: \.categoryRaw).map { key, group -> AnalyticsFoodCategoryRow in
            let stats = group.compactMap { perMeal[$0.id] }
            return AnalyticsFoodCategoryRow(
                id: key,
                label: FoodCategory(rawValue: key)?.label ?? key,
                count: group.count,
                moodAfter: scaleAverage(stats.map(\.moodAfter), observations: Array(repeating: 1, count: stats.compactMap(\.moodAfter).count), method: mealMethod),
                hungerBefore: scaleAverage(stats.map(\.hunger), observations: Array(repeating: 1, count: stats.compactMap(\.hunger).count), method: mealMethod)
            )
        }

        return AnalyticsFoodSummary(
            mealCount: meals.count,
            hungerFilledShare: meals.isEmpty ? nil : Double(hungerBefore.count) / Double(meals.count),
            appetiteFilledShare: meals.isEmpty ? nil : Double(appetiteFilled) / Double(meals.count),
            fullnessFilledShare: meals.isEmpty ? nil : Double(fullnessAfter.count) / Double(meals.count),
            moodBefore: scaleAverage(moodBefore.map(Optional.some), observations: Array(repeating: 1, count: moodBefore.count), method: mealMethod),
            moodAfter: scaleAverage(moodAfter.map(Optional.some), observations: Array(repeating: 1, count: moodAfter.count), method: mealMethod),
            hungerBefore: scaleAverage(hungerBefore.map(Optional.some), observations: Array(repeating: 1, count: hungerBefore.count), method: mealMethod),
            fullnessAfter: scaleAverage(fullnessAfter.map(Optional.some), observations: Array(repeating: 1, count: fullnessAfter.count), method: mealMethod),
            treatsPerDay: Double(treatCount) / Double(calendarDays),
            snacksPerDay: Double(treatCount) / Double(calendarDays),
            impulseFoodDays: days.filter { $0.impulseCategories.contains(ImpulseCategory.food.rawValue) }.count,
            byCategory: byCategory.sorted { $0.count > $1.count },
            hungerAppetitePairs: cells,
            linkWindowSeconds: window
        )
    }

    // MARK: - Sleep

    static func buildSleep(
        facts: AnalyticsFacts,
        days: [AnalyticsDayRow],
        previousDays: [AnalyticsDayRow],
        interval: DateInterval,
        calendar: Calendar
    ) -> AnalyticsSleepSummary {
        let nights = days.compactMap(\.sleepSeconds)
        let staged = days.filter { $0.deepSeconds != nil || $0.remSeconds != nil || $0.coreSeconds != nil }
        func bucket(_ id: String, _ label: String, range: Range<TimeInterval>) -> AnalyticsSleepBucket {
            let group = days.filter { night in
                guard let seconds = night.sleepSeconds else { return false }
                return range.contains(seconds)
            }
            return AnalyticsSleepBucket(
                id: id,
                label: label,
                nightCount: group.count,
                mood: scaleAverage(group.map(\.mood), observations: group.map(\.moodCount)),
                energy: scaleAverage(group.map(\.energy), observations: group.map(\.energyCount)),
                appetite: scaleAverage(group.map(\.appetite), observations: group.map(\.appetiteCount))
            )
        }
        func cycleBucket(_ id: String, _ label: String, include: (AnalyticsDayRow) -> Bool) -> AnalyticsSleepBucket {
            let group = days.filter { $0.sleepSeconds != nil && include($0) }
            return AnalyticsSleepBucket(
                id: id,
                label: label,
                nightCount: group.count,
                mood: scaleAverage(group.map(\.mood), observations: group.map(\.moodCount)),
                energy: scaleAverage(group.map(\.energy), observations: group.map(\.energyCount)),
                appetite: scaleAverage(group.map(\.appetite), observations: group.map(\.appetiteCount))
            )
        }
        return AnalyticsSleepSummary(
            nightCount: nights.count,
            averageSeconds: mean(nights),
            medianSeconds: median(nights),
            shortestSeconds: nights.min(),
            longestSeconds: nights.max(),
            averageQuality: mean(days.compactMap(\.sleepQuality)),
            averageAwakenings: mean(days.compactMap { $0.awakeningCount.map(Double.init) }),
            napCount: days.filter(\.hasNap).count,
            averageNapSeconds: mean(days.filter(\.hasNap).map(\.napSeconds)),
            bedtimeSpreadSeconds: circularSpread(days.compactMap(\.bedtime).map { minutesOfDay($0, calendar: calendar) }),
            wakeSpreadSeconds: circularSpread(days.compactMap(\.wakeTime).map { minutesOfDay($0, calendar: calendar) }),
            averageDeepSeconds: mean(staged.compactMap(\.deepSeconds)),
            averageDeepShare: mean(staged.compactMap { day -> Double? in
                guard let deep = day.deepSeconds, let total = day.totalStagedSleep, total > 0 else { return nil }
                return deep / total
            }),
            averageREMSeconds: mean(staged.compactMap(\.remSeconds)),
            averageCoreSeconds: mean(staged.compactMap(\.coreSeconds)),
            stagedNightCount: staged.count,
            previousAverageSeconds: mean(previousDays.compactMap(\.sleepSeconds)),
            previousNightCount: previousDays.compactMap(\.sleepSeconds).count,
            moodAfter: [
                bucket("under6", L("Меньше 6 часов", "Under 6 hours"), range: 0..<(6 * 3600)),
                bucket("6to8", L("6–8 часов", "6–8 hours"), range: (6 * 3600)..<(8 * 3600)),
                bucket("over8", L("Больше 8 часов", "Over 8 hours"), range: (8 * 3600)..<TimeInterval.greatestFiniteMagnitude)
            ],
            cycleBuckets: [
                cycleBucket("period", L("Дни менструации", "Period days"), include: { $0.isPeriodDay }),
                cycleBucket("other", L("Остальные дни", "Other days"), include: { !$0.isPeriodDay })
            ]
        )
    }

    static func buildEmotions(days: [AnalyticsDayRow]) -> [AnalyticsEmotionRow] {
        let keys = Set(days.flatMap(\.emotions))
        return keys.sorted().map { raw in
            let group = days.filter { $0.emotions.contains(raw) }
            var co: [String: Int] = [:]
            for day in group {
                for other in day.emotions where other != raw {
                    co[other, default: 0] += 1
                }
            }
            return AnalyticsEmotionRow(
                id: raw,
                raw: raw,
                dayCount: group.count,
                entryCount: group.count,
                mood: scaleAverage(group.map(\.mood), observations: group.map(\.moodCount)),
                energy: scaleAverage(group.map(\.energy), observations: group.map(\.energyCount)),
                motivation: scaleAverage(group.map(\.motivation), observations: group.map(\.motivationCount)),
                previousNightSleep: mean(group.compactMap(\.sleepSeconds)),
                cooccurrence: co.map { AnalyticsLabeledCount(id: "\(raw)|\($0.key)", label: Emotion(rawValue: $0.key)?.label ?? $0.key, count: $0.value) }
                    .sorted { $0.count > $1.count }
            )
        }
        .sorted { $0.dayCount > $1.dayCount }
    }

    static func buildImpulses(days: [AnalyticsDayRow]) -> [AnalyticsImpulseRow] {
        let keys = Set(ImpulseCategory.allCases.map(\.rawValue)).union(days.flatMap(\.impulseCategories))
        return keys.sorted().compactMap { raw in
            let group = days.filter { $0.impulseCategories.contains(raw) }
            let entryCount = group.reduce(0) { $0 + $1.impulseCount }
            guard entryCount > 0 || ImpulseCategory(rawValue: raw) != nil else { return nil }
            if entryCount == 0 { return nil }
            return AnalyticsImpulseRow(
                id: raw,
                categoryRaw: raw,
                dayCount: group.count,
                entryCount: entryCount,
                mood: scaleAverage(group.map(\.mood), observations: group.map(\.moodCount)),
                energy: scaleAverage(group.map(\.energy), observations: group.map(\.energyCount)),
                motivation: scaleAverage(group.map(\.motivation), observations: group.map(\.motivationCount)),
                previousNightSleep: mean(group.compactMap(\.sleepSeconds)),
                periodDayCount: group.filter(\.isPeriodDay).count,
                supportTakenDays: group.filter { $0.supportRaw == SupportStatus.taken.rawValue }.count
            )
        }
        .sorted { $0.entryCount > $1.entryCount }
    }

    /// Session trajectory: average of per-session bucket means, so a session
    /// with many check-ins cannot dominate. Decline copy is omitted unless
    /// enough independent sessions actually fall.
    static func buildTrajectory(facts: AnalyticsFacts, interval: DateInterval, now: Date) -> [MoodTimelinePoint] {
        let sessions = facts.sessions.filter { $0.start < interval.end && ($0.end ?? now) > interval.start }
        let checkIns = Dictionary(grouping: facts.checkIns) { $0.sessionID }
        let bucket = 20
        var sums: [Int: Double] = [:]
        var counts: [Int: Int] = [:]
        for session in sessions {
            let points = (checkIns[session.id] ?? []).map { ($0.timestamp.timeIntervalSince(session.start) / 60, $0.mood) }
            var perBucket: [Int: [Double]] = [:]
            for (minutes, mood) in points where minutes >= 0 {
                let start = (Int(minutes) / bucket) * bucket
                perBucket[start, default: []].append(mood)
            }
            for (start, values) in perBucket {
                sums[start, default: 0] += values.reduce(0, +) / Double(values.count)
                counts[start, default: 0] += 1
            }
        }
        return sums.keys.sorted().map { start in
            let n = counts[start] ?? 1
            return MoodTimelinePoint(minuteBucketStart: start, averageMood: (sums[start] ?? 0) / Double(n), sampleCount: n)
        }
    }

    static func declineNote(facts: AnalyticsFacts, interval: DateInterval, now: Date) -> String? {
        let sessions = facts.sessions.filter { $0.start < interval.end && ($0.end ?? now) > interval.start }
        let checkIns = Dictionary(grouping: facts.checkIns) { $0.sessionID }
        var declined = 0
        var eligible = 0
        for session in sessions {
            let points = (checkIns[session.id] ?? []).sorted { $0.timestamp < $1.timestamp }.map(\.mood)
            guard points.count >= 2 else { continue }
            eligible += 1
            let first = points[0]
            let last = points[points.count - 1]
            if first - last >= 0.7 { declined += 1 }
        }
        guard AnalyticsConfidence(independentCount: eligible) != .insufficient,
              declined * 2 >= eligible, eligible > 0 else { return nil }
        return L(
            "В \(declined) из \(eligible) сеансов настроение к концу было ниже. Предварительное наблюдение, не причина.",
            "In \(declined) of \(eligible) sessions mood was lower by the end. A preliminary observation, not a cause."
        )
    }

    static func compare(
        days: [AnalyticsDayRow],
        outcome: String,
        groups: [(id: String, label: String, include: (AnalyticsDayRow) -> Bool)]
    ) -> [AnalyticsCompareGroup] {
        groups.map { group in
            let subset = days.filter(group.include)
            let values = subset.compactMap { $0.value(outcome) }
            return AnalyticsCompareGroup(
                id: group.id,
                label: group.label,
                dayCount: subset.count,
                observationCount: values.count,
                average: mean(values),
                confidence: AnalyticsConfidence(independentCount: subset.count)
            )
        }
    }

    // MARK: - Time-weighted mood (day-bounded)

    /// Time-weighted mean of points that already lie inside `[start, end)`.
    /// Gaps never extend past the day bounds, so a 23:50 check-in cannot
    /// pull weight from 00:10 the next day.
    static func timeWeightedAverage(
        points: [(Date, Double)],
        start: Date,
        end: Date,
        maxGap: TimeInterval
    ) -> Double? {
        let inside = points
            .filter { $0.0 >= start && $0.0 < end }
            .sorted { $0.0 < $1.0 }
        guard !inside.isEmpty else { return nil }
        guard inside.count > 1 else { return inside[0].1 }

        var weightedSum = 0.0
        var totalWeight = 0.0
        for index in inside.indices {
            let previous = index == 0 ? start : inside[index - 1].0
            let next = index == inside.count - 1 ? end : inside[index + 1].0
            let before = min(inside[index].0.timeIntervalSince(previous), maxGap)
            let after = min(next.timeIntervalSince(inside[index].0), maxGap)
            let weight = (before + after) / 2
            weightedSum += inside[index].1 * weight
            totalWeight += weight
        }
        guard totalWeight > 0 else { return mean(inside.map(\.1)) }
        return weightedSum / totalWeight
    }

    // MARK: - Helpers

    static func mean(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    static func median(_ values: [TimeInterval]) -> TimeInterval? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let mid = sorted.count / 2
        if sorted.count % 2 == 0 {
            return (sorted[mid - 1] + sorted[mid]) / 2
        }
        return sorted[mid]
    }

    static func circularSpread(_ minutes: [Int]) -> TimeInterval? {
        guard minutes.count >= 2 else { return nil }
        let sorted = minutes.sorted()
        var gaps: [Int] = []
        for index in 0..<(sorted.count - 1) {
            gaps.append(sorted[index + 1] - sorted[index])
        }
        gaps.append((sorted[0] + 24 * 60) - sorted[sorted.count - 1])
        let maxGap = gaps.max() ?? 0
        let span = 24 * 60 - maxGap
        return TimeInterval(span) * 60
    }

    static func minutesOfDay(_ date: Date, calendar: Calendar) -> Int {
        let comps = calendar.dateComponents([.hour, .minute], from: date)
        return (comps.hour ?? 0) * 60 + (comps.minute ?? 0)
    }

    static func scaleAverage(_ values: [Double], observations: [Int], method: String = dayMethod) -> AnalyticsScaleAverage {
        scaleAverage(values.map(Optional.some), observations: observations, method: method)
    }

    static func scaleAverage(_ values: [Double?], observations: [Int], method: String = dayMethod) -> AnalyticsScaleAverage {
        let present = zip(values, observations).compactMap { value, count -> (Double, Int)? in
            guard let value else { return nil }
            return (value, count)
        }
        let average = present.isEmpty ? nil : present.map(\.0).reduce(0, +) / Double(present.count)
        return AnalyticsScaleAverage(
            average: average,
            dayCount: present.count,
            observationCount: present.reduce(0) { $0 + $1.1 },
            confidence: AnalyticsConfidence(independentCount: present.count),
            method: method
        )
    }

    static func countDays(in interval: DateInterval, calendar: Calendar) -> Int {
        var day = interval.start
        var count = 0
        while day < interval.end {
            count += 1
            day = calendar.date(byAdding: .day, value: 1, to: day) ?? interval.end
        }
        return count
    }

    static func formatDay(_ date: Date, _ calendar: Calendar) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = AppLanguage.current.locale
        formatter.timeZone = calendar.timeZone
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }

    static func nearestMood(
        in checkIns: [AnalyticsCheckInFact],
        around date: Date,
        window: TimeInterval,
        after: Bool
    ) -> Double? {
        if after {
            return firstCheckIn(in: checkIns, after: date, window: window, where: { _ in true })?.mood
        }
        return lastCheckIn(in: checkIns, before: date, window: window, where: { _ in true })?.mood
    }

    static func lastCheckIn(
        in items: [AnalyticsCheckInFact],
        before date: Date,
        window: TimeInterval,
        where predicate: (AnalyticsCheckInFact) -> Bool
    ) -> AnalyticsCheckInFact? {
        var match: AnalyticsCheckInFact?
        for item in items {
            if item.timestamp > date { break }
            if date.timeIntervalSince(item.timestamp) <= window, predicate(item) {
                match = item
            }
        }
        return match
    }

    static func firstCheckIn(
        in items: [AnalyticsCheckInFact],
        after date: Date,
        window: TimeInterval,
        where predicate: (AnalyticsCheckInFact) -> Bool
    ) -> AnalyticsCheckInFact? {
        for item in items {
            if item.timestamp < date { continue }
            if item.timestamp.timeIntervalSince(date) > window { break }
            if predicate(item) { return item }
        }
        return nil
    }

    static func last(
        in items: [AnalyticsHungerFact],
        before date: Date,
        window: TimeInterval,
        where predicate: (AnalyticsHungerFact) -> Bool
    ) -> AnalyticsHungerFact? {
        var match: AnalyticsHungerFact?
        for item in items {
            if item.eventDate > date { break }
            if date.timeIntervalSince(item.eventDate) <= window, predicate(item) {
                match = item
            }
        }
        return match
    }

    static func first(
        in items: [AnalyticsCheckInFact],
        after date: Date,
        window: TimeInterval,
        where predicate: (AnalyticsCheckInFact) -> Bool
    ) -> AnalyticsCheckInFact? {
        firstCheckIn(in: items, after: date, window: window, where: predicate)
    }

    static func last(
        in items: [AnalyticsCheckInFact],
        before date: Date,
        window: TimeInterval,
        where predicate: (AnalyticsCheckInFact) -> Bool
    ) -> AnalyticsCheckInFact? {
        lastCheckIn(in: items, before: date, window: window, where: predicate)
    }

    static func shouldPublish(token: Int, generation: Int) -> Bool {
        token == generation
    }
}
