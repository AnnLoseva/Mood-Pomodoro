//
//  DiaryEntrySheets.swift
//  Mood Pomodoro
//

import SwiftUI
import SwiftData

/// "+ Добавить" and every edit in the diary. There is no separate
/// "backdated mode": each form simply has a date and a time, prefilled with
/// now (or with the day being viewed) and always editable. Whatever is
/// chosen becomes the record's event date; `createdAt` is stamped by the
/// store and never shown here.
enum DiaryEntrySheet: Identifiable {
    case activity(editing: UUID?)
    case mood(editing: UUID?)
    case support
    case cycle
    case factor(editing: UUID?)
    case note(editing: UUID?)

    var id: String {
        switch self {
        case .activity(let id): return "activity-\(id?.uuidString ?? "new")"
        case .mood(let id): return "mood-\(id?.uuidString ?? "new")"
        case .support: return "support"
        case .cycle: return "cycle"
        case .factor(let id): return "factor-\(id?.uuidString ?? "new")"
        case .note(let id): return "note-\(id?.uuidString ?? "new")"
        }
    }

    init(editing target: DiaryEditTarget) {
        switch target {
        case .session(let id): self = .activity(editing: id)
        case .checkIn(let id): self = .mood(editing: id)
        case .support: self = .support
        case .factor(let id): self = .factor(editing: id)
        case .note(let id): self = .note(editing: id)
        }
    }
}

/// Routes a `DiaryEntrySheet` to its form. `day` is the day the diary is
/// showing — new entries start there instead of on today.
struct DiaryEntrySheetView: View {
    let sheet: DiaryEntrySheet
    let day: Date

    var body: some View {
        switch sheet {
        case .activity(let id): ActivityEntrySheet(editingID: id, day: day)
        case .mood(let id): MoodEntrySheet(editingID: id, day: day)
        case .support: SupportEntrySheet(day: day)
        case .cycle: CycleLogSheet(date: day)
        case .factor(let id): FactorEntrySheet(editingID: id, day: day)
        case .note(let id): NoteEntrySheet(editingID: id, day: day)
        }
    }
}

enum DiaryDefaults {
    /// Now when looking at today; otherwise the same clock time on the
    /// viewed day (never later than now).
    static func defaultMoment(on day: Date, calendar: Calendar = .current) -> Date {
        if calendar.isDateInToday(day) { return .now }
        return min(combine(day: day, time: .now, calendar: calendar), .now)
    }

    /// The calendar day of `day` at the hour/minute of `time`.
    static func combine(day: Date, time: Date, calendar: Calendar = .current) -> Date {
        let clock = calendar.dateComponents([.hour, .minute], from: time)
        return calendar.date(bySettingHour: clock.hour ?? 0, minute: clock.minute ?? 0, second: 0, of: day) ?? day
    }

    static func trimmed(_ text: String) -> String? {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}

// MARK: - Activity

struct ActivityEntrySheet: View {
    @Environment(DiaryEntryStore.self) private var store

    let editingID: UUID?

    @State private var activity = ""
    @State private var day: Date
    @State private var start: Date
    @State private var end: Date
    @State private var note = ""
    @State private var loaded = false

    init(editingID: UUID?, day: Date) {
        self.editingID = editingID
        let moment = DiaryDefaults.defaultMoment(on: day)
        _day = State(initialValue: moment)
        _start = State(initialValue: moment.addingTimeInterval(-60 * 60))
        _end = State(initialValue: moment)
    }

    private var startDate: Date { DiaryDefaults.combine(day: day, time: start) }
    private var endDate: Date { DiaryDefaults.combine(day: day, time: end) }

    private var problem: String? {
        if endDate <= startDate { return "Конец должен быть позже начала." }
        if endDate > .now { return "Это время ещё не наступило." }
        return nil
    }

