//
//  ActivitiesAnalyticsView.swift
//  Mood Pomodoro
//

import SwiftUI
import SwiftData

struct ActivitiesAnalyticsView: View {
    @Query private var sessions: [FocusSession]

    private var stats: [ActivityStatistics] { AnalyticsService.activityStatistics(sessions: sessions) }

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                if stats.isEmpty {
                    Text(L("Недостаточно данных", "Not enough data"))
                        .font(.lora(14))
                        .foregroundStyle(AppTheme.inkSoft)
                } else {
                    ForEach(stats) { activity in
                        HStack {
                            Text(Ldata(activity.activityName))
                                .font(.lora(16, weight: .medium))
                                .foregroundStyle(AppTheme.ink)
                            Spacer()
                            if activity.hasEnoughData, let avg = activity.averageMood {
                                Text(String(format: "%.1f", avg))
                                    .font(.lora(16, weight: .semibold))
                                    .foregroundStyle(AppTheme.forest)
                            } else {
                                Text(L("мало данных", "little data"))
                                    .font(.lora(12))
                                    .foregroundStyle(AppTheme.inkSoft)
                            }
                        }
                        .padding(14)
                        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(AppTheme.parchmentCard))
                        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(AppTheme.border, lineWidth: 1.25))
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 24)
        }
    }
}
