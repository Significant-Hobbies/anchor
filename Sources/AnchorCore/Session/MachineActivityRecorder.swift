import Foundation
import SwiftData

/// Converts periodic idle-time observations into wall-clock activity totals.
/// Sampling decides only active versus away; it never drives focus elapsed time.
@MainActor
public final class MachineActivityRecorder {
    private let context: ModelContext
    private let calendar: Calendar
    private var lastObservedAt: Date?
    private var cachedDay: MachineActivityDay?
    private var unsavedSeconds: Double = 0

    public init(context: ModelContext, calendar: Calendar = .current) {
        self.context = context
        self.calendar = calendar
    }

    public func observe(idleSeconds: Double, isTracking: Bool, at timestamp: Date = Date()) {
        defer { lastObservedAt = timestamp }
        guard let lastObservedAt, timestamp >= lastObservedAt else { return }

        let interval = timestamp.timeIntervalSince(lastObservedAt)
        guard interval > 0 else { return }
        let away = min(interval, max(0, idleSeconds))
        let active = max(0, interval - away)
        guard active > 0 else { return }

        let record = record(for: timestamp)
        record.activeSeconds += active
        if isTracking { record.trackedSeconds += active }
        unsavedSeconds += interval

        if unsavedSeconds >= 60 {
            try? context.save()
            unsavedSeconds = 0
        }
    }

    public func flush() {
        guard unsavedSeconds > 0 else { return }
        try? context.save()
        unsavedSeconds = 0
    }

    private func record(for timestamp: Date) -> MachineActivityDay {
        let day = calendar.startOfDay(for: timestamp)
        if let cachedDay, calendar.isDate(cachedDay.day, inSameDayAs: day) {
            return cachedDay
        }

        let descriptor = FetchDescriptor<MachineActivityDay>(
            predicate: #Predicate { $0.day == day },
            sortBy: [SortDescriptor(\.createdAt)]
        )
        if let existing = try? context.fetch(descriptor).first {
            cachedDay = existing
            return existing
        }

        let created = MachineActivityDay(day: day)
        context.insert(created)
        cachedDay = created
        return created
    }
}