    var body: some View {
        DiaryFormScaffold(
            title: "🌿 Деятельность",
            canSave: DiaryDefaults.trimmed(activity) != nil && problem == nil,
            hint: problem,
            onSave: save,
            onDelete: deleteAction
        ) {
            DiaryFormSection("Чем занималась") {
                TextField("Например, математика", text: $activity)
                    .font(.lora(15))
                    .diaryField()
                FlowLayout(spacing: 8) {
                    ForEach(ActivityCategory.allCases) { category in
                        DiaryChip(title: category.label, isSelected: activity == category.label) {
                            activity = category.label
                        }
                    }
                }
            }
            DiaryFormSection("Дата") {
                DatePicker("Дата", selection: $day, in: ...Date.now, displayedComponents: .date)
                    .diaryPicker()
            }
            HStack(spacing: 16) {
                DiaryFormSection("Начало") {
                    DatePicker("Начало", selection: $start, displayedComponents: .hourAndMinute)
                        .diaryPicker()
                }
                DiaryFormSection("Конец") {
                    DatePicker("Конец", selection: $end, displayedComponents: .hourAndMinute)
                        .diaryPicker()
                }
            }
            DiaryFormSection("Заметка") {
                TextField("Необязательно", text: $note, axis: .vertical)
                    .font(.lora(15))
                    .diaryField()
            }
        }
        .onAppear(perform: load)
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        guard let editingID, let session = store.session(id: editingID) else { return }
        activity = session.activity
        day = session.startDate
        start = session.startDate
        end = session.endDate ?? session.startDate
        note = session.note ?? ""
    }

    private func save() {
        guard let name = DiaryDefaults.trimmed(activity) else { return }
        let text = DiaryDefaults.trimmed(note)
        if let editingID, let session = store.session(id: editingID) {
            store.updateManualActivity(session, activity: name, start: startDate, end: endDate, note: text)
        } else {
            store.addManualActivity(activity: name, start: startDate, end: endDate, note: text)
        }
    }

    /// Only an existing record can be deleted.
    private var deleteAction: (() -> Void)? {
        guard editingID != nil else { return nil }
        return delete
    }

    private func delete() {
        guard let editingID, let session = store.session(id: editingID) else { return }
        store.deleteManualActivity(session)
    }
}

// MARK: - Mood

struct MoodEntrySheet: View {
    @Environment(DiaryEntryStore.self) private var store
    @Environment(ReasonsStore.self) private var reasonsStore

    let editingID: UUID?

    @State private var moment: Date
    @State private var mood: Mood?
    @State private var reason: String?
    @State private var note = ""
    @State private var loaded = false

    init(editingID: UUID?, day: Date) {
        self.editingID = editingID
        _moment = State(initialValue: DiaryDefaults.defaultMoment(on: day))
    }

    private var reasons: [String] {
        guard let mood else { return [] }
        var list = reasonsStore.reasons(for: mood)
        if let reason, !list.contains(reason) { list.insert(reason, at: 0) }
        return list
    }

