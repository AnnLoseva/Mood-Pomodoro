import Foundation

/// Coalesces overlapping async refresh work: a call that arrives while one
/// is running waits, then at most one follow-up runs with the latest request.
/// Used for HealthKit and CloudKit so a burst of notifications cannot stack
/// full reloads on the main actor.
actor RefreshCoalescer {
    private var inFlight: Task<Void, Never>?
    private var queued = false

    func run(_ work: @escaping @Sendable () async -> Void) async {
        if inFlight != nil {
            queued = true
            await inFlight?.value
            return
        }
        repeat {
            queued = false
            let task = Task { await work() }
            inFlight = task
            await task.value
            inFlight = nil
        } while queued
    }
}

/// Main-actor debounce + single-flight for CloudKit notifications, which
/// always arrive on the main queue.
@MainActor
final class MainDebouncedCoalescer {
    private var debounce: Task<Void, Never>?
    private var running = false
    private var queued = false

    func schedule(nanoseconds: UInt64 = 400_000_000, _ work: @escaping @MainActor () -> Void) {
        debounce?.cancel()
        debounce = Task { @MainActor in
            try? await Task.sleep(nanoseconds: nanoseconds)
            guard !Task.isCancelled else { return }
            if running {
                queued = true
                return
            }
            running = true
            defer { running = false }
            repeat {
                queued = false
                work()
            } while queued && !Task.isCancelled
        }
    }
}
