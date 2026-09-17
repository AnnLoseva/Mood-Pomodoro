//
//  SleepEntrySheet.swift
//  Mood Pomodoro
//

import SwiftUI

/// "🌙 Сон вручную" — for the nights the watch missed, wasn't worn, or never
/// recorded.
///
/// Two rules this form keeps:
/// * It **never writes back to HealthKit.** The integration is read-only;
///   the app has no business putting its own estimate into the user's health
///   record, and Apple asks that apps not write data they didn't measure.
/// * It **warns instead of adding up.** If Apple Health already describes
///   sleep overlapping this stretch, saying so is the honest move — silently
///   keeping both would report sixteen hours for one night.
struct SleepEntrySheet: View {
    @Environment(SleepStore.self) private var store

    /// The `deterministicKey` of a manual entry being edited.
    let editingID: String?

    @State private var wakeDay: Date
    @State private var fellAsleep: Date
    @State private var wokeUp: Date
    @State private var kind: SleepKind = .night
    @State private var note = ""
    @State private var quality: SleepQuality?
    @State private var loaded = false

    init(editingID: String?, day: Date) {
        self.editingID = editingID
        let calendar = Calendar.current
        let base = DiaryDefaults.defaultMoment(on: day)
        _wakeDay = State(initialValue: calendar.startOfDay(for: base))
        _fellAsleep = State(initialValue: calendar.date(bySettingHour: 0, minute: 20, second: 0, of: base) ?? base)
        _wokeUp = State(initialValue: calendar.date(bySettingHour: 8, minute: 10, second: 0, of: base) ?? base)
    }

    private let calendar = Calendar.current

    /// The wake-up moment is on the chosen day; falling asleep is on that day
    /// too, or the evening before when the clock time is later — which is
    /// what "легла в 23:40, проснулась в 8:10" means.
    private var wokeUpDate: Date { DiaryDefaults.combine(day: wakeDay, time: wokeUp) }

    private var fellAsleepDate: Date {
        let sameDay = DiaryDefaults.combine(day: wakeDay, time: fellAsleep)
        guard sameDay >= wokeUpDate else { return sameDay }
        return calendar.date(byAdding: .day, value: -1, to: sameDay) ?? sameDay
    }

    private var duration: TimeInterval { wokeUpDate.timeIntervalSince(fellAsleepDate) }

    private var problem: String? {
        if duration < SleepAggregationService.minimumSessionDuration {
            return L("Слишком короткий промежуток.", "That stretch is too short.")
        }
        if duration > 24 * 60 * 60 {
            return L("Больше суток — наверное, что-то не так со временем.", "More than a day — the times are probably off.")
        }
        if wokeUpDate > .now { return L("Это время ещё не наступило.", "That time hasn't come yet.") }
        return nil
    }

    /// Apple Health may already describe this stretch. Shown as information,
    /// not a block — she is allowed to add her own record anyway.
    private var overlapping: SleepSessionSummary? {
        guard problem == nil else { return nil }
        return store.importedSleepOverlaps(start: fellAsleepDate, end: wokeUpDate, ignoring: editingID)
    }

