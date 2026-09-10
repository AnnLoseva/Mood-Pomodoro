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
        case overview = "Обзор"
        case conditions = "Условия"
        case activities = "Активности"
        case compare = "Сравнить"
        var id: String { rawValue }
    }

    @Query private var allSessions: [FocusSession]
    @State private var section: Section = .overview

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
                    Text("Аналитика")
                        .font(.lora(17, weight: .semibold))
                        .foregroundStyle(AppTheme.ink)
                }
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
                        Text(item.rawValue)
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
            Text("Пока мало данных")
                .font(.lora(19, weight: .semibold))
                .foregroundStyle(AppTheme.ink)
            Text("Аналитика появится после нескольких сессий")
                .font(.lora(14))
                .foregroundStyle(AppTheme.inkSoft)
                .multilineTextAlignment(.center)
        }
        .padding(28)
        .parchmentCard()
        .padding(.horizontal, 32)
    }
}