    var body: some View {
        DiaryFormScaffold(
            title: "🙂 Настроение",
            canSave: mood != nil && moment <= .now,
            hint: moment > .now ? "Это время ещё не наступило." : nil,
            onSave: save,
            onDelete: deleteAction
        ) {
            DiaryMomentPicker(moment: $moment)
            DiaryFormSection("Настроение") {
                HStack(spacing: 6) {
                    ForEach(Mood.orderedCases) { option in
                        Button {
                            if mood != option { reason = nil }
                            mood = option
                        } label: {
                            MoodImage(mood: option, size: 44)
                                .padding(6)
                                .frame(maxWidth: .infinity)
                                .background(
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .fill(mood == option ? AppTheme.forest.opacity(0.18) : Color.clear)
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .stroke(mood == option ? AppTheme.forest : AppTheme.border, lineWidth: mood == option ? 2 : 1)
                                )
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(option.label)
                    }
                }
                if let mood {
                    Text(mood.label)
                        .font(.lora(14, weight: .medium))
                        .foregroundStyle(AppTheme.ink)
                }
            }
            if mood != nil {
                DiaryFormSection("Причина") {
                    FlowLayout(spacing: 8) {
                        ForEach(reasons, id: \.self) { item in
                            DiaryChip(title: item, isSelected: reason == item) {
                                reason = reason == item ? nil : item
                            }
                        }
                    }
                }
            }
            DiaryFormSection("Заметка") {
                TextField("Необязательно", text: $note, axis: .vertical)
                    .font(.lora(15))
                    .diaryField()
            }
        }
        .onAppear(perform: load)
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        guard let editingID, let checkIn = store.checkIn(id: editingID) else { return }
        moment = checkIn.timestamp
        mood = checkIn.mood
        reason = checkIn.reason
        note = checkIn.note ?? ""
    }

    private func save() {
        guard let mood else { return }
        let text = DiaryDefaults.trimmed(note)
        if let editingID, let checkIn = store.checkIn(id: editingID) {
            store.updateMood(checkIn, mood: mood, reason: reason, note: text, at: moment)
        } else {
            store.addMood(mood, reason: reason, note: text, at: moment)
        }
    }

    /// Only an existing record can be deleted.
    private var deleteAction: (() -> Void)? {
        guard editingID != nil else { return nil }
        return delete
    }

    private func delete() {
        guard let editingID, let checkIn = store.checkIn(id: editingID) else { return }
        store.deleteCheckIn(checkIn)
    }
}

// MARK: - Daily support

/// Tracking only: the sheet records what the user says and nothing else —
/// no reminders, no "ты пропустила", no advice.
struct SupportEntrySheet: View {
    @Environment(DiaryEntryStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var day: Date
    @State private var status: SupportStatus?
    @State private var knowsTime = false
    @State private var time: Date
    @State private var note = ""
    @State private var hasExisting = false

    init(day: Date) {
        let moment = DiaryDefaults.defaultMoment(on: day)
        _day = State(initialValue: moment)
        _time = State(initialValue: moment)
    }

    var body: some View {
        DiaryFormScaffold(
            title: "💊 Поддержка",
            canSave: status != nil,
            onSave: save
        ) {
            DiaryFormSection("День") {
                DatePicker("День", selection: $day, in: ...Date.now, displayedComponents: .date)
                    .diaryPicker()
            }
            DiaryFormSection("Отметка") {
                VStack(spacing: 8) {
                    ForEach(SupportStatus.allCases) { option in
                        Button {
                            status = option
                        } label: {
                            HStack(spacing: 12) {
                                Text(option.glyph)
                                    .font(.lora(17, weight: .semibold))
                                    .frame(width: 24)
                                Text(option.label)
                                    .font(.lora(15, weight: .medium))
                                Spacer()
                                if status == option {
                                    Image(systemName: "checkmark").foregroundStyle(AppTheme.forest)
                                }
                            }
                            .foregroundStyle(AppTheme.ink)
                            .diaryField(highlighted: status == option)
                        }
                        .buttonStyle(.plain)
                    }
                }
                DiaryNote(text: "Если ничего не выбрать, день останется «не отмечен» — это не то же самое, что «не принято».")
            }
            DiaryFormSection("Время") {
                Toggle("Знаю точное время", isOn: $knowsTime)
                    .font(.lora(15))
                    .foregroundStyle(AppTheme.ink)
                    .tint(AppTheme.forest)
                if knowsTime {
                    DatePicker("Время", selection: $time, displayedComponents: .hourAndMinute)
                        .diaryPicker()
                } else {
                    DiaryNote(text: "Запишется как «в течение дня».")
                }
            }
            DiaryFormSection("Заметка") {
                TextField("Необязательно", text: $note, axis: .vertical)
                    .font(.lora(15))
                    .diaryField()
            }
            if hasExisting {
                Button("Убрать отметку за этот день") {
                    store.clearSupport(on: day)
                    dismiss()
                }
                .font(.lora(14))
                .foregroundStyle(AppTheme.rustDeep)
            }
        }
        .onAppear { load(for: day) }
        .onChange(of: day) { _, newDay in load(for: newDay) }
    }

    private func load(for day: Date) {
        if let entry = store.supportEntry(on: day) {
            status = entry.status
            knowsTime = entry.time != nil
            if let entryTime = entry.time { time = entryTime }
            note = entry.note ?? ""
            hasExisting = true
        } else {
            status = nil
            knowsTime = false
            note = ""
            hasExisting = false
        }
    }

    private func save() {
        guard let status else { return }
        store.setSupport(
            status,
            on: day,
            time: knowsTime ? DiaryDefaults.combine(day: day, time: time) : nil,
            note: DiaryDefaults.trimmed(note)
        )
    }
}

// MARK: - Factor

struct FactorEntrySheet: View {
    @Environment(DiaryEntryStore.self) private var store
    @Query(sort: \FactorCategory.sortOrder) private var categories: [FactorCategory]

