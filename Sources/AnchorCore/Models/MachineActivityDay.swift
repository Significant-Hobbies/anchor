import Foundation
import SwiftData

/// Privacy-safe daily computer-presence totals from the Mac app.
///
/// Only aggregate active and actively-tracked seconds are stored. Anchor never
/// records app names, window titles, websites, keystrokes, or pointer events.
@Model
public final class MachineActivityDay {
    public var id: UUID = UUID()
    public var day: Date = Date()
    public var activeSeconds: Double = 0
    public var trackedSeconds: Double = 0
    public var createdAt: Date = Date()

    public init(
        id: UUID = UUID(),
        day: Date,
        activeSeconds: Double = 0,
        trackedSeconds: Double = 0,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.day = day
        self.activeSeconds = max(0, activeSeconds)
        self.trackedSeconds = max(0, trackedSeconds)
        self.createdAt = createdAt
    }

    public var untrackedSeconds: Double { max(0, activeSeconds - trackedSeconds) }
}
