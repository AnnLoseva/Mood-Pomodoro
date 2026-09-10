//
//  ContentView.swift
//  Mood Pomodoro
//

import SwiftUI

/// Root view. Adapts between a phone tab bar and an iPad sidebar based on
/// horizontal size class — one codebase, no separate iPhone/iPad targets.
struct ContentView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(CloudSyncStatus.self) private var cloudSync

    var body: some View {
        VStack(spacing: 0) {
            if let banner = cloudSync.bannerText {
                Text(banner)
                    .font(.lora(12))
                    .foregroundStyle(AppTheme.inkSoft)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity)
                    .background(AppTheme.parchmentCard.opacity(0.92))
            }
            Group {
                if horizontalSizeClass == .regular {
                    iPadRootView()
                } else {
                    iPhoneRootView()
                }
            }
        }
        .tint(AppTheme.forest)
    }
}

private struct iPhoneRootView: View {
    var body: some View {
        TabView {
            HomeView()
                .tabItem { Label("Сегодня", systemImage: "leaf.fill") }
            HistoryView()
                .tabItem { Label("История", systemImage: "book.closed.fill") }
            AnalyticsView()
                .tabItem { Label("Аналитика", systemImage: "chart.line.uptrend.xyaxis") }
        }
        .toolbarBackground(AppTheme.parchmentCard, for: .tabBar)
        .toolbarBackground(.visible, for: .tabBar)
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
            case .today: return "leaf.fill"
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
            }
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
        .environment(CloudSyncStatus())
}
