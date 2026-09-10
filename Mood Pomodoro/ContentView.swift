//
//  ContentView.swift
//  Mood Pomodoro
//

import SwiftUI

/// Root view. Adapts between a phone tab bar and an iPad sidebar based on
/// horizontal size class — one codebase, no separate iPhone/iPad targets.
struct ContentView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    var body: some View {
        if horizontalSizeClass == .regular {
            iPadRootView()
        } else {
            iPhoneRootView()
        }
    }
}

private struct iPhoneRootView: View {
    var body: some View {
        TabView {
            HomeView()
                .tabItem { Label("Сегодня", systemImage: "circle.grid.2x2") }
            HistoryView()
                .tabItem { Label("История", systemImage: "clock") }
            AnalyticsView()
                .tabItem { Label("Аналитика", systemImage: "chart.bar") }
        }
    }
}

private struct iPadRootView: View {
    enum SidebarSection: String, Identifiable, CaseIterable {
        case today, history, analytics
        var id: String { rawValue }

        var title: String {
            switch self {
            case .today: return "Сегодня"
            case .history: return "История"
            case .analytics: return "Аналитика"
            }
        }

        var icon: String {
            switch self {
            case .today: return "circle.grid.2x2"
            case .history: return "clock"
            case .analytics: return "chart.bar"
            }
        }
    }

    @State private var selection: SidebarSection? = .today

    var body: some View {
        NavigationSplitView {
            List(SidebarSection.allCases, selection: $selection) { section in
                Label(section.title, systemImage: section.icon).tag(section)
            }
            .navigationTitle("Mood Pomodoro")
        } detail: {
            switch selection ?? .today {
            case .today: DashboardView()
            case .history: HistoryView()
            case .analytics: AnalyticsView()
            }
        }
    }
}

#Preview {
    ContentView()
        .environment(SessionManager(container: PersistenceController.makeContainer()))
        .environment(ReasonsStore.shared)
}
