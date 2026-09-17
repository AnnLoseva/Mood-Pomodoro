import Foundation
import os

/// DEBUG-only timing around the hot paths. Names only — never the contents
/// of a note, a mood, a dose or a night.
enum PerfSignpost {
    static let subsystem = "annloseva.Mood-Pomodoro"
    static let log = OSLog(subsystem: subsystem, category: "perf")

    @discardableResult
    static func interval<T>(_ name: StaticString, _ work: () throws -> T) rethrows -> T {
        #if DEBUG
        let signpost = OSSignpostID(log: log)
        os_signpost(.begin, log: log, name: name, signpostID: signpost)
        defer { os_signpost(.end, log: log, name: name, signpostID: signpost) }
        #endif
        return try work()
    }

    static func event(_ name: StaticString) {
        #if DEBUG
        os_signpost(.event, log: log, name: name)
        #endif
    }
}
