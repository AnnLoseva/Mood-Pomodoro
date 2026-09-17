//
//  EmotionEntrySheets.swift
//  Mood Pomodoro
//

import SwiftUI

/// "🎭 Эмоции" and "⚡️ Импульс" — the two records that stand entirely on
/// their own: no session, no mood, no scale required. Both use the same
/// date-and-time discipline as every other diary form, so anything
/// remembered later lands on the moment it actually happened.

// MARK: - Emotions

/// One or more feelings at a moment.
///
/// What this form is careful about:
/// * **Nothing else is required.** Настроение, энергия и мотивация are a
///   different question; the app never creates a filler check-in to carry a
///   feeling.
/// * **Empty is empty.** With nothing selected there is nothing to save —
///   an empty record is not "спокойно".
/// * **Several at once.** Тревожная и злая is one moment, so the selection
///   is a set rather than a radio button.
struct EmotionEntrySheet: View {
    @Environment(DiaryEntryStore.self) private var store

    let editingID: UUID?

    @State private var moment: Date
    @State private var selection: Set<Emotion> = []
    @State private var note = ""
    @State private var loaded = false

    init(editingID: UUID?, day: Date) {
        self.editingID = editingID
        _moment = State(initialValue: DiaryDefaults.defaultMoment(on: day))
    }

    var body: some View {
        DiaryFormScaffold(
            title: L("🎭 Эмоции", "🎭 Emotions"),
            canSave: !selection.isEmpty && moment <= .now,
            hint: hint,
            onSave: save,
            onDelete: deleteAction
        ) {
            DiaryMomentPicker(moment: $moment)
            DiaryFormSection(L("Что чувствуешь", "What you're feeling")) {
                EmotionPickerGrid(selection: $selection)
                DiaryNote(text: L("Можно отметить несколько сразу. Это отдельная запись — настроение, силы и мотивацию заполнять не нужно.", "You can pick several at once. This is its own entry — no need to fill in mood, energy or motivation."))
            }
            DiaryFormSection(L("Заметка", "Note")) {
                TextField(L("Необязательно", "Optional"), text: $note, axis: .vertical)
                    .font(.lora(15))
                    .diaryField()
            }
        }
        .onAppear(perform: load)
    }

    private var hint: String? {
        if moment > .now { return L("Это время ещё не наступило.", "That time hasn't come yet.") }
        if selection.isEmpty {
            return L("Выбери хотя бы одну эмоцию — пустая запись ничего не значит.", "Pick at least one feeling — an empty entry says nothing.")
        }
        return nil
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        guard let editingID, let entry = store.emotions(id: editingID) else { return }
        moment = entry.eventDate
        selection = Set(entry.emotions)
        note = entry.note ?? ""
    }

    private func save() {
        let emotions = Emotion.allCases.filter(selection.contains)
        guard !emotions.isEmpty else { return }
        let text = DiaryDefaults.trimmed(note)
        if let editingID, let entry = store.emotions(id: editingID) {
            store.updateEmotions(entry, emotions: emotions, note: text, at: moment)
        } else {
            store.addEmotions(emotions, note: text, at: moment)
        }
    }

    private var deleteAction: (() -> Void)? {
        guard editingID != nil else { return nil }
        return delete
    }

    private func delete() {
        guard let editingID, let entry = store.emotions(id: editingID) else { return }
        store.deleteEmotions(entry)
    }
}

// MARK: - Impulses

/// "⚡️ Импульс" — a category and a time is the whole minimum. Strength,
/// what came of it and a note are offered and never demanded, and nothing
/// here creates a meal or a session: an impulse is a mark, not an event
/// the app decides happened.
struct ImpulseEntrySheet: View {
    @Environment(DiaryEntryStore.self) private var store

    let editingID: UUID?

    @State private var moment: Date
    @State private var category: ImpulseCategory?
    @State private var strength: ImpulseStrength?
    @State private var outcome: ImpulseOutcome?
    @State private var note = ""
    @State private var loaded = false

    init(editingID: UUID?, day: Date) {
        self.editingID = editingID
        _moment = State(initialValue: DiaryDefaults.defaultMoment(on: day))
    }

