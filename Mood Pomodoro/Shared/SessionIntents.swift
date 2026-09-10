//
//  SessionIntents.swift
//  Mood Pomodoro
//
//  Compiled into both the app and the widget. `Button(intent:)` in the Live
//  Activity needs the intent types in the widget target; `perform()` itself
//  runs in the app process (LiveActivityIntent) — even if the app was
//  terminated, iOS relaunches it in the background. The widget never talks
//  to SwiftData: handlers are bound by the app at launch.
//

import ActivityKit
import AppIntents
import Foundation

enum SessionIntentBridge {
    nonisolated(unsafe) static var pauseHandler: (@Sendable (String) async -> Void)?
    nonisolated(unsafe) static var resumeHandler: (@Sendable (String) async -> Void)?
    nonisolated(unsafe) static var endHandler: (@Sendable (String) async -> Void)?
    nonisolated(unsafe) static var recordMoodHandler: (@Sendable (String, String) async -> Void)?
    nonisolated(unsafe) static var requestCheckInHandler: (@Sendable (String) async -> Void)?

    static func bind(
        pause: @escaping @Sendable (String) async -> Void,
        resume: @escaping @Sendable (String) async -> Void,
        end: @escaping @Sendable (String) async -> Void,
        recordMood: @escaping @Sendable (String, String) async -> Void,
        requestCheckIn: @escaping @Sendable (String) async -> Void
    ) {
        pauseHandler = pause
        resumeHandler = resume
        endHandler = end
        recordMoodHandler = recordMood
        requestCheckInHandler = requestCheckIn
    }
}

struct PauseSessionIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Пауза"
    static var openAppWhenRun: Bool = false

    @Parameter(title: "Session ID")
    var sessionID: String

    init() { sessionID = "" }
    init(sessionID: UUID) { self.sessionID = sessionID.uuidString }

    func perform() async throws -> some IntentResult {
        await SessionIntentBridge.pauseHandler?(sessionID)
        return .result()
    }
}

struct ResumeSessionIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Продолжить"
    static var openAppWhenRun: Bool = false

    @Parameter(title: "Session ID")
    var sessionID: String

    init() { sessionID = "" }
    init(sessionID: UUID) { self.sessionID = sessionID.uuidString }

    func perform() async throws -> some IntentResult {
        await SessionIntentBridge.resumeHandler?(sessionID)
        return .result()
    }
}

struct EndSessionIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Закончить"
    static var openAppWhenRun: Bool = false

    @Parameter(title: "Session ID")
    var sessionID: String

    init() { sessionID = "" }
    init(sessionID: UUID) { self.sessionID = sessionID.uuidString }

    func perform() async throws -> some IntentResult {
        await SessionIntentBridge.endHandler?(sessionID)
        return .result()
    }
}

/// Records a mood from the Live Activity without opening the app. Reason is
/// left nil — a follow-up notification can collect it, and the user can
/// always add it later. Mood itself is never blocked on a reason.
struct RecordMoodIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Как я сейчас"
    static var openAppWhenRun: Bool = false

    @Parameter(title: "Session ID")
    var sessionID: String

    @Parameter(title: "Mood")
    var moodRaw: String

    init() {
        sessionID = ""
        moodRaw = MoodLiveActivityButton.neutral.rawValue
    }

    init(sessionID: UUID, moodRaw: String) {
        self.sessionID = sessionID.uuidString
        self.moodRaw = moodRaw
    }

    func perform() async throws -> some IntentResult {
        await SessionIntentBridge.recordMoodHandler?(sessionID, moodRaw)
        return .result()
    }
}

/// Asks "Как ты?" via an immediate system notification (same mood actions
/// as the periodic reminder). Does **not** open the app.
struct OpenCheckInIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Как я сейчас"
    static var openAppWhenRun: Bool = false

    @Parameter(title: "Session ID")
    var sessionID: String

    init() { sessionID = "" }
    init(sessionID: UUID) { self.sessionID = sessionID.uuidString }

    func perform() async throws -> some IntentResult {
        await SessionIntentBridge.requestCheckInHandler?(sessionID)
        return .result()
    }
}

/// The five moods as the Live Activity widget knows them. Kept here so the
/// widget doesn't have to compile `Mood.swift`. Raw values match `Mood`.
enum MoodLiveActivityButton: String, CaseIterable, Sendable {
    case veryGood
    case good
    case neutral
    case tired
    case veryBad

    var emoji: String {
        switch self {
        case .veryGood: return "😍"
        case .good: return "😄"
        case .neutral: return "🙂"
        case .tired: return "🥲"
        case .veryBad: return "😭"
        }
    }
}
