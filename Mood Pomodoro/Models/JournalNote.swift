//
//  JournalNote.swift
//  Mood Pomodoro
//

import Foundation
import SwiftData

/// A free-text line in the diary, placed at the moment it is *about*
/// (`timestamp`), which can be well before the moment it was written
/// (`createdAt`).
@Model
final class JournalNote {
    var id: UUID = UUID()
    var timestamp: Date = Date.now
    var text: String = ""
    var createdAt: Date = Date.now
    var updatedAt: Date = Date.now

    init(id: UUID = UUID(), timestamp: Date, text: String) {
        self.id = id
        self.timestamp = timestamp
        self.text = text
        self.createdAt = .now
        self.updatedAt = .now
    }
}
