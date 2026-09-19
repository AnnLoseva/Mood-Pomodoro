//
//  ContentView.swift
//  Mood Pomodoro
//

import SwiftUI
import SwiftData

private struct IPadSidebarHiddenKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var iPadSidebarHidden: Bool {
        get { self[IPadSidebarHiddenKey.self] }
        set { self[IPadSidebarHiddenKey.self] = newValue }
    }
}

@Observable
final class AppTabs {
    enum Tab: Hashable {
        case today, diary, history, analytics
    }

    var selected: Tab = .today
    var diaryDay: Date?

    func openDiary(day: Date) {
        diaryDay = day
        selected = .diary
    }
}

/// Root view. Adapts between a phone tab bar and an iPad sidebar based on
/// horizontal size class — one codebase, no separate iPhone/iPad targets.
struct ContentView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(SessionManager.self) private var sessionManager
    @Environment(TodoIntegrationCoordinator.self) private var integration
    @State private var tabs = AppTabs()

    var body: some View {
        Group {
            if horizontalSizeClass == .regular {
                iPadRootView()
            } else {
                iPhoneRootView()
            }
        }
        .environment(tabs)
        .goblinChrome()
        .onOpenURL { url in
            // A task from ToDo List: bring the start screen (or the running
            // session) forward. Anything else is ignored.
            if integration.handle(url: url, activeSession: sessionManager.activeSession) {
                tabs.selected = .today
            }
        }
        .sheet(item: Binding(get: { integration.prompt }, set: { integration.prompt = $0 })) { prompt in
            TodoSessionPromptSheet(prompt: prompt)
        }
    }
}

private struct iPhoneRootView: View {
    @Environment(AppTabs.self) private var tabs

    var body: some View {
        @Bindable var tabs = tabs
        TabView(selection: $tabs.selected) {
            HomeView()
                .tabItem { Label(L("Сейчас", "Now"), systemImage: "leaf.fill") }
                .tag(AppTabs.Tab.today)
            DiaryView()
                .tabItem { Label(L("Дневник", "Diary"), systemImage: "text.book.closed.fill") }
                .tag(AppTabs.Tab.diary)
            HistoryView()
                .tabItem { Label(L("История", "History"), systemImage: "book.closed.fill") }
                .tag(AppTabs.Tab.history)
            AnalyticsView()
                .tabItem { Label(L("Аналитика", "Analytics"), systemImage: "chart.line.uptrend.xyaxis") }
                .tag(AppTabs.Tab.analytics)
        }
        .toolbarBackground(AppTheme.parchmentCard, for: .tabBar)
        .toolbarBackground(.visible, for: .tabBar)
    }
}

private struct iPadRootView: View {
    enum SidebarSection: String, Identifiable, CaseIterable {
        case today, diary, history, analytics
        var id: String { rawValue }

        var title: String {
            switch self {
            case .today: return L("Сейчас", "Now")
            case .diary: return L("Дневник", "Diary")
            case .history: return L("История", "History")
            case .analytics: return L("Аналитика", "Analytics")
            }
        }

        var icon: String {
            switch self {
            case .today: return "leaf.fill"
            case .diary: return "text.book.closed.fill"
            case .history: return "book.closed.fill"
            case .analytics: return "chart.line.uptrend.xyaxis"
            }
        }
    }

    @Environment(AppTabs.self) private var tabs
    @State private var selection: SidebarSection? = .today
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    private var sidebarHidden: Bool { columnVisibility == .detailOnly }

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    sidebarToggle
                    LanguageMenu()
                        .frame(width: 44, height: 36)
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.top, 8)
                .padding(.bottom, 4)
                List(SidebarSection.allCases, selection: $selection) { section in
                    Label {
                        Text(section.title)
                            .font(.lora(16))
                            .foregroundStyle(AppTheme.ink)
                    } icon: {
                        Image(systemName: section.icon)
                            .foregroundStyle(AppTheme.forest)
                    }
                    .listRowBackground(AppTheme.parchmentCard)
                    .tag(section)
                }
                .scrollContentBackground(.hidden)
            }
            .background(AppTheme.parchment)
            .hideRootNavigationBar()
        } detail: {
            Group {
                switch selection ?? .today {
                case .today: DashboardView()
                case .diary: DiaryView()
                case .history: HistoryView()
                case .analytics: AnalyticsView()
                }
            }
            .hideRootNavigationBar()
            .environment(\.iPadSidebarHidden, sidebarHidden)
            .overlay(alignment: .topLeading) {
                if sidebarHidden {
                    sidebarToggle
                        .padding(.leading, 10)
                        .padding(.top, 6)
                }
            }
        }
        .onChange(of: tabs.selected) { _, selected in
            switch selected {
            case .today: selection = .today
            case .diary: selection = .diary
            case .history: selection = .history
            case .analytics: selection = .analytics
            }
        }
    }

    private var sidebarToggle: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                columnVisibility = sidebarHidden ? .all : .detailOnly
            }
        } label: {
            Image(systemName: "sidebar.leading")
                .font(.body.weight(.medium))
                .foregroundStyle(AppTheme.forest)
                .frame(width: 36, height: 36)
                .background(Circle().fill(AppTheme.parchmentCard))
                .overlay(Circle().stroke(AppTheme.border, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
            sidebarHidden
                ? L("Показать боковую панель", "Show sidebar")
                : L("Скрыть боковую панель", "Hide sidebar")
        )
    }
}

#Preview {
    let container = PersistenceController.makeContainer()
    return ContentView()
        .environment(SessionManager(container: container))
        .environment(ReasonsStore.shared)
        .environment(CycleStore(container: container))
        .environment(DiaryEntryStore(container: container))
        .environment(SleepStore())
        .environment(TodoIntegrationCoordinator())
        .modelContainer(container)
}
