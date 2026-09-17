//
//  FoodEntrySheets.swift
//  Mood Pomodoro
//

import SwiftUI

/// "🍽 Еда" and "🍎 Голод / аппетит". Both follow the diary's rule: a date
/// and a time prefilled with the day being viewed and always editable, so
/// "в 16:30 ела пасту" typed at 23:00 lands at 16:30.
///
/// Both are meant to be over in a few taps. The food form is deliberately
/// not a long form: pick a drawer, answer the two chips it asks for, save.
/// Everything else — what it was, how full it left her, a note — is
/// optional, and nothing in either sheet praises, scolds, scores or counts.

// MARK: - Food

struct FoodEntrySheet: View {
    @Environment(DiaryEntryStore.self) private var store

    let editingID: UUID?

    @State private var moment: Date
    @State private var category: FoodCategory?
    @State private var mealDensity: MealDensity?
    @State private var taste: TasteRating?
    @State private var treatType: TreatType?
    @State private var treatAmount: TreatAmount?
    @State private var fullness: Fullness?
    @State private var desc = ""
    @State private var note = ""
    @State private var loaded = false

    init(editingID: UUID?, day: Date) {
        self.editingID = editingID
        _moment = State(initialValue: DiaryDefaults.defaultMoment(on: day))
    }

    var body: some View {
        DiaryFormScaffold(
            title: L("🍽 Еда", "🍽 Food"),
            canSave: category != nil && moment <= .now,
            hint: moment > .now ? L("Это время ещё не наступило.", "That time hasn't come yet.") : nil,
            onSave: save,
            onDelete: deleteAction
        ) {
            DiaryMomentPicker(moment: $moment)

            DiaryFormSection(L("Какая еда", "Which kind")) {
                HStack(spacing: 8) {
                    ForEach(FoodCategory.allCases) { option in
                        categoryButton(option)
                    }
                }
                DiaryNote(text: L("Это просто твои полки для записей — приложение не оценивает, что ты ела.", "These are just your own drawers for records — the app doesn't judge what you ate."))
            }

            // Only the branch this category actually asks for is shown, and
            // only that branch is saved — see `FoodEntry.apply`.
            if let category {
                if category.usesMealDetails {
                    DiaryFormSection(L("Насколько плотно", "How much of a meal")) {
                        FlowLayout(spacing: 8) {
                            ForEach(MealDensity.allCases) { option in
                                DiaryChip(title: "\(option.emoji) \(option.label)", isSelected: mealDensity == option) {
                                    mealDensity = mealDensity == option ? nil : option
                                }
                            }
                        }
                    }
                    DiaryFormSection(L("Как понравилось", "How it was")) {
                        FlowLayout(spacing: 8) {
                            ForEach(TasteRating.allCases) { option in
                                DiaryChip(title: "\(option.emoji) \(option.label)", isSelected: taste == option) {
                                    taste = taste == option ? nil : option
                                }
                            }
                        }
                    }
                } else {
                    DiaryFormSection(L("Тип", "Type")) {
                        FlowLayout(spacing: 8) {
                            ForEach(TreatType.allCases) { option in
                                DiaryChip(title: "\(option.emoji) \(option.label)", isSelected: treatType == option) {
                                    treatType = treatType == option ? nil : option
                                }
                            }
                        }
                    }
                    DiaryFormSection(L("Количество", "How much")) {
                        FlowLayout(spacing: 8) {
                            ForEach(TreatAmount.allCases) { option in
                                DiaryChip(title: option.label, isSelected: treatAmount == option) {
                                    treatAmount = treatAmount == option ? nil : option
                                }
                            }
                        }
                    }
                }
            }

            DiaryFormSection(L("Что это было?", "What was it?")) {
                TextField(L("Необязательно — например, паста с грибами", "Optional — for example, pasta with mushrooms"), text: $desc)
                    .font(.lora(15))
                    .diaryField()
            }

            DiaryFormSection(L("Сытость после еды", "How full afterwards")) {
                ScaleStepPickerRow(selection: $fullness)
                DiaryNote(text: L("Если хочется — можно отметить, наелась или осталась голодной. Это отдельно от того, сколько было еды.", "If you feel like it, you can note whether you ended up full or still hungry. That's separate from how much food there was."))
            }

            DiaryFormSection(L("Заметка", "Note")) {
                TextField(L("Необязательно", "Optional"), text: $note, axis: .vertical)
                    .font(.lora(15))
                    .diaryField()
            }
        }
        .onAppear(perform: load)
    }

