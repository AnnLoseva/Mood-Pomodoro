//
//  ContentView.swift
//  Mood Pomodoro
//

import SwiftUI
import SwiftData

/// Root view. Adapts between a phone tab bar and an iPad sidebar based on
/// horizontal size class — one codebase, no separate iPhone/iPad targets.
struct ContentView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    var body: some View {
        Group {
            if horizontalSizeClass == .regular {
                iPadRootView()
            } else {
                iPhoneRootView()
            }
        }
        .tint(AppTheme.forest)
    }
}

private struct iPhoneRootView: View {
    var body: some View {
        TabView {
            HomeView()
                .tabItem { Label(L("Сейчас", "Now"), systemImage: "leaf.fill") }
            DiaryView()
                .tabItem { Label(L("Дневник", "Diary"), systemImage: "text.book.closed.fill") }
            HistoryView()
                .tabItem { Label(L("История", "History"), systemImage: "book.closed.fill") }
            AnalyticsView()
                .tabItem { Label(L("Аналитика", "Analytics"), systemImage: "chart.line.uptrend.xyaxis") }
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

    @State private var selection: SidebarSection? = .today

    var body: some View {
        NavigationSplitView {
            List(SidebarSection.allCases, selection: $selection) { section in
                Label {
                    Text(section.title).font(.lora(16))
                } icon: {
                    Image(systemName: section.icon)
                }
                .tag(section)
            }
            .scrollContentBackground(.hidden)
            .background(AppTheme.parchment)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Mood Pomodoro")
                        .font(.lora(18, weight: .semibold))
                        .foregroundStyle(AppTheme.ink)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    LanguageMenu()
                }
            }
        } detail: {
            switch selection ?? .today {
            case .today: DashboardView()
            case .diary: DiaryView()
            case .history: HistoryView()
            case .analytics: AnalyticsView()
            }
        }
    }
}

#Preview {
    let container = PersistenceController.makeContainer()
    return ContentView()
        .environment(SessionManager(container: container))
        .environment(ReasonsStore.shared)
        .environment(CycleStore(container: container))
        .environment(DiaryEntryStore(container: container))
        .modelContainer(container)
}
