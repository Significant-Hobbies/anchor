import Foundation
import UserNotifications

public struct PlannerStartReminder: Equatable, Sendable {
    public static let leadKey = "anchor.planner.start-reminder.lead-minutes"
    public static let defaultLead = 1
    static let prefix = "anchor.planner.start."
    let id: UUID
    let title: String
    let start: Date

    public init(id: UUID, title: String, start: Date) {
        self.id = id
        self.title = title
        self.start = start
    }
}

struct ScheduledPlannerReminder: Codable, Equatable {
    let start: Date
    let fire: Date
}

public struct PlannerReminderUpdate: Equatable, Sendable {
    let entries: [PlannerStartReminder]
    let leadMinutes: Int

    public init(entries: [PlannerStartReminder], leadMinutes: Int) {
        self.entries = entries
        self.leadMinutes = leadMinutes
    }

    func requests(now: Date, otherPending: Int, scheduled: [String: ScheduledPlannerReminder] = [:]) -> [UNNotificationRequest] {
        guard leadMinutes >= 0 else { return [] }
        let lead = Double(leadMinutes) * 60
        let upcoming = entries.compactMap { entry -> (PlannerStartReminder, Date)? in
            guard entry.start > now else { return nil }
            let fire = entry.start.addingTimeInterval(-lead)
            if fire > now { return (entry, fire) }
            let previous = scheduled[PlannerStartReminder.prefix + entry.id.uuidString]
            // A newly added entry can already be inside its lead window. Alert at
            // its start, unless an alert for this same occurrence already came due.
            if let previous, previous.start == entry.start, previous.fire <= now { return nil }
            return (entry, entry.start)
        }
        // Leave room for the focus timer and other local alerts.
        let capacity = max(0, 60 - otherPending)
        return upcoming.sorted {
            ($0.1, $0.0.id.uuidString) < ($1.1, $1.0.id.uuidString)
        }.prefix(capacity).map { entry, fire in
            let content = UNMutableNotificationContent()
            content.title = entry.title
            content.body = fire == entry.start ? "Starts now" : "Starts in \(leadMinutes) min"
            content.userInfo = ["plannedStart": entry.start.timeIntervalSince1970]
            content.sound = .default
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = TimeZone(secondsFromGMT: 0)!
            let date = calendar.dateComponents([.calendar, .timeZone, .year, .month, .day, .hour, .minute, .second], from: fire)
            return UNNotificationRequest(identifier: PlannerStartReminder.prefix + entry.id.uuidString, content: content,
                                         trigger: UNCalendarNotificationTrigger(dateMatching: date, repeats: false))
        }
    }
}

extension SystemSessionCompletionNotifier {
    /// Serialize system-center mutations. An edit that arrives while authorization or an
    /// add is in flight always gets the last reconciliation.
    public func reconcileStartReminders(_ update: PlannerReminderUpdate, canRequestPermission: Bool) {
        nextStartReminderUpdate = (update, canRequestPermission)
        guard startReminderTask == nil else { return }
        startReminderTask = Task {
            while let (update, mayPrompt) = nextStartReminderUpdate {
                nextStartReminderUpdate = nil
                await applyStartReminders(update, canRequestPermission: mayPrompt)
            }
            startReminderTask = nil
        }
    }

    private func applyStartReminders(_ update: PlannerReminderUpdate, canRequestPermission: Bool) async {
        let pending = await center.pendingNotificationRequests()
        let ours = pending.filter { $0.identifier.hasPrefix(PlannerStartReminder.prefix) }
        let ledgerKey = "anchor.planner.start-reminder.scheduled"
        let now = Date()
        let saved = UserDefaults.standard.data(forKey: ledgerKey)
        let previous = saved.flatMap { try? JSONDecoder().decode([String: ScheduledPlannerReminder].self, from: $0) } ?? [:]
        var scheduled = previous.filter { $0.value.start > now }
        defer {
            if scheduled != previous, let data = try? JSONEncoder().encode(scheduled) {
                UserDefaults.standard.set(data, forKey: ledgerKey)
            }
        }
        var desired = update.requests(now: now, otherPending: pending.count - ours.count, scheduled: scheduled)
        if !desired.isEmpty {
            var status = await center.notificationSettings().authorizationStatus
            if status == .notDetermined && canRequestPermission {
                _ = try? await center.requestAuthorization(options: [.alert, .sound])
                status = await center.notificationSettings().authorizationStatus
            }
            var allowed = status == .authorized || status == .provisional
            #if os(iOS)
            allowed = allowed || status == .ephemeral
            #endif
            if !allowed { desired = [] }
        }
        guard nextStartReminderUpdate == nil else { return }
        let ids = Set(desired.map(\.identifier))
        let stale = ours.map(\.identifier).filter { !ids.contains($0) }
        if !stale.isEmpty {
            center.removePendingNotificationRequests(withIdentifiers: stale)
            // A canceled alert never fired. Re-enabling this calendar or its reminders
            // inside the lead window must still allow the at-start fallback.
            for id in stale where scheduled[id].map({ $0.fire > now }) == true {
                scheduled.removeValue(forKey: id)
            }
        }
        let existing = Dictionary(uniqueKeysWithValues: ours.map { ($0.identifier, $0) })
        for request in desired {
            if let old = existing[request.identifier], old.content.title == request.content.title,
               old.content.body == request.content.body,
               (old.trigger as? UNCalendarNotificationTrigger)?.dateComponents == (request.trigger as? UNCalendarNotificationTrigger)?.dateComponents {
                continue
            }
            guard nextStartReminderUpdate == nil else { return }
            do {
                try await center.add(request)
                if let start = request.content.userInfo["plannedStart"] as? Double,
                   let fire = (request.trigger as? UNCalendarNotificationTrigger)?.dateComponents.date {
                    scheduled[request.identifier] = ScheduledPlannerReminder(start: Date(timeIntervalSince1970: start), fire: fire)
                }
            } catch {
                // Retry on the next reconciliation while the entry is still upcoming.
                continue
            }
        }
    }
}
