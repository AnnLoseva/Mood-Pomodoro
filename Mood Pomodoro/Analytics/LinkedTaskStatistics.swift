//
//  LinkedTaskStatistics.swift
//  Mood Pomodoro
//

import Foundation

/// Time spent in sessions that came from one ToDo List task. Several sessions
/// can belong to the same task, so this groups by `sourceTaskID`.
///
/// It is only a sum of what was done. It says nothing about how much of the
/// task is finished (a long session on a hard task can leave it half done),
/// and it never combines the task, the session's type or the mood recorded
/// during it into one figure.
struct LinkedTaskStatistics: Identifiable, Equatable {
    var id: UUID { taskID }
    let taskID: UUID
    /// The name at the time of the latest session, for display only.
    let title: String?
    let sessionCount: Int
    let activeDuration: TimeInterval
}

extension AnalyticsService {
    /// Finished sessions grouped by the task they were started from, most
    /// time first. Standalone sessions are not in the result.
    static func linkedTaskStatistics(sessions: [FocusSession]) -> [LinkedTaskStatistics] {
        let linked = sessions.filter { $0.sourceTaskID != nil && $0.state == .completed }
        return Dictionary(grouping: linked) { $0.sourceTaskID! }
            .map { taskID, group in
                LinkedTaskStatistics(
                    taskID: taskID,
                    title: group.max { $0.startDate < $1.startDate }?.sourceTaskTitle,
                    sessionCount: group.count,
                    activeDuration: group.reduce(0) { $0 + $1.activeWorkDuration() }
                )
            }
            .sorted { $0.activeDuration == $1.activeDuration ? $0.taskID.uuidString < $1.taskID.uuidString : $0.activeDuration > $1.activeDuration }
    }
}
