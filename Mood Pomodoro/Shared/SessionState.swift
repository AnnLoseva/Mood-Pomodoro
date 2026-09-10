//
//  SessionState.swift
//  Mood Pomodoro
//
//  Compiled into both the app and the Live Activity widget. Kept free of
//  SwiftData so the widget can render `SessionActivityAttributes` without
//  pulling in the rest of the model graph.
//

import Foundation

/// A session's lifecycle state. Replaces the old standalone `isActive` /
/// `isPaused` booleans — those two together could never represent
/// "completed" or "cancelled" distinctly.
nonisolated enum SessionState: String, Codable, Sendable, Hashable {
    case active
    case paused
    case completed
    case cancelled
}
