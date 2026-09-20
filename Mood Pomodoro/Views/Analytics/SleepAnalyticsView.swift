import SwiftUI

/// Сон: a chart of the nights, the average and how many nights it rests on —
/// and the rest (quality, regularity, stages, the period before, the day
/// after a night, cycle phases) in sections that open on request.
struct SleepAnalyticsView: View {
    @Bindable var store: AnalyticsStore

    var body: some View {
        let snapshot = store.snapshot
        let sleep = snapshot.sleep
        let series = AnalyticsChartSeries.make(metric: .sleep, days: snapshot.days)

        AnalyticsDetailScaffold(title: AnalyticsSection.sleep.title, store: store) {
            if sleep.nightCount == 0 {
                AnalyticsEmptyCard(
                    title: L("Данных о сне пока нет", "No sleep data yet"),
                    message: L("Подключить Apple Health или добавить сон вручную можно в Дневнике.", "Connect Apple Health or add sleep by hand in the Diary.")
                )
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        AnalyticsStatTile(title: L("Средний сон", "Average sleep"), value: analyticsDuration(sleep.averageSeconds))
                        AnalyticsStatTile(title: L("Ночей с данными", "Nights with data"), value: "\(sleep.nightCount)")
                        AnalyticsInfoButton(text: L(
                            "Средняя длительность ночного сна по ночам периода. Единица — ночь; дневной сон считается отдельно.",
                            "Mean length of night sleep over the nights of the period. The unit is a night; naps are counted separately."
                        ))
                    }
                    AnalyticsMetricChart(series: [series], interval: snapshot.interval, height: 200)
                }
                .padding(16)
                .parchmentCard(padding: 0)

                VStack(alignment: .leading, spacing: 0) {
                    AnalyticsRouteRow(title: L("Ночи", "Nights"), subtitle: L("каждая запись отдельно", "each record on its own"), route: .nights)
                }
                .padding(.horizontal, 16)
                .parchmentCard(padding: 0)

                AnalyticsDisclosure(L("Длительность", "Length"), summary: analyticsDuration(sleep.medianSeconds)) {
                    VStack(alignment: .leading, spacing: 8) {
                        row(L("Медиана", "Median"), analyticsDuration(sleep.medianSeconds))
                        row(L("Самая короткая ночь", "Shortest night"), analyticsDuration(sleep.shortestSeconds))
                        row(L("Самая длинная ночь", "Longest night"), analyticsDuration(sleep.longestSeconds))
                        row(L("Дневной сон", "Naps"), "\(sleep.napCount) · \(analyticsDuration(sleep.averageNapSeconds))")
                    }
                }

                AnalyticsDisclosure(L("Качество и регулярность", "Quality and regularity")) {
                    VStack(alignment: .leading, spacing: 8) {
                        row(L("Качество", "Quality"), analyticsFormat(sleep.averageQuality))
                        if let awakenings = sleep.averageAwakenings {
                            row(L("Пробуждения за ночь", "Awakenings per night"), String(format: "%.1f", awakenings))
                        }
                        if let bed = sleep.bedtimeSpreadSeconds {
                            row(L("Разброс засыпания", "Bedtime spread"), analyticsDuration(bed))
                        }
                        if let wake = sleep.wakeSpreadSeconds {
                            row(L("Разброс пробуждения", "Wake-up spread"), analyticsDuration(wake))
                        }
                    }
                }

                if sleep.stagedNightCount > 0 {
                    AnalyticsDisclosure(L("Стадии сна", "Sleep stages"), summary: L("\(sleep.stagedNightCount) ноч.", "\(sleep.stagedNightCount) nights")) {
                        VStack(alignment: .leading, spacing: 8) {
                            row(L("Глубокий", "Deep"), "\(analyticsDuration(sleep.averageDeepSeconds)) · \(Int(((sleep.averageDeepShare ?? 0) * 100).rounded()))%")
                            row("REM", analyticsDuration(sleep.averageREMSeconds))
                            row(L("Основной", "Core"), analyticsDuration(sleep.averageCoreSeconds))
                            Text(L("Только ночи с подробными стадиями. Минуты и доля — разные величины.", "Only nights with detailed stages. Minutes and share are different quantities."))
                                .font(.lora(11)).foregroundStyle(AppTheme.inkSoft)
                        }
                    }
                }

                if sleep.previousNightCount > 0 {
                    AnalyticsDisclosure(L("С прошлым периодом", "Versus the previous period")) {
                        VStack(alignment: .leading, spacing: 8) {
                            row(L("Сейчас", "Now"), "\(analyticsDuration(sleep.averageSeconds)) · " + L("\(sleep.nightCount) ноч.", "\(sleep.nightCount) nights"))
                            row(L("Раньше", "Before"), "\(analyticsDuration(sleep.previousAverageSeconds)) · " + L("\(sleep.previousNightCount) ноч.", "\(sleep.previousNightCount) nights"))
                        }
                    }
                }

                AnalyticsDisclosure(L("День после ночи", "The day after the night")) {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(sleep.moodAfter) { bucketRow($0) }
                    }
                }

                if sleep.cycleBuckets.contains(where: { $0.nightCount > 0 }) {
                    AnalyticsDisclosure(L("По фазам цикла", "By cycle phase")) {
                        VStack(alignment: .leading, spacing: 10) {
                            ForEach(sleep.cycleBuckets) { bucketRow($0) }
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 0) {
                    AnalyticsRouteRow(title: L("Сравнить сон с другим показателем", "Compare sleep with another metric"), route: .section(.compare))
                }
                .padding(.horizontal, 16)
                .parchmentCard(padding: 0)
            }
        }
    }

    private func row(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title).font(.lora(14)).foregroundStyle(AppTheme.ink)
            Spacer(minLength: 8)
            Text(value).font(.lora(14, weight: .semibold)).foregroundStyle(AppTheme.ink)
        }
    }

    private func bucketRow(_ bucket: AnalyticsSleepBucket) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(bucket.label) · " + countLabel(bucket.nightCount, ru: ("ночь", "ночи", "ночей"), en: ("night", "nights")))
                .font(.lora(14, weight: .medium)).foregroundStyle(AppTheme.ink)
            Text(L(
                "настроение \(analyticsFormat(bucket.mood.average)) · энергия \(analyticsFormat(bucket.energy.average)) · аппетит \(analyticsFormat(bucket.appetite.average))",
                "mood \(analyticsFormat(bucket.mood.average)) · energy \(analyticsFormat(bucket.energy.average)) · appetite \(analyticsFormat(bucket.appetite.average))"
            ))
            .font(.lora(12)).foregroundStyle(AppTheme.inkSoft)
            AnalyticsReliabilityBadge(confidence: bucket.mood.confidence)
        }
    }
}
