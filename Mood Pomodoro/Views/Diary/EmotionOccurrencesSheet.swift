//
//  EmotionOccurrencesSheet.swift
//  Mood Pomodoro
//

import SwiftUI

/// Every time one feeling was recorded, newest first, each with what else
/// was written down close to it. It is there to look back through — what
/// was going on around the feeling is left for the reader to weigh; nothing
/// here says what caused it.
struct EmotionOccurrencesSheet: View {
    let emotion: Emotion
    let entries: [EmotionEntry]
    let context: (Date) -> [String]
    let onOpenDay: (Date) -> Void

    @Environment(\.dismiss) private var dismiss

    private var occurrences: [EmotionEntry] {
        entries.filter { $0.emotions.contains(emotion) }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                ForestBackdrop()
                ScrollView {
                    VStack(spacing: 12) {
                        header
                        ForEach(occurrences, id: \.id) { entry in
                            occurrenceCard(entry)
                        }
                    }
                    .padding(16)
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(L("Готово", "Done")) { dismiss() }
                        .foregroundStyle(AppTheme.forest)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(emotion.imageName)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 40, height: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(emotion.label)
                    .font(.lora(20, weight: .semibold))
                    .foregroundStyle(AppTheme.ink)
                Text(countLabel(occurrences.count, ru: ("запись", "записи", "записей"), en: ("entry", "entries")))
                    .font(.lora(13))
                    .foregroundStyle(AppTheme.inkSoft)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func occurrenceCard(_ entry: EmotionEntry) -> some View {
        let lines = context(entry.eventDate)
        let others = entry.emotions.filter { $0 != emotion }
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(DateFormatting.fullDate(entry.eventDate) + " · " + DateFormatting.time(entry.eventDate))
                    .font(.lora(14, weight: .semibold))
                    .foregroundStyle(AppTheme.ink)
                Spacer(minLength: 8)
                Button(L("Открыть день", "Open day")) {
                    dismiss()
                    onOpenDay(entry.eventDate)
                }
                .font(.lora(12, weight: .medium))
                .foregroundStyle(AppTheme.forest)
                .buttonStyle(.plain)
            }
            if !others.isEmpty {
                Text(L("Вместе с этим: ", "Along with it: ") + others.map { "\($0.emoji) \($0.label)" }.joined(separator: " · "))
                    .font(.lora(12.5))
                    .foregroundStyle(AppTheme.inkSoft)
            }
            if let note = entry.note, !note.isEmpty {
                Text("📝 " + note)
                    .font(.lora(13))
                    .foregroundStyle(AppTheme.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if lines.isEmpty {
                if entry.note?.isEmpty ?? true {
                    Text(L("Рядом по времени других записей нет.", "Nothing else was recorded around then."))
                        .font(.lora(12))
                        .foregroundStyle(AppTheme.inkSoft)
                }
            } else {
                Divider().overlay(AppTheme.border)
                Text(L("Что было записано рядом", "Recorded around then"))
                    .font(.loraItalic(11))
                    .foregroundStyle(AppTheme.inkSoft)
                ForEach(lines, id: \.self) { line in
                    Text(line)
                        .font(.lora(12.5))
                        .foregroundStyle(AppTheme.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .parchmentCard(padding: 0)
    }
}