    /// Choosing a different drawer drops the answers that belonged to the
    /// old one, so nothing contradictory can reach the store even if the
    /// user switches back and forth.
    private func categoryButton(_ option: FoodCategory) -> some View {
        let isSelected = category == option
        return Button {
            if category != option {
                mealDensity = nil
                taste = nil
                treatType = nil
                treatAmount = nil
            }
            category = option
        } label: {
            VStack(spacing: 4) {
                Image(option.imageName)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(height: 52)
                Text(option.label)
                    .font(.lora(13, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? AppTheme.ink : AppTheme.inkSoft)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(isSelected ? AppTheme.forest.opacity(0.18) : AppTheme.chipFill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(isSelected ? AppTheme.forest : AppTheme.border, lineWidth: isSelected ? 2 : 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(option.label)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        guard let editingID, let entry = store.food(id: editingID) else { return }
        moment = entry.eventDate
        category = entry.category
        mealDensity = entry.mealDensity
        taste = entry.taste
        treatType = entry.treatType
        treatAmount = entry.treatAmount
        fullness = entry.fullness
        desc = entry.desc ?? ""
        note = entry.note ?? ""
    }

    private func save() {
        guard let category else { return }
        let description = DiaryDefaults.trimmed(desc)
        let text = DiaryDefaults.trimmed(note)
        if let editingID, let entry = store.food(id: editingID) {
            store.updateFood(
                entry,
                category: category,
                mealDensity: mealDensity,
                taste: taste,
                treatType: treatType,
                treatAmount: treatAmount,
                fullness: fullness,
                desc: description,
                note: text,
                at: moment
            )
        } else {
            store.addFood(
                category: category,
                mealDensity: mealDensity,
                taste: taste,
                treatType: treatType,
                treatAmount: treatAmount,
                fullness: fullness,
                desc: description,
                note: text,
                at: moment
            )
        }
    }

    /// Only an existing record can be deleted.
    private var deleteAction: (() -> Void)? {
        guard editingID != nil else { return nil }
        return delete
    }

    private func delete() {
        guard let editingID, let entry = store.food(id: editingID) else { return }
        store.deleteFood(entry)
    }
}

// MARK: - Hunger / appetite

/// Two scales, asked separately and stored separately. Hunger is what the
/// body is doing; appetite is whether anything appeals. Answering one is a
/// complete record — the other stays "не отмечено" rather than being
/// filled in from its neighbour.
struct HungerEntrySheet: View {
    @Environment(DiaryEntryStore.self) private var store

    let editingID: UUID?

    @State private var moment: Date
    @State private var hunger: HungerLevel?
    @State private var appetite: AppetiteLevel?
    @State private var note = ""
    @State private var loaded = false

    init(editingID: UUID?, day: Date) {
        self.editingID = editingID
        _moment = State(initialValue: DiaryDefaults.defaultMoment(on: day))
    }

    var body: some View {
        DiaryFormScaffold(
            title: L("🍎 Голод / аппетит", "🍎 Hunger / appetite"),
            canSave: (hunger != nil || appetite != nil) && moment <= .now,
            hint: moment > .now ? L("Это время ещё не наступило.", "That time hasn't come yet.") : nil,
            onSave: save,
            onDelete: deleteAction
        ) {
            DiaryMomentPicker(moment: $moment)

            DiaryFormSection(L("Голод — насколько телу нужна еда", "Hunger — how much your body needs food")) {
                LevelPickerRow(selection: $hunger)
            }

            DiaryFormSection(L("Аппетит — насколько хочется есть", "Appetite — how much you feel like eating")) {
                LevelPickerRow(selection: $appetite)
            }

            DiaryNote(text: L("Это две разные вещи: можно быть очень голодной и при этом ничего не хотеть — и наоборот. Можно отметить только одну.", "These are two different things: you can be very hungry and want nothing at all — and the other way round. You can answer just one of them."))

            DiaryFormSection(L("Заметка", "Note")) {
                TextField(L("Необязательно", "Optional"), text: $note, axis: .vertical)
                    .font(.lora(15))
                    .diaryField()
            }
        }
        .onAppear(perform: load)
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        guard let editingID, let entry = store.hunger(id: editingID) else { return }
        moment = entry.eventDate
        hunger = entry.hunger
        appetite = entry.appetite
        note = entry.note ?? ""
    }

    private func save() {
        let text = DiaryDefaults.trimmed(note)
        if let editingID, let entry = store.hunger(id: editingID) {
            store.updateHunger(entry, hunger: hunger, appetite: appetite, note: text, at: moment)
        } else {
            store.addHunger(hunger: hunger, appetite: appetite, note: text, at: moment)
        }
    }

    /// Only an existing record can be deleted.
    private var deleteAction: (() -> Void)? {
        guard editingID != nil else { return nil }
        return delete
    }

    private func delete() {
        guard let editingID, let entry = store.hunger(id: editingID) else { return }
        store.deleteHunger(entry)
    }
}
