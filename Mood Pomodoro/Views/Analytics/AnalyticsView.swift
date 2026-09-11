//
//  AnalyticsView.swift
//  Mood Pomodoro
//

import SwiftUI
import SwiftData

/// Four sections, per the spec: Обзор / Условия / Активности / Сравнить.
/// Deliberately not a dashboard — each section is a short scroll, not a wall
/// of charts.
struct AnalyticsView: View {
    private enum Section: String, CaseIterable, Identifiable {
        case overview
        case conditions
        case activities
        case compare
        var id: String { rawValue }

        var title: String {
            switch self {
            case .overview: return L("Обзор", "Overview")
            case .conditions: return L("Условия", "Conditions")
            case .activities: return L("Активности", "Activities")
            case .compare: return L("Сравнить", "Compare")
            }
        }
    }

    @Query private var allSessions: [FocusSession]
    @State private var section: Section = .overview
    @State private var showExport = false

    private var finishedOrActive: [FocusSession] { allSessions }
    private var hasAnyCheckIns: Bool { allSessions.contains { !($0.checkIns ?? []).isEmpty } }

    var body: some View {
        NavigationStack {
            ZStack {
                ForestBackdrop()

                if !hasAnyCheckIns {
                    emptyState
                } else {
                    VStack(spacing: 0) {
                        sectionPicker
                        Group {
                            switch section {
                            case .overview: OverviewAnalyticsView()
                            case .conditions: FactorsAnalyticsView()
                            case .activities: ActivitiesAnalyticsView()
                            case .compare: CompareAnalyticsView()
                            }
                        }
                    }
                }
            }
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text(L("Аналитика", "Analytics"))
                        .font(.lora(17, weight: .semibold))
                        .foregroundStyle(AppTheme.ink)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showExport = true
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .foregroundStyle(AppTheme.forest)
                    .accessibilityLabel(L("Экспорт", "Export"))
                }
            }
            .sheet(isPresented: $showExport) {
                ExportSheet()
            }
        }
    }

    private var sectionPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Section.allCases) { item in
                    let isSelected = item == section
                    Button {
                        section = item
                    } label: {
                        Text(item.title)
                            .font(.lora(13, weight: isSelected ? .semibold : .regular))
                            .foregroundStyle(isSelected ? AppTheme.parchmentCard : AppTheme.ink)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(Capsule().fill(isSelected ? AppTheme.forest : AppTheme.parchment.opacity(0.5)))
                            .overlay(Capsule().stroke(AppTheme.border, lineWidth: isSelected ? 0 : 1))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 8)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            MoodImage(mood: .neutral, size: 72)
            Text(L("Пока мало данных", "Not much data yet"))
                .font(.lora(19, weight: .semibold))
                .foregroundStyle(AppTheme.ink)
            Text(L("Аналитика появится после нескольких сессий", "Analytics will appear after a few sessions"))
                .font(.lora(14))
                .foregroundStyle(AppTheme.inkSoft)
                .multilineTextAlignment(.center)
        }
        .padding(28)
        .parchmentCard()
        .padding(.horizontal, 32)
    }
}
