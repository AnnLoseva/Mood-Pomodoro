import SwiftUI
import SwiftData

/// One search over metrics, sections, activity and factor names, sessions and
/// dates. Used inside the analytics (results push onto its stack) and from
/// the diary (`onOpen` decides where a result goes).
struct AnalyticsSearchView: View {
    var store: AnalyticsStore?
    var onOpen: ((AnalyticsRoute) -> Void)?

    @Environment(\.modelContext) private var context
    @Environment(\.analyticsOpen) private var analyticsOpen
    @State private var query = ""
    @State private var sessions: [FocusSession] = []
    @State private var pickedDay = Date.now
    @FocusState private var focused: Bool

    private func open(_ route: AnalyticsRoute) {
        if let onOpen { onOpen(route) } else { analyticsOpen(route) }
    }

    private var entries: [AnalyticsSearchEntry] {
        var all = AnalyticsSearch.staticEntries()
        if let snapshot = store?.snapshot {
            all += AnalyticsSearch.dynamicEntries(
                activities: snapshot.activities.map(\.name),
                factors: snapshot.factors.map { ($0.optionName, $0.categoryID, $0.categoryName) }
            )
        }
        return all
    }

    private var trimmed: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        let matches = AnalyticsSearch.match(trimmed, in: entries)
        let day = AnalyticsSearch.parseDay(trimmed)
        ZStack {
            ForestBackdrop()
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    field
                    if trimmed.isEmpty {
                        dayPicker
                        AnalyticsQuietNote(text: L("Показатель, занятие, дата или слово из названия задачи.", "A metric, an activity, a date or a word from a task name."))
                    } else {
                        if let day { dayRow(day) }
                        if !matches.isEmpty { matchesCard(matches) }
                        if !sessions.isEmpty { sessionsCard }
                        if matches.isEmpty && sessions.isEmpty && day == nil {
                            AnalyticsQuietNote(text: L("Ничего не найдено.", "Nothing found."))
                        }
                    }
                }
                .frame(maxWidth: 640, alignment: .leading)
                .frame(maxWidth: .infinity)
                .padding(16)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text(L("Поиск", "Search")).font(.lora(17, weight: .semibold)).foregroundStyle(AppTheme.ink)
            }
        }
        .goblinChrome()
        .task(id: trimmed) {
            // A short pause so typing does not fetch on every key.
            try? await Task.sleep(for: .milliseconds(180))
            guard !Task.isCancelled else { return }
            sessions = SessionSearch.find(trimmed, in: context)
        }
        .onAppear { focused = true }
    }

    private var field: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(AppTheme.inkSoft)
            TextField(L("Сон, энергия, математика, 12.03…", "Sleep, energy, math, 12.03…"), text: $query)
                .font(.lora(16))
                .focused($focused)
                .submitLabel(.search)
                .autocorrectionDisabled()
            if !query.isEmpty {
                Button { query = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(AppTheme.inkSoft).frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L("Очистить", "Clear"))
            }
        }
        .padding(.leading, 14)
        .frame(minHeight: 48)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(AppTheme.parchmentCard))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(AppTheme.border, lineWidth: 1.25))
    }

    private var dayPicker: some View {
        HStack {
            DatePicker(L("Открыть день", "Open a day"), selection: $pickedDay, in: ...Date.now, displayedComponents: .date)
                .font(.lora(14))
            Button(L("Открыть", "Open")) { open(.day(Calendar.current.startOfDay(for: pickedDay))) }
                .buttonStyle(AnalyticsSmallButtonStyle())
        }
        .padding(14)
        .parchmentCard(padding: 0)
    }

    private func dayRow(_ day: Date) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            AnalyticsLinkRow(title: L("Открыть день: ", "Open day: ") + DateFormatting.fullDate(day)) { open(.day(day)) }
        }
        .padding(.horizontal, 16)
        .parchmentCard(padding: 0)
    }

    private func matchesCard(_ matches: [AnalyticsSearchEntry]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(matches.enumerated()), id: \.element.id) { index, entry in
                if index > 0 { Divider().overlay(AppTheme.border) }
                AnalyticsLinkRow(
                    title: entry.title,
                    subtitle: entry.subtitle,
                    leading: AnyView(
                        Image(systemName: entry.symbol)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(AppTheme.forest)
                            .frame(width: 22)
                    )
                ) { open(entry.route) }
            }
        }
        .padding(.horizontal, 16)
        .parchmentCard(padding: 0)
    }

    private var sessionsCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L("Сессии", "Sessions")).font(.lora(13, weight: .semibold)).foregroundStyle(AppTheme.inkSoft).padding(.horizontal, 4)
            ForEach(sessions, id: \.id) { session in
                Button { open(.session(session.id)) } label: { SessionRow(session: session) }
                    .buttonStyle(.plain)
            }
        }
    }
}
