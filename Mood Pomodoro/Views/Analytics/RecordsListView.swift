import SwiftUI
import SwiftData

/// The raw entries of one kind in the chosen period, newest first, each
/// opening the diary's own form. It is where a count ("14 meals") ends: the
/// entries it counted, one by one.
struct RecordsListView: View {
    let kind: AnalyticsRecordKind
    @Bindable var store: AnalyticsStore

    var body: some View {
        let interval = store.period.interval(earliest: store.facts.earliest)
        AnalyticsDetailScaffold(title: kind.title, store: store) {
            Group {
                switch kind {
                case .meals: MealRecords(interval: interval)
                case .hunger: HungerRecords(interval: interval)
                case .emotions: EmotionRecords(interval: interval)
                case .impulses: ImpulseRecords(interval: interval)
                case .cycle: CycleRecords(interval: interval)
                case .medication: MedicationRecords(interval: interval)
                }
            }
            .id("\(kind.rawValue)-\(interval.start.timeIntervalSince1970)-\(interval.end.timeIntervalSince1970)")
        }
    }
}

/// One line of a records list.
struct RecordRowModel: Identifiable {
    let id: String
    let date: Date
    let title: String
    let subtitle: String?
    let sheet: DiaryEntrySheet?
}

private struct RecordsCard: View {
    let rows: [RecordRowModel]
    @State private var sheet: DiaryEntrySheet?
    @State private var sheetDay = Date.now
    private static let cap = 200

    var body: some View {
        if rows.isEmpty {
            AnalyticsQuietNote(text: L("В этом периоде записей нет.", "No records in this period."))
        } else {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(rows.prefix(Self.cap).enumerated()), id: \.element.id) { index, row in
                    if index > 0 { Divider().overlay(AppTheme.border) }
                    Button {
                        guard let target = row.sheet else { return }
                        sheetDay = row.date
                        sheet = target
                    } label: {
                        HStack(spacing: 10) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(row.title).font(.lora(14, weight: .medium)).foregroundStyle(AppTheme.ink)
                                    .multilineTextAlignment(.leading)
                                Text([DateFormatting.fullDate(row.date) + ", " + DateFormatting.time(row.date), row.subtitle]
                                    .compactMap { $0 }.joined(separator: " · "))
                                    .font(.lora(12)).foregroundStyle(AppTheme.inkSoft)
                                    .multilineTextAlignment(.leading)
                            }
                            Spacer(minLength: 8)
                            if row.sheet != nil {
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(AppTheme.inkSoft)
                            }
                        }
                        .frame(minHeight: 52)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                if rows.count > Self.cap {
                    Text(L("Показаны последние \(Self.cap). Более ранние — через день в дневнике или экспорт.", "Showing the latest \(Self.cap). Earlier ones: through the diary day or the export."))
                        .font(.lora(11)).foregroundStyle(AppTheme.inkSoft).padding(.top, 8)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 4)
            .parchmentCard(padding: 0)
            .sheet(item: $sheet) { DiaryEntrySheetView(sheet: $0, day: sheetDay) }
        }
    }
}

private struct MealRecords: View {
    @Query private var entries: [FoodEntry]
    init(interval: DateInterval) {
        let s = interval.start, e = interval.end
        _entries = Query(filter: #Predicate<FoodEntry> { $0.eventDate >= s && $0.eventDate < e }, sort: \.eventDate, order: .reverse)
    }
    var body: some View {
        RecordsCard(rows: entries.map {
            RecordRowModel(id: $0.id.uuidString, date: $0.eventDate, title: "\($0.category.emoji) \($0.category.label)",
                           subtitle: DiaryDefaults.trimmed($0.note ?? ""), sheet: .food(editing: $0.id))
        })
    }
}

private struct HungerRecords: View {
    @Query private var entries: [HungerEntry]
    init(interval: DateInterval) {
        let s = interval.start, e = interval.end
        _entries = Query(filter: #Predicate<HungerEntry> { $0.eventDate >= s && $0.eventDate < e }, sort: \.eventDate, order: .reverse)
    }
    var body: some View {
        RecordsCard(rows: entries.filter { !$0.isEmpty }.map {
            let parts = [$0.hunger.map { L("голод: ", "hunger: ") + $0.label }, $0.appetite.map { L("аппетит: ", "appetite: ") + $0.label }]
            return RecordRowModel(id: $0.id.uuidString, date: $0.eventDate, title: parts.compactMap { $0 }.joined(separator: " · "),
                                  subtitle: DiaryDefaults.trimmed($0.note ?? ""), sheet: .hunger(editing: $0.id))
        })
    }
}

private struct EmotionRecords: View {
    @Query private var entries: [EmotionEntry]
    init(interval: DateInterval) {
        let s = interval.start, e = interval.end
        _entries = Query(filter: #Predicate<EmotionEntry> { $0.eventDate >= s && $0.eventDate < e }, sort: \.eventDate, order: .reverse)
    }
    var body: some View {
        RecordsCard(rows: entries.filter { !$0.isEmpty }.map {
            RecordRowModel(id: $0.id.uuidString, date: $0.eventDate, title: $0.emotions.map { "\($0.emoji) \($0.label)" }.joined(separator: ", "),
                           subtitle: DiaryDefaults.trimmed($0.note ?? ""), sheet: .emotion(editing: $0.id))
        })
    }
}

private struct ImpulseRecords: View {
    @Query private var entries: [ImpulseEntry]
    init(interval: DateInterval) {
        let s = interval.start, e = interval.end
        _entries = Query(filter: #Predicate<ImpulseEntry> { $0.eventDate >= s && $0.eventDate < e }, sort: \.eventDate, order: .reverse)
    }
    var body: some View {
        RecordsCard(rows: entries.map {
            RecordRowModel(id: $0.id.uuidString, date: $0.eventDate, title: "\($0.category.emoji) \($0.category.label)",
                           subtitle: [DiaryDefaults.trimmed($0.detailLine), DiaryDefaults.trimmed($0.note ?? "")].compactMap { $0 }.joined(separator: " · "),
                           sheet: .impulse(editing: $0.id))
        })
    }
}

private struct CycleRecords: View {
    @Query private var entries: [CycleEntry]
    init(interval: DateInterval) {
        let s = interval.start, e = interval.end
        _entries = Query(filter: #Predicate<CycleEntry> { $0.date >= s && $0.date < e }, sort: \.date, order: .reverse)
    }
    var body: some View {
        RecordsCard(rows: entries.map {
            RecordRowModel(id: $0.id.uuidString, date: $0.date, title: "\($0.kind.icon) \($0.kind.label)",
                           subtitle: DiaryDefaults.trimmed($0.note ?? ""), sheet: .cycle)
        })
    }
}

private struct MedicationRecords: View {
    @Query private var entries: [SupportEntry]
    init(interval: DateInterval) {
        let s = interval.start, e = interval.end
        _entries = Query(filter: #Predicate<SupportEntry> { $0.day >= s && $0.day < e }, sort: \.day, order: .reverse)
    }
    var body: some View {
        RecordsCard(rows: entries.map {
            RecordRowModel(id: $0.id.uuidString, date: $0.time ?? $0.day, title: "\($0.status.glyph) \($0.status.label)",
                           subtitle: DiaryDefaults.trimmed($0.note ?? ""), sheet: .support)
        })
    }
}