    let editingID: UUID?

    @State private var moment: Date
    @State private var categoryID: UUID?
    @State private var optionID: UUID?
    @State private var loaded = false

    init(editingID: UUID?, day: Date) {
        self.editingID = editingID
        _moment = State(initialValue: DiaryDefaults.defaultMoment(on: day))
    }

    private var enabledCategories: [FactorCategory] { categories.filter(\.isEnabled) }

    var body: some View {
        DiaryFormScaffold(
            title: "☕ Фактор",
            canSave: selection != nil && moment <= .now,
            hint: moment > .now ? "Это время ещё не наступило." : nil,
            onSave: save,
            onDelete: deleteAction
        ) {
            DiaryMomentPicker(moment: $moment)
            ForEach(enabledCategories) { category in
                DiaryFormSection("\(category.icon) \(category.name)") {
                    FlowLayout(spacing: 8) {
                        ForEach(category.enabledOptions) { option in
                            DiaryChip(
                                title: option.name,
                                icon: option.icon,
                                iconImageName: option.iconImageName ?? category.iconImageName,
                                isSelected: optionID == option.id
                            ) {
                                categoryID = category.id
                                optionID = option.id
                            }
                        }
                    }
                }
            }
        }
        .onAppear(perform: load)
    }

    private var selection: (FactorCategory, FactorOption)? {
        guard let category = categories.first(where: { $0.id == categoryID }),
              let option = (category.options ?? []).first(where: { $0.id == optionID }) else { return nil }
        return (category, option)
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        guard let editingID, let event = store.factor(id: editingID) else { return }
        moment = event.timestamp
        categoryID = event.categoryID
        optionID = event.optionID
    }

    private func save() {
        guard let (category, option) = selection else { return }
        if let editingID, let event = store.factor(id: editingID) {
            store.updateFactor(event, category: category, option: option, at: moment)
        } else {
            store.addFactor(category: category, option: option, at: moment)
        }
    }

    /// Only an existing record can be deleted.
    private var deleteAction: (() -> Void)? {
        guard editingID != nil else { return nil }
        return delete
    }

    private func delete() {
        guard let editingID, let event = store.factor(id: editingID) else { return }
        store.deleteFactor(event)
    }
}

// MARK: - Note

struct NoteEntrySheet: View {
    @Environment(DiaryEntryStore.self) private var store

    let editingID: UUID?

    @State private var moment: Date
    @State private var text = ""
    @State private var loaded = false

    init(editingID: UUID?, day: Date) {
        self.editingID = editingID
        _moment = State(initialValue: DiaryDefaults.defaultMoment(on: day))
    }

    var body: some View {
        DiaryFormScaffold(
            title: "📝 Заметка",
            canSave: DiaryDefaults.trimmed(text) != nil && moment <= .now,
            hint: moment > .now ? "Это время ещё не наступило." : nil,
            onSave: save,
            onDelete: deleteAction
        ) {
            DiaryMomentPicker(moment: $moment)
            DiaryFormSection("Текст") {
                TextField("Что хочется запомнить про этот момент", text: $text, axis: .vertical)
                    .lineLimit(4...12)
                    .font(.lora(15))
                    .diaryField()
            }
        }
        .onAppear(perform: load)
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        guard let editingID, let note = store.note(id: editingID) else { return }
        moment = note.timestamp
        text = note.text
    }

    private func save() {
        guard let value = DiaryDefaults.trimmed(text) else { return }
        if let editingID, let note = store.note(id: editingID) {
            store.updateNote(note, text: value, at: moment)
        } else {
            store.addNote(value, at: moment)
        }
    }

