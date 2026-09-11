//
//  ExportSheet.swift
//  Mood Pomodoro
//

import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import UIKit

/// "Экспорт": pick a period, a language and a format, look at a preview,
/// then share the file (to ChatGPT, Claude, Notes, mail…) or copy the text.
/// Nothing leaves the device unless the user sends it somewhere herself.
struct ExportSheet: View {
    private enum Period: String, CaseIterable, Identifiable {
        case week, days30, thisMonth, allTime, custom

        var id: String { rawValue }

        var title: String {
            switch self {
            case .week: return L("7 дней", "7 days")
            case .days30: return L("30 дней", "30 days")
            case .thisMonth: return L("Этот месяц", "This month")
            case .allTime: return L("Всё время", "All time")
            case .custom: return L("Свои даты", "Custom")
            }
        }
    }

    @Environment(\.dismiss) private var dismiss

    @Query private var sessions: [FocusSession]
    @Query private var checkIns: [CheckIn]
    @Query private var cycleEntries: [CycleEntry]
    @Query private var supportEntries: [SupportEntry]
    @Query private var notes: [JournalNote]
    @Query private var conditionEvents: [ConditionEvent]

    @State private var period: Period = .days30
    @State private var customStart = Calendar.current.date(byAdding: .day, value: -13, to: .now) ?? .now
    @State private var customEnd = Date.now
    @State private var language = AppLanguage.current
    @State private var format: ExportFormat = .markdown
    @State private var includeAIPrompt = true
    @State private var includeNotes = true
    @State private var includeCycle = true
    @State private var includeSupport = true
    @State private var copied = false

    private let calendar = Calendar.current

    private var input: ExportInput {
        ExportInput(
            sessions: sessions.filter { !$0.isActive },
            checkIns: checkIns,
            cycleEntries: cycleEntries,
            supportEntries: supportEntries,
            notes: notes,
            conditionEvents: conditionEvents
        )
    }

    private var options: ExportOptions {
        let now = Date.now
        let start: Date
        let end: Date
        switch period {
        case .week:
            start = calendar.date(byAdding: .day, value: -6, to: now) ?? now
            end = now
        case .days30:
            start = calendar.date(byAdding: .day, value: -29, to: now) ?? now
            end = now
        case .thisMonth:
            start = calendar.dateInterval(of: .month, for: now)?.start ?? now
            end = now
        case .allTime:
            start = input.earliestDate ?? now
            end = now
        case .custom:
            start = customStart
            end = customEnd
        }
        return ExportOptions(
            start: start,
            end: end,
            language: language,
            format: format,
            includeAIPrompt: includeAIPrompt,
            includeNotes: includeNotes,
            includeCycle: includeCycle,
            includeSupport: includeSupport
        )
    }

    var body: some View {
        let options = options
        let text = DiaryExporter.export(input, options: options, calendar: calendar)
        let fileName = DiaryExporter.fileName(for: options, calendar: calendar)

        NavigationStack {
            ZStack {
                AppTheme.parchmentCard.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        DiaryFormSection(L("Период", "Period")) {
                            FlowLayout(spacing: 8) {
                                ForEach(Period.allCases) { item in
                                    DiaryChip(title: item.title, isSelected: period == item) { period = item }
                                }
                            }
                            if period == .custom {
                                HStack(spacing: 16) {
                                    DatePicker(L("С", "From"), selection: $customStart, in: ...customEnd, displayedComponents: .date)
                                        .diaryPicker()
                                    DatePicker(L("По", "To"), selection: $customEnd, in: customStart...Date.now, displayedComponents: .date)
                                        .diaryPicker()
                                }
                            }
                        }

                        DiaryFormSection(L("Язык файла", "File language")) {
                            FlowLayout(spacing: 8) {
                                ForEach(AppLanguage.allCases) { item in
                                    DiaryChip(title: item.nativeName, isSelected: language == item) { language = item }
                                }
                            }
                        }

                        DiaryFormSection(L("Формат", "Format")) {
                            FlowLayout(spacing: 8) {
                                DiaryChip(title: L("Текст для ИИ (Markdown)", "Text for AI (Markdown)"), isSelected: format == .markdown) { format = .markdown }
                                DiaryChip(title: "JSON", isSelected: format == .json) { format = .json }
                            }
                        }

                        DiaryFormSection(L("Что включить", "Include")) {
                            VStack(spacing: 10) {
                                if format == .markdown {
                                    toggle(L("Просьбу к ИИ в начале", "A request to the AI at the top"), isOn: $includeAIPrompt)
                                }
                                toggle(L("Заметки", "Notes"), isOn: $includeNotes)
                                toggle(L("Цикл", "Cycle"), isOn: $includeCycle)
                                toggle(L("Ежедневную поддержку", "Daily support"), isOn: $includeSupport)
                            }
                        }

                        DiaryFormSection(L("Предпросмотр", "Preview")) {
                            ScrollView {
                                Text(String(text.prefix(6000)))
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundStyle(AppTheme.ink)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .textSelection(.enabled)
                                    .padding(12)
                            }
                            .frame(height: 260)
                            .background(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(AppTheme.parchment.opacity(0.55))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .stroke(AppTheme.border, lineWidth: 1.25)
                            )
                        }

                        VStack(spacing: 10) {
                            ShareLink(
                                item: ExportDocument(text: text, fileName: fileName, format: format),
                                preview: SharePreview(fileName)
                            ) {
                                Label(L("Поделиться файлом", "Share file"), systemImage: "square.and.arrow.up")
                            }
                            .buttonStyle(.goblinPrimary)

                            Button {
                                UIPasteboard.general.string = text
                                copied = true
                            } label: {
                                Label(
                                    copied ? L("Скопировано", "Copied") : L("Скопировать текст", "Copy text"),
                                    systemImage: copied ? "checkmark" : "doc.on.doc"
                                )
                            }
                            .buttonStyle(.goblinSecondary)
                        }

                        DiaryNote(text: L("В файле — личные данные: настроение, заметки, цикл, поддержка. Отправляй его только туда, где тебе спокойно их хранить.", "The file holds personal data — mood, notes, cycle, support. Only send it somewhere you're comfortable keeping it."))
                    }
                    .padding(20)
                }
            }
            .onChange(of: text) { _, _ in copied = false }
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text(L("Экспорт", "Export"))
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

    private func toggle(_ title: String, isOn: Binding<Bool>) -> some View {
        Toggle(title, isOn: isOn)
            .font(.lora(15))
            .foregroundStyle(AppTheme.ink)
            .tint(AppTheme.forest)
    }
}

/// The export as a shareable file, written to a temporary location only
/// when the share sheet actually asks for it.
nonisolated struct ExportDocument: Transferable, Sendable {
    let text: String
    let fileName: String
    let format: ExportFormat

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .json) { document in
            try document.writtenFile()
        }
        .exportingCondition { $0.format == .json }
        FileRepresentation(exportedContentType: .plainText) { document in
            try document.writtenFile()
        }
        .exportingCondition { $0.format == .markdown }
    }

    private func writtenFile() throws -> SentTransferredFile {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        try text.write(to: url, atomically: true, encoding: .utf8)
        return SentTransferredFile(url)
    }
}