    var body: some View {
        DiaryFormScaffold(
            title: L("🌙 Сон вручную", "🌙 Sleep by hand"),
            canSave: problem == nil,
            hint: problem,
            onSave: save,
            onDelete: deleteAction
        ) {
            DiaryFormSection(L("Дата пробуждения", "Day you woke up")) {
                DatePicker(L("Дата", "Date"), selection: $wakeDay, in: ...Date.now, displayedComponents: .date)
                    .diaryPicker()
                DiaryNote(text: L("Сон записывается на тот день, в который ты проснулась.", "Sleep is filed under the day you woke up."))
            }

            HStack(spacing: 16) {
                DiaryFormSection(L("Легла", "Fell asleep")) {
                    DatePicker(L("Легла", "Fell asleep"), selection: $fellAsleep, displayedComponents: .hourAndMinute)
                        .diaryPicker()
                }
                DiaryFormSection(L("Проснулась", "Woke up")) {
                    DatePicker(L("Проснулась", "Woke up"), selection: $wokeUp, displayedComponents: .hourAndMinute)
                        .diaryPicker()
                }
            }

            if problem == nil {
                HStack(spacing: 8) {
                    Text(L("Получается", "That's"))
                        .font(.lora(14))
                        .foregroundStyle(AppTheme.inkSoft)
                    Text(DurationFormatting.compact(duration))
                        .font(.lora(18, weight: .semibold))
                        .foregroundStyle(AppTheme.ink)
                    if fellAsleepDate < calendar.startOfDay(for: wokeUpDate) {
                        Text(L("· через полночь", "· across midnight"))
                            .font(.lora(12))
                            .foregroundStyle(AppTheme.inkSoft)
                    }
                }
            }

            DiaryFormSection(L("Что это было", "Which was it")) {
                FlowLayout(spacing: 8) {
                    ForEach([SleepKind.night, SleepKind.nap], id: \.rawValue) { option in
                        DiaryChip(title: "\(option.emoji) \(option.label)", isSelected: kind == option) {
                            kind = option
                        }
                    }
                }
            }

            if let overlapping {
                DiaryFormSection(L("Уже есть в Apple Health", "Already in Apple Health")) {
                    SleepSessionBlock(session: overlapping)
                    DiaryNote(text: L("Ручная запись заменит пересекающуюся запись Apple Health целиком в итогах. Обе записи сохранятся.", "The manual entry replaces the entire overlapping Apple Health record in totals. Both records are retained."))
                }
            }

            SleepQualityPicker(selection: $quality)
            DiaryFormSection(L("Заметка", "Note")) {
                TextField(L("Необязательно", "Optional"), text: $note, axis: .vertical)
                    .font(.lora(15))
                    .diaryField()
            }

            DiaryNote(text: L("Эта запись остаётся в приложении — в Apple Health она не записывается.", "This entry stays in the app — it is never written into Apple Health."))
        }
        .onAppear(perform: load)
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        guard let editingID, let record = store.manualRecord(key: editingID) else { return }
        wakeDay = calendar.startOfDay(for: record.endDate)
        fellAsleep = record.startDate
        wokeUp = record.endDate
        kind = record.kind
        note = record.note ?? ""
        quality = record.quality
    }

    private func save() {
        let text = DiaryDefaults.trimmed(note)
        if let editingID, store.manualRecord(key: editingID) != nil {
            store.updateManualSleep(
                id: editingID,
                start: fellAsleepDate,
                end: wokeUpDate,
                kind: kind,
                quality: quality,
                note: text
            )
        } else {
            store.addManualSleep(start: fellAsleepDate, end: wokeUpDate, kind: kind, quality: quality, note: text)
        }
    }

    /// Only an existing record can be deleted.
    private var deleteAction: (() -> Void)? {
        guard editingID != nil else { return nil }
        return delete
    }

    private func delete() {
        guard let editingID else { return }
        store.deleteSleep(id: editingID)
    }
}

struct SleepQualityPicker: View {
    @Binding var selection: SleepQuality?
    var body: some View {
        DiaryFormSection(L("Как спалось?", "How did you sleep?")) {
            FlowLayout(spacing: 6) {
                ForEach(SleepQuality.orderedCases, id: \.rawValue) { quality in
                    DiaryChip(title: quality.label, isSelected: selection == quality) {
                        selection = selection == quality ? nil : quality
                    }
                }
            }
        }
    }
}

struct SleepEditorRoute: View {
    @Environment(SleepStore.self) private var store
    let editingID: String?
    let day: Date
    var body: some View {
        if let id = editingID, let sleep = store.sessions.first(where: { $0.id == id }), sleep.source == .healthKit {
            NavigationStack {
                ScrollView { SleepSessionBlock(session: sleep).padding(20) }
                    .background(AppTheme.parchmentCard)
                    .navigationTitle(L("Сон из Apple Health", "Apple Health sleep"))
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbarColorScheme(.light, for: .navigationBar)
            }
            .goblinChrome()
        } else { SleepEntrySheet(editingID: editingID, day: day) }
    }
}