    /// Only an existing record can be deleted.
    private var deleteAction: (() -> Void)? {
        guard editingID != nil else { return nil }
        return delete
    }

    private func delete() {
        guard let editingID, let note = store.note(id: editingID) else { return }
        store.deleteNote(note)
    }
}

// MARK: - Building blocks

/// Parchment sheet with Отмена / Сохранить and an optional confirmed delete.
struct DiaryFormScaffold<Content: View>: View {
    @Environment(\.dismiss) private var dismiss

    let title: String
    let canSave: Bool
    var hint: String?
    let onSave: () -> Void
    var onDelete: (() -> Void)?
    @ViewBuilder var content: Content

    @State private var confirmDelete = false

    var body: some View {
        NavigationStack {
            ZStack {
                AppTheme.parchmentCard.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        content
                        if let hint {
                            Text(hint)
                                .font(.lora(13))
                                .foregroundStyle(AppTheme.rustDeep)
                        }
                        if onDelete != nil {
                            Button("Удалить запись") { confirmDelete = true }
                                .font(.lora(14))
                                .foregroundStyle(AppTheme.rustDeep)
                                .padding(.top, 4)
                        }
                    }
                    .padding(20)
                }
                .scrollDismissesKeyboard(.interactively)
            }
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text(title)
                        .font(.lora(17, weight: .semibold))
                        .foregroundStyle(AppTheme.ink)
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }
                        .font(.lora(15))
                        .foregroundStyle(AppTheme.forest)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Сохранить") {
                        onSave()
                        dismiss()
                    }
                    .font(.lora(15, weight: .semibold))
                    .foregroundStyle(canSave ? AppTheme.forest : AppTheme.inkSoft)
                    .disabled(!canSave)
                }
            }
            .confirmationDialog("Удалить эту запись?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Удалить", role: .destructive) {
                    onDelete?()
                    dismiss()
                }
                Button("Отмена", role: .cancel) {}
            }
        }
        .presentationDetents([.large])
    }
}

struct DiaryFormSection<Content: View>: View {
    let label: String
    @ViewBuilder var content: Content

    init(_ label: String, @ViewBuilder content: () -> Content) {
        self.label = label
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label)
                .font(.lora(13, weight: .medium))
                .foregroundStyle(AppTheme.inkSoft)
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Separate date and time pickers over one `Date` — each edits only its
/// half, so "вчера в 22:30" is two taps.
struct DiaryMomentPicker: View {
    @Binding var moment: Date

    var body: some View {
        HStack(spacing: 16) {
            DiaryFormSection("Дата") {
                DatePicker("Дата", selection: $moment, in: ...Date.now, displayedComponents: .date)
                    .diaryPicker()
            }
            DiaryFormSection("Время") {
                DatePicker("Время", selection: $moment, displayedComponents: .hourAndMinute)
                    .diaryPicker()
            }
        }
    }
}

struct DiaryChip: View {
    let title: String
    var icon: String?
    var iconImageName: String?
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if let icon {
                    FactorIconView(icon: icon, iconImageName: iconImageName, size: 18)
                }
                Text(title)
                    .font(.lora(13, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? AppTheme.parchmentCard : AppTheme.ink)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(Capsule(style: .continuous).fill(isSelected ? AppTheme.forest : AppTheme.parchment.opacity(0.55)))
            .overlay(Capsule(style: .continuous).stroke(AppTheme.border, lineWidth: isSelected ? 0 : 1))
        }
        .buttonStyle(.plain)
    }
}

extension View {
    func diaryField(highlighted: Bool = false) -> some View {
        self
            .foregroundStyle(AppTheme.ink)
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(highlighted ? AppTheme.forest.opacity(0.14) : AppTheme.parchment.opacity(0.55))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(highlighted ? AppTheme.forest : AppTheme.border, lineWidth: 1.25)
            )
    }

    func diaryPicker() -> some View {
        self
            .labelsHidden()
            .tint(AppTheme.forest)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
