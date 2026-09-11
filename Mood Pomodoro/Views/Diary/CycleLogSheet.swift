//
//  CycleLogSheet.swift
//  Mood Pomodoro
//

import SwiftUI

/// Marks menstruation on any day — today or one remembered later — or on a
/// run of days at once. Cycle day is always counted from the recorded start
/// date, never from when the mark was made. Nothing to predict, nothing to
/// diagnose, and nothing that has to be filled in for the rest of the app
/// to work.
struct CycleLogSheet: View {
    @Environment(CycleStore.self) private var cycleStore
    @Environment(\.dismiss) private var dismiss

    @State private var day: Date
    @State private var marksRange = false
    @State private var rangeEnd: Date
    @State private var firstDayIsStart = true

    private let calendar = Calendar.current

    init(date: Date) {
        let day = Calendar.current.startOfDay(for: min(date, .now))
        _day = State(initialValue: day)
        _rangeEnd = State(initialValue: day)
    }

    private var existing: [CycleEventKind] { cycleStore.events(on: day) }

    private var rangeDayCount: Int {
        let start = calendar.startOfDay(for: day)
        let end = calendar.startOfDay(for: max(rangeEnd, day))
        return (calendar.dateComponents([.day], from: start, to: end).day ?? 0) + 1
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AppTheme.parchmentCard.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        DiaryFormSection(L("День", "Day")) {
                            DatePicker(L("День", "Day"), selection: $day, in: ...Date.now, displayedComponents: .date)
                                .diaryPicker()
                            if let cycleDay = cycleStore.cycleDay(for: day) {
                                Text(L("День цикла: \(cycleDay)", "Cycle day: \(cycleDay)"))
                                    .font(.lora(15, weight: .medium))
                                    .foregroundStyle(AppTheme.ink)
                            }
                        }

                        DiaryFormSection(L("Отметить этот день", "Mark this day")) {
                            VStack(spacing: 10) {
                                ForEach(CycleEventKind.allCases, id: \.self) { kind in
                                    Button {
                                        cycleStore.log(kind, on: day)
                                        dismiss()
                                    } label: {
                                        HStack(spacing: 12) {
                                            Text(kind.icon).font(.system(size: 20))
                                            Text(kind.label)
                                                .font(.lora(15, weight: .medium))
                                                .foregroundStyle(AppTheme.ink)
                                            Spacer()
                                            if existing.contains(kind) {
                                                Image(systemName: "checkmark").foregroundStyle(AppTheme.forest)
                                            }
                                        }
                                        .diaryField(highlighted: existing.contains(kind))
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }

                        DiaryFormSection(L("Несколько дней", "Several days")) {
                            Toggle(L("Отметить сразу несколько дней", "Mark several days at once"), isOn: $marksRange)
                                .font(.lora(15))
                                .foregroundStyle(AppTheme.ink)
                                .tint(AppTheme.forest)
                            if marksRange {
                                HStack(spacing: 12) {
                                    Text(L("по", "until"))
                                        .font(.lora(15))
                                        .foregroundStyle(AppTheme.inkSoft)
                                    DatePicker(L("по", "until"), selection: $rangeEnd, in: day...Date.now, displayedComponents: .date)
                                        .diaryPicker()
                                }
                                Toggle(L("Первый день — начало", "First day is the start"), isOn: $firstDayIsStart)
                                    .font(.lora(15))
                                    .foregroundStyle(AppTheme.ink)
                                    .tint(AppTheme.forest)
                                Button(L("Отметить \(rangeDayCount) дн.", "Mark \(rangeDayCount) days")) {
                                    cycleStore.logPeriod(from: day, through: rangeEnd, firstDayIsStart: firstDayIsStart)
                                    dismiss()
                                }
                                .buttonStyle(.goblinPrimary)
                            }
                        }

                        if !existing.isEmpty {
                            Button(L("Убрать отметку за этот день", "Remove this day's mark")) {
                                cycleStore.clear(on: day)
                                dismiss()
                            }
                            .font(.lora(14))
                            .foregroundStyle(AppTheme.rustDeep)
                        }

                        DiaryNote(text: L("Это личный контекст для наблюдений. Приложение ничего не предсказывает и не ставит диагнозов.", "This is personal context for your observations. The app doesn't predict anything or make diagnoses."))
                    }
                    .padding(20)
                }
            }
            .onChange(of: day) { _, newDay in
                if rangeEnd < newDay { rangeEnd = newDay }
            }
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text(L("🌸 Цикл", "🌸 Cycle"))
                        .font(.lora(17, weight: .semibold))
                        .foregroundStyle(AppTheme.ink)
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button(L("Закрыть", "Close")) { dismiss() }
                        .font(.lora(15))
                        .foregroundStyle(AppTheme.forest)
                }
            }
        }
        .presentationDetents([.large])
    }
}
