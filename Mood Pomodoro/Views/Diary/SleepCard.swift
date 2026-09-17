//
//  SleepCard.swift
//  Mood Pomodoro
//

import SwiftUI

/// The day's 🌙 Сон card, plus the stage bar and the Apple Health connect
/// row that live only here.
///
/// Three things this card is careful about:
/// * **No data is never "you didn't sleep".** HealthKit withholds read
///   permission state on purpose, so an empty night can mean no watch, no
///   permission, or nothing recorded. It always says "нет данных".
/// * **No grades.** Stage durations are shown as they were recorded. The app
///   never says a night was poor, never calls REM insufficient, and never
///   names a sleep disorder.
/// * **It says sleep stays on this device**, because it does — health data
///   is kept out of iCloud, so the iPad reads it from Health itself.

struct SleepCard: View {
    let summary: SleepDaySummary
    let isConnected: Bool
    let isAvailable: Bool
    let isImporting: Bool
    /// True when the app reads something Health was never asked about.
    var needsAdditionalPermission: Bool = false
    let onConnect: () -> Void
    let onRefresh: () -> Void
    let onAddManual: () -> Void
    let onEdit: (String) -> Void

    var body: some View {
        DiaryCard(title: L("🌙 Сон", "🌙 Sleep")) {
            VStack(alignment: .leading, spacing: 14) {
                if summary.isEmpty {
                    emptyState
                } else {
                    ForEach(summary.sessions) { session in
                        SleepSessionBlock(session: session, onEdit: onEdit)
                        if session.id != summary.sessions.last?.id {
                            Divider().background(AppTheme.border)
                        }
                    }
                    if summary.sessions.count > 1 {
                        Divider().background(AppTheme.border)
                        HStack {
                            Text(L("Всего за день", "Total for the day"))
                                .font(.lora(14))
                                .foregroundStyle(AppTheme.inkSoft)
                            Spacer(minLength: 8)
                            Text(DurationFormatting.compact(summary.totalSleep))
                                .font(.lora(16, weight: .semibold))
                                .foregroundStyle(AppTheme.ink)
                        }
                    }
                }
                actions
            }
        }
    }

    /// Absence of a HealthKit sample is absence of a *record* — never a
    /// statement about the night itself.
    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(isConnected
                 ? L("Нет данных из Apple Health за эту ночь.", "No Apple Health data for this night.")
                 : L("Apple Health не подключён.", "Apple Health isn't connected."))
                .font(.lora(15))
                .foregroundStyle(AppTheme.inkSoft)
            DiaryNote(text: isConnected
                      ? L("Это значит только, что записи нет — например, часы не были надеты. Можно добавить сон вручную.", "That only means there's no record — the watch may not have been worn. You can add sleep by hand.")
                      : L("Если подключить, приложение будет само показывать сон с Apple Watch и дни цикла из Health.", "Once connected, the app will show sleep from your Apple Watch and cycle days from Health on its own."))
        }
    }

    private var actions: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 14) {
                if isAvailable && !isConnected {
                    Button(L("Подключить Apple Health", "Connect Apple Health"), action: onConnect)
                        .font(.lora(13, weight: .medium))
                        .foregroundStyle(AppTheme.forest)
                        .buttonStyle(.plain)
                } else if isConnected {
                    Button(isImporting ? L("Обновляю…", "Refreshing…") : L("Обновить", "Refresh"), action: onRefresh)
                        .font(.lora(13, weight: .medium))
                        .foregroundStyle(AppTheme.forest)
                        .buttonStyle(.plain)
                        .disabled(isImporting)
                }
                Button(L("Добавить вручную", "Add by hand"), action: onAddManual)
                    .font(.lora(13, weight: .medium))
                    .foregroundStyle(AppTheme.forest)
                    .buttonStyle(.plain)
                Spacer(minLength: 0)
            }
            if !isAvailable {
                DiaryNote(text: L("Apple Health недоступен на этом устройстве.", "Apple Health isn't available on this device."))
            } else if isConnected, needsAdditionalPermission {
                DiaryNote(text: L("Приложение теперь умеет читать ещё и дни цикла — нажми «Обновить», чтобы Health спросил про них.", "The app can now also read cycle days — tap “Refresh” and Health will ask about them."))
            } else if isConnected {
                DiaryNote(text: L("Сон и дни цикла читаются из Apple Health на этом устройстве и не выгружаются в iCloud — поэтому на iPad они появятся, только если Health есть и там.", "Sleep and cycle days are read from Apple Health on this device and never uploaded to iCloud — so they show on the iPad only if Health has them there too."))
            }
        }
    }
}

