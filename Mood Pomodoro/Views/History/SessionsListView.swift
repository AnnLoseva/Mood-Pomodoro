//
//  SessionsListView.swift
//  Mood Pomodoro
//
//  The finished sessions of the chosen analytics period, newest first — what
//  the "История" tab used to be, now one step inside Аналитика → Занятия.
//  Every row opens the one `SessionDetailView`; swipe deletes after a
//  confirmation, exactly like the details screen does.
//

import SwiftUI
import SwiftData

struct SessionsListView: View {
    /// Narrows the list to one activity (by canonical name); nil lists all.
    let activity: String?
    @Bindable var store: AnalyticsStore

    @State private var limit = Self.pageSize
    private static let pageSize = 60

    var body: some View {
        let interval = store.period.interval(earliest: store.facts.earliest)
        ZStack {
            ForestBackdrop()
            SessionsListBody(
                interval: interval,
                activity: activity,
                limit: limit,
                onMore: { limit += Self.pageSize }
            )
            .id("\(interval.start.timeIntervalSince1970)-\(interval.end.timeIntervalSince1970)-\(activity ?? "")")
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text(activity.map { Ldata($0) } ?? L("Все сессии", "All sessions"))
                    .font(.lora(17, weight: .semibold))
                    .foregroundStyle(AppTheme.ink)
                    .lineLimit(1)
            }
            ToolbarItem(placement: .topBarTrailing) { AnalyticsPeriodMenu(store: store) }
        }
        .goblinChrome()
        .onChange(of: store.period) { _, _ in limit = Self.pageSize }
    }
}

private struct SessionsListBody: View {
    let activity: String?
    let limit: Int
    let onMore: () -> Void

    @Environment(SessionManager.self) private var sessionManager
    @Query private var fetched: [FocusSession]
    @State private var pendingDelete: FocusSession?
    @State private var showDeleteConfirm = false

    init(interval: DateInterval, activity: String?, limit: Int, onMore: @escaping () -> Void) {
        self.activity = activity
        self.limit = limit
        self.onMore = onMore
        let start = interval.start
        let end = interval.end
        var descriptor = FetchDescriptor<FocusSession>(
            predicate: #Predicate { $0.startDate >= start && $0.startDate < end },
            sortBy: [SortDescriptor(\.startDate, order: .reverse)]
        )
        // Names are grouped by their canonical form, which a predicate can't
        // compute — so an activity's list reads its whole period; the
        // unfiltered list reads one page at a time.
        if activity == nil { descriptor.fetchLimit = limit }
        _fetched = Query(descriptor)
    }

    private var sessions: [FocusSession] {
        fetched.filter { session in
            guard !session.isActive else { return false }
            guard let activity else { return true }
            return canonicalData(session.activity) == activity
        }
    }

    private var sections: [(day: Date, sessions: [FocusSession])] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: sessions) { calendar.startOfDay(for: $0.startDate) }
        return grouped.keys.sorted(by: >).map { day in
            (day, (grouped[day] ?? []).sorted { $0.startDate > $1.startDate })
        }
    }

    var body: some View {
        let sections = sections
        if sections.isEmpty {
            VStack(spacing: 8) {
                Text(L("В этом периоде сессий нет", "No sessions in this period"))
                    .font(.lora(17, weight: .semibold))
                    .foregroundStyle(AppTheme.ink)
                Text(L("Другой период — в меню сверху.", "Pick another period in the menu above."))
                    .font(.lora(13))
                    .foregroundStyle(AppTheme.inkSoft)
            }
            .padding(24)
            .parchmentCard(padding: 0)
            .padding(.horizontal, 32)
        } else {
            List {
                ForEach(sections, id: \.day) { section in
                    Section {
                        ForEach(section.sessions, id: \.id) { session in
                            NavigationLink(value: AnalyticsRoute.session(session.id)) {
                                SessionRow(session: session)
                            }
                            .buttonStyle(.plain)
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                            .listRowInsets(EdgeInsets(top: 5, leading: 16, bottom: 5, trailing: 16))
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button(role: .destructive) {
                                    pendingDelete = session
                                    showDeleteConfirm = true
                                } label: {
                                    Label(L("Удалить", "Delete"), systemImage: "trash")
                                }
                            }
                        }
                    } header: {
                        Text(DateFormatting.historySectionTitle(section.day))
                            .font(.lora(13, weight: .semibold))
                            .foregroundStyle(AppTheme.inkSoft)
                            .textCase(nil)
                    }
                }
                if activity == nil, fetched.count >= limit {
                    Button(L("Показать ещё", "Show more"), action: onMore)
                        .buttonStyle(AnalyticsSmallButtonStyle())
                        .frame(maxWidth: .infinity)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .frame(maxWidth: 760)
            .frame(maxWidth: .infinity)
            .goblinConfirmation(
                isPresented: $showDeleteConfirm,
                title: L("Удалить сессию?", "Delete the session?"),
                message: L("Она исчезнет из дневника и больше не попадёт в аналитику.", "It will disappear from the diary and won't count in analytics anymore."),
                confirmTitle: L("Удалить", "Delete"),
                isDestructive: true,
                onConfirm: {
                    if let session = pendingDelete { sessionManager.delete(session) }
                    pendingDelete = nil
                }
            )
        }
    }
}

struct SessionRow: View {
    let session: FocusSession

    var body: some View {
        HStack(spacing: 14) {
            if let mood = session.sortedCheckIns.last?.mood {
                MoodImage(mood: mood, size: 44)
            } else {
                Text("🍄")
                    .font(.system(size: 28))
                    .frame(width: 44, height: 44)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(Ldata(session.activity))
                    .font(.lora(17, weight: .medium))
                    .foregroundStyle(AppTheme.ink)
                if let title = session.sourceTaskTitle {
                    Text(L("Задача: \(title)", "Task: \(title)"))
                        .font(.lora(12))
                        .foregroundStyle(AppTheme.forest)
                        .lineLimit(1)
                }
                Text(DateFormatting.fullDate(session.startDate))
                    .font(.lora(13))
                    .foregroundStyle(AppTheme.inkSoft)
                Text(DateFormatting.timeRange(from: session.startDate, to: session.endDate))
                    .font(.lora(13).monospacedDigit())
                    .foregroundStyle(AppTheme.inkSoft)
                Text(durationLine)
                    .font(.lora(13))
                    .foregroundStyle(AppTheme.inkSoft)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.footnote)
                .foregroundStyle(AppTheme.inkSoft)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(AppTheme.parchmentCard)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(AppTheme.border, lineWidth: 1.25)
        )
        .accessibilityElement(children: .combine)
    }

    private var durationLine: String {
        let total = DurationFormatting.compact(session.totalDuration())
        let count = session.checkIns?.count ?? 0
        let checkIns = checkInCount(count)
        if session.breakDuration() > 0 {
            let active = DurationFormatting.compact(session.activeWorkDuration())
            let pause = DurationFormatting.compact(session.breakDuration())
            return L("\(total) · \(active) активно · \(pause) перерыв · \(checkIns)", "\(total) · \(active) active · \(pause) break · \(checkIns)")
        }
        return "\(total) · \(checkIns)"
    }
}
