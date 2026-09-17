import SwiftUI

struct SleepAnalyticsView: View {
    let snapshot: AnalyticsSnapshot

    var body: some View {
        let sleep = snapshot.sleep
        ScrollView {
            LazyVStack(spacing: 16) {
                if sleep.nightCount == 0 {
                    AnalyticsEmptyCard(
                        title: L("Данных о сне пока нет", "No sleep data yet"),
                        message: L("Подключить Apple Health или добавить сон вручную можно в Дневнике.", "Connect Apple Health or add sleep by hand in the Diary.")
                    )
                } else {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            AnalyticsStatTile(title: L("Средний сон", "Average sleep"), value: analyticsDuration(sleep.averageSeconds))
                            AnalyticsStatTile(title: L("Медиана", "Median"), value: analyticsDuration(sleep.medianSeconds))
                        }
                        HStack {
                            AnalyticsStatTile(title: L("Короткая ночь", "Short night"), value: analyticsDuration(sleep.shortestSeconds))
                            AnalyticsStatTile(title: L("Длинная ночь", "Long night"), value: analyticsDuration(sleep.longestSeconds))
                        }
                        Text(L("По \(sleep.nightCount) ночам. Единица: ночь.", "From \(sleep.nightCount) nights. Unit: night."))
                            .font(.lora(12))
                            .foregroundStyle(AppTheme.inkSoft)
                    }
                    .padding(18)
                    .parchmentCard()

                    VStack(alignment: .leading, spacing: 6) {
                        Text(L("Качество и регулярность", "Quality and regularity"))
                            .font(.lora(16, weight: .semibold)).foregroundStyle(AppTheme.ink)
                        Text(L("Качество: \(analyticsFormat(sleep.averageQuality))", "Quality: \(analyticsFormat(sleep.averageQuality))"))
                            .font(.lora(14)).foregroundStyle(AppTheme.ink)
                        if let awakenings = sleep.averageAwakenings {
                            Text(L("Пробуждения: \(String(format: "%.1f", awakenings))", "Awakenings: \(String(format: "%.1f", awakenings))"))
                                .font(.lora(14)).foregroundStyle(AppTheme.ink)
                        }
                        if let bed = sleep.bedtimeSpreadSeconds {
                            Text(L("Разброс засыпания: \(analyticsDuration(bed))", "Bedtime spread: \(analyticsDuration(bed))"))
                                .font(.lora(14)).foregroundStyle(AppTheme.ink)
                        }
                        if let wake = sleep.wakeSpreadSeconds {
                            Text(L("Разброс пробуждения: \(analyticsDuration(wake))", "Wake spread: \(analyticsDuration(wake))"))
                                .font(.lora(14)).foregroundStyle(AppTheme.ink)
                        }
                        Text(L("Дневной сон: \(sleep.napCount) · \(analyticsDuration(sleep.averageNapSeconds))", "Naps: \(sleep.napCount) · \(analyticsDuration(sleep.averageNapSeconds))"))
                            .font(.lora(14)).foregroundStyle(AppTheme.ink)
                    }
                    .padding(18)
                    .parchmentCard()

                    if sleep.stagedNightCount > 0 {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(L("Стадии сна", "Sleep stages"))
                                .font(.lora(16, weight: .semibold)).foregroundStyle(AppTheme.ink)
                            Text(L("Глубокий: \(analyticsDuration(sleep.averageDeepSeconds)) · \(Int(((sleep.averageDeepShare ?? 0) * 100).rounded()))% общего сна", "Deep: \(analyticsDuration(sleep.averageDeepSeconds)) · \(Int(((sleep.averageDeepShare ?? 0) * 100).rounded()))% of total sleep"))
                                .font(.lora(14)).foregroundStyle(AppTheme.ink)
                            Text(L("REM \(analyticsDuration(sleep.averageREMSeconds)) · основной \(analyticsDuration(sleep.averageCoreSeconds))", "REM \(analyticsDuration(sleep.averageREMSeconds)) · core \(analyticsDuration(sleep.averageCoreSeconds))"))
                                .font(.lora(13)).foregroundStyle(AppTheme.inkSoft)
                            Text(L("По \(sleep.stagedNightCount) ночам с подробными стадиями. Минуты и доля считаются отдельно — больше минут глубокого сна не значит «лучше», если ночь длиннее.", "From \(sleep.stagedNightCount) nights with detailed stages. Minutes and share are counted separately — more deep-sleep minutes is not “better” if the night is longer."))
                                .font(.lora(12)).foregroundStyle(AppTheme.inkSoft)
                        }
                        .padding(18)
                        .parchmentCard()
                    }

                    if sleep.previousNightCount > 0 {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(L("С прошлым периодом", "Versus the previous period"))
                                .font(.lora(16, weight: .semibold)).foregroundStyle(AppTheme.ink)
                            Text(L("сейчас \(analyticsDuration(sleep.averageSeconds)) · \(sleep.nightCount) ночей", "now \(analyticsDuration(sleep.averageSeconds)) · \(sleep.nightCount) nights"))
                                .font(.lora(14)).foregroundStyle(AppTheme.ink)
                            Text(L("раньше \(analyticsDuration(sleep.previousAverageSeconds)) · \(sleep.previousNightCount) ночей", "before \(analyticsDuration(sleep.previousAverageSeconds)) · \(sleep.previousNightCount) nights"))
                                .font(.lora(13)).foregroundStyle(AppTheme.inkSoft)
                        }
                        .padding(18)
                        .parchmentCard()
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text(L("День после ночи", "The day after the night"))
                            .font(.lora(16, weight: .semibold)).foregroundStyle(AppTheme.ink)
                        ForEach(sleep.moodAfter) { bucket in
                            bucketRow(bucket)
                        }
                    }
                    .padding(18)
                    .parchmentCard()

                    if sleep.cycleBuckets.contains(where: { $0.nightCount > 0 }) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(L("По фазам цикла", "By cycle phase"))
                                .font(.lora(16, weight: .semibold)).foregroundStyle(AppTheme.ink)
                            ForEach(sleep.cycleBuckets) { bucket in
                                bucketRow(bucket)
                            }
                        }
                        .padding(18)
                        .parchmentCard()
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 24)
        }
    }

    private func bucketRow(_ bucket: AnalyticsSleepBucket) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(bucket.label) · \(bucket.nightCount) " + L("ночей", "nights"))
                .font(.lora(14, weight: .medium)).foregroundStyle(AppTheme.ink)
            Text(L("настроение \(analyticsFormat(bucket.mood.average)) · энергия \(analyticsFormat(bucket.energy.average)) · аппетит \(analyticsFormat(bucket.appetite.average))", "mood \(analyticsFormat(bucket.mood.average)) · energy \(analyticsFormat(bucket.energy.average)) · appetite \(analyticsFormat(bucket.appetite.average))"))
                .font(.lora(12)).foregroundStyle(AppTheme.inkSoft)
            AnalyticsReliabilityBadge(confidence: bucket.mood.confidence)
        }
    }
}
