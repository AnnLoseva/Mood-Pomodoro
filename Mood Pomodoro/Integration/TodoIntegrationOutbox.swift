//
//  TodoIntegrationOutbox.swift
//  Mood Pomodoro
//

import Foundation

/// The durable queue of things to tell ToDo List.
///
/// A plain JSON file, on purpose: it lives beside the app's data but outside
/// the SwiftData/CloudKit container, so the diary's schema and its sync are
/// untouched and nothing here can leak into iCloud. It survives a restart,
/// needs no network and no second app, and is written atomically so a crash
/// mid-write leaves the previous file intact.
///
/// One process writes it (this app). If it is ever moved into a shared
/// container the write must go through `NSFileCoordinator`.
@MainActor
final class TodoIntegrationOutbox {
    /// Bounded so a receiver that never appears cannot grow the file forever.
    static let capacity = 500

    private let fileURL: URL
    private(set) var events: [TodoIntegrationEvent] = []

    nonisolated static func defaultFileURL(fileManager: FileManager = .default) -> URL {
        let base = (try? fileManager.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true))
            ?? fileManager.temporaryDirectory
        let folder = base.appendingPathComponent("Integration", isDirectory: true)
        try? fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appendingPathComponent("todo-outbox.json")
    }

    init(fileURL: URL = TodoIntegrationOutbox.defaultFileURL()) {
        self.fileURL = fileURL
        load()
    }

    // MARK: - Reading

    func event(withID id: String) -> TodoIntegrationEvent? {
        events.first { $0.id == id }
    }

    /// Events still to be given to the other app, oldest first.
    func queued(where matches: (TodoIntegrationEventType) -> Bool = { _ in true }) -> [TodoIntegrationEvent] {
        events.filter { $0.delivery == .queued && matches($0.type) }.sorted { $0.createdAt < $1.createdAt }
    }

    // MARK: - Writing

    /// Adds an event. The same operation (same id) is never added twice: a
    /// repeated tap or a re-delivered signal returns what is already there,
    /// with its delivery state. A newer state of the same session replaces
    /// the older one, so the other app is only ever told the latest.
    @discardableResult
    func enqueue(_ event: TodoIntegrationEvent) -> TodoIntegrationEvent {
        if let existing = self.event(withID: event.id) { return existing }

        if let index = events.firstIndex(where: { $0.coalescingKey == event.coalescingKey }) {
            let previous = events[index]
            if event.type == .sessionDeleted, previous.delivery == .queued, previous.type != .sessionDeleted {
                // The other app never heard of this session; there is
                // nothing to take back.
                events.remove(at: index)
                persist()
                return event
            }
            events[index] = event
        } else {
            events.append(event)
        }
        if events.count > Self.capacity {
            events.removeFirst(events.count - Self.capacity)
        }
        persist()
        return event
    }

    func markAttempted(_ id: String, at date: Date = .now) {
        update(id) { $0.attempts += 1; $0.lastAttemptAt = date }
    }

    func markHandedOff(_ id: String, at date: Date = .now) {
        update(id) { $0.delivery = .handedOff; $0.lastAttemptAt = date }
    }

    /// In a silent channel (mailbox / iCloud). Not the same as acknowledged.
    func markDelivered(_ id: String, at date: Date = .now) {
        update(id) { $0.delivery = .delivered; $0.lastAttemptAt = date }
    }

    /// ToDo List understood the event and refused it; retrying the same thing cannot help.
    func markRejected(_ id: String, reason: String) {
        update(id) { $0.delivery = .rejected; $0.rejectionReason = reason }
    }

    /// Events that left this app but that ToDo List has not answered yet.
    func awaitingReceipt() -> [TodoIntegrationEvent] {
        events.filter { $0.delivery == .delivered || $0.delivery == .handedOff }
    }

    /// Answered events are forgotten after a month; nothing lives here forever.
    func pruneSettled(olderThan cutoff: Date) {
        let before = events.count
        events.removeAll { ($0.delivery == .delivered || $0.delivery == .rejected) && $0.createdAt < cutoff }
        if events.count != before { persist() }
    }

    /// The other app confirmed it processed the event; nothing left to keep.
    func acknowledge(_ id: String) {
        events.removeAll { $0.id == id }
        persist()
    }

    private func update(_ id: String, _ change: (inout TodoIntegrationEvent) -> Void) {
        guard let index = events.firstIndex(where: { $0.id == id }) else { return }
        change(&events[index])
        persist()
    }

    // MARK: - Storage

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        do {
            events = try decoder.decode([TodoIntegrationEvent].self, from: data)
        } catch {
            // Never discard what cannot be read: set it aside, start clean.
            let aside = fileURL.deletingLastPathComponent()
                .appendingPathComponent("todo-outbox.unreadable-\(Int(Date().timeIntervalSince1970)).json")
            try? FileManager.default.moveItem(at: fileURL, to: aside)
            events = []
        }
    }

    private func persist() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(events) else { return }
        try? data.write(to: fileURL, options: [.atomic])
    }
}