    var body: some View {
        DiaryFormScaffold(
            title: L("⚡️ Импульс", "⚡️ Impulse"),
            canSave: category != nil && moment <= .now,
            hint: moment > .now ? L("Это время ещё не наступило.", "That time hasn't come yet.") : nil,
            onSave: save,
            onDelete: deleteAction
        ) {
            DiaryMomentPicker(moment: $moment)
            DiaryFormSection(L("О чём импульс", "What it was about")) {
                FlowLayout(spacing: 8) {
                    ForEach(ImpulseCategory.allCases) { option in
                        DiaryChip(title: "\(option.emoji) \(option.label)", isSelected: category == option) {
                            category = option
                        }
                    }
                }
            }
            DiaryFormSection(L("Что вышло", "What came of it")) {
                FlowLayout(spacing: 8) {
                    ForEach(ImpulseOutcome.allCases) { option in
                        DiaryChip(title: "\(option.emoji) \(option.label)", isSelected: outcome == option) {
                            outcome = outcome == option ? nil : option
                        }
                    }
                }
                DiaryNote(text: L("Необязательно — и «сделала» здесь не хуже, чем «только захотелось».", "Optional — and “did it” is no worse an answer here than “just felt like it”."))
            }
            DiaryFormSection(L("Сила импульса", "How strong it was")) {
                FlowLayout(spacing: 8) {
                    ForEach(ImpulseStrength.orderedCases) { option in
                        DiaryChip(title: "\(option.emoji) \(option.label)", isSelected: strength == option) {
                            strength = strength == option ? nil : option
                        }
                    }
                }
            }
            DiaryFormSection(L("Заметка", "Note")) {
                TextField(L("Необязательно", "Optional"), text: $note, axis: .vertical)
                    .font(.lora(15))
                    .diaryField()
            }
            DiaryNote(text: L("Это твоя отметка. Приложение само не считает импульсом ни еду, ни покупку, ни начатое занятие — и не создаёт из этой записи ни приём еды, ни сессию.", "This is your own mark. The app never decides by itself that a meal, a purchase or a new activity was impulsive — and this entry creates neither a meal nor a session."))
        }
        .onAppear(perform: load)
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        guard let editingID, let entry = store.impulse(id: editingID) else { return }
        moment = entry.eventDate
        category = entry.category
        strength = entry.strength
        outcome = entry.outcome
        note = entry.note ?? ""
    }

    private func save() {
        guard let category else { return }
        let text = DiaryDefaults.trimmed(note)
        if let editingID, let entry = store.impulse(id: editingID) {
            store.updateImpulse(
                entry,
                category: category,
                strength: strength,
                outcome: outcome,
                note: text,
                at: moment
            )
        } else {
            store.addImpulse(
                category: category,
                strength: strength,
                outcome: outcome,
                note: text,
                at: moment
            )
        }
    }

    private var deleteAction: (() -> Void)? {
        guard editingID != nil else { return nil }
        return delete
    }

    private func delete() {
        guard let editingID, let entry = store.impulse(id: editingID) else { return }
        store.deleteImpulse(entry)
    }
}

// MARK: - Shared pickers

/// The seven feelings as illustrated, colour-coded tiles. Compact enough to
/// sit inside a form or a quick check-in, and multi-select by design.
struct EmotionPickerGrid: View {
    @Binding var selection: Set<Emotion>
    var size: CGFloat = 46

    var body: some View {
        FlowLayout(spacing: 8) {
            ForEach(Emotion.allCases) { emotion in
                let isSelected = selection.contains(emotion)
                Button {
                    if isSelected {
                        selection.remove(emotion)
                    } else {
                        selection.insert(emotion)
                    }
                } label: {
                    VStack(spacing: 4) {
                        Image(emotion.imageName)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: size, height: size)
                        Text(emotion.label)
                            .font(.lora(11, weight: isSelected ? .semibold : .regular))
                            .foregroundStyle(isSelected ? emotion.color : AppTheme.inkSoft)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 7)
                    .frame(width: size + 34)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(isSelected ? emotion.color.opacity(0.18) : AppTheme.chipFill)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(isSelected ? emotion.color : AppTheme.border, lineWidth: isSelected ? 2 : 1)
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(emotion.label)
                .accessibilityValue(isSelected ? L("выбрано", "selected") : L("не выбрано", "not selected"))
            }
        }
    }
}

/// Отдых / обязательная работа / учёба, with the answer clearable back to
/// "не выбрано". Deliberately three chips and no fourth: "без типа" is a
/// state older records are in, not something to pick.
struct SessionTypePicker: View {
    @Binding var selection: SessionType?
    var showsHint = true

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            FlowLayout(spacing: 8) {
                ForEach(SessionType.allCases) { type in
                    let isSelected = selection == type
                    Button {
                        selection = isSelected ? nil : type
                    } label: {
                        HStack(spacing: 5) {
                            Text(type.emoji)
                            Text(type.label)
                                .font(.lora(13, weight: isSelected ? .semibold : .regular))
                        }
                        .foregroundStyle(isSelected ? AppTheme.parchmentCard : AppTheme.ink)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(
                            Capsule(style: .continuous)
                                .fill(isSelected ? type.color : AppTheme.chipFill)
                        )
                        .overlay(
                            Capsule(style: .continuous)
                                .stroke(AppTheme.border, lineWidth: isSelected ? 0 : 1)
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(type.label)
                    .accessibilityValue(isSelected ? L("выбрано", "selected") : L("не выбрано", "not selected"))
                }
            }
            if showsHint {
                Text(selection == nil
                     ? L("Выбери тип занятия: учёба, работа или отдых.", "Choose the activity type: study, work or rest.")
                     : L("Нажми ещё раз, чтобы снять отметку.", "Tap again to clear it."))
                    .font(.lora(11))
                    .foregroundStyle(AppTheme.inkSoft)
            }
        }
    }
}