/// One night or nap: when, how long, its stages, and where it came from.
struct SleepSessionBlock: View {
    @Environment(SleepStore.self) private var store
    let session: SleepSessionSummary
    var onEdit: ((String) -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if session.source == .healthKit {
                SleepQualityPicker(selection: Binding(get: { store.sessions.first { $0.id == session.id }?.quality }, set: { store.setQuality($0, forSleepID: session.id) }))
            }
            if let quality = session.quality { Text(quality.label).font(.lora(13)) }
            if session.isSuperseded {
                DiaryNote(text: L("Пересечение: исключено из итогов", "Overlap: excluded from totals"))
            }
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(session.kind.emoji) \(session.kind.label)")
                        .font(.lora(14, weight: .medium))
                        .foregroundStyle(AppTheme.ink)
                    Text(session.timeRange)
                        .font(.lora(13).monospacedDigit())
                        .foregroundStyle(AppTheme.inkSoft)
                }
                Spacer(minLength: 8)
                Text(DurationFormatting.compact(session.totalSleep))
                    .font(.lora(20, weight: .semibold))
                    .foregroundStyle(AppTheme.ink)
                if session.source == .manual, let onEdit {
                    Button { onEdit(session.id) } label: {
                        Image(systemName: "pencil")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(AppTheme.inkSoft)
                    }
                    .buttonStyle(.plain)
                }
            }

            if !session.intervals.isEmpty {
                SleepStageBar(intervals: session.intervals, start: session.start, end: session.end)
            }

            if session.hasStageDetail {
                FlowLayout(spacing: 10) {
                    ForEach(SleepStage.displayOrder.filter { session.duration(of: $0) > 0 }) { stage in
                        HStack(spacing: 5) {
                            RoundedRectangle(cornerRadius: 3, style: .continuous)
                                .fill(stage.color)
                                .frame(width: 10, height: 10)
                            Text("\(stage.label) \(DurationFormatting.compact(session.duration(of: stage)))")
                                .font(.lora(12))
                                .foregroundStyle(AppTheme.inkSoft)
                        }
                    }
                }
            }

            if !detailLine.isEmpty {
                Text(detailLine)
                    .font(.lora(12))
                    .foregroundStyle(AppTheme.inkSoft)
            }
        }
    }

    /// Time in bed, awakenings and the recording source — stated, never
    /// interpreted.
    private var detailLine: String {
        var parts: [String] = []
        if let inBed = session.timeInBed {
            parts.append(L("в постели \(DurationFormatting.compact(inBed))", "in bed \(DurationFormatting.compact(inBed))"))
        }
        if let count = session.awakeningCount, count > 0 {
            parts.append(countLabel(count, ru: ("пробуждение", "пробуждения", "пробуждений"), en: ("awakening", "awakenings")))
        }
        if session.source == .manual {
            parts.append(SleepSource.manual.label.lowercased())
        } else if let name = session.sourceName {
            parts.append(name)
        }
        return parts.joined(separator: " · ")
    }
}

/// The night as one horizontal band, each stage in its place on the clock.
/// Readable at a glance and deliberately not a clinical hypnogram — it shows
/// what was recorded, at the real timestamps, and says nothing about it.
struct SleepStageBar: View {
    let intervals: [SleepInterval]
    let start: Date
    let end: Date

    private var span: TimeInterval { max(1, end.timeIntervalSince(start)) }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(AppTheme.chipFill)
                    ForEach(intervals, id: \.self) { interval in
                        let offset = interval.start.timeIntervalSince(start) / span * proxy.size.width
                        let width = interval.duration / span * proxy.size.width
                        Rectangle()
                            .fill(interval.stage.color)
                            .frame(width: max(1, width))
                            .offset(x: offset)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            }
            .frame(height: 22)
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(AppTheme.border, lineWidth: 1)
            )
            HStack {
                Text(DateFormatting.time(start))
                Spacer()
                Text(DateFormatting.time(end))
            }
            .font(.lora(10).monospacedDigit())
            .foregroundStyle(AppTheme.inkSoft)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L("Стадии сна с \(DateFormatting.time(start)) до \(DateFormatting.time(end))", "Sleep stages from \(DateFormatting.time(start)) to \(DateFormatting.time(end))"))
    }
}

extension SleepStage {
    /// A night palette that sits inside the app's parchment world: moss,
    /// muted indigo and warm brown rather than the neon blues a medical
    /// dashboard would use.
    var color: Color {
        switch self {
        case .deep: return Color(red: 0.204, green: 0.239, blue: 0.376)
        case .rem: return Color(red: 0.400, green: 0.451, blue: 0.604)
        case .core: return Color(red: 0.522, green: 0.588, blue: 0.549)
        case .unspecified: return AppTheme.moss
        case .awake: return Color(red: 0.749, green: 0.596, blue: 0.376)
        case .inBed: return AppTheme.border
        }
    }
}
