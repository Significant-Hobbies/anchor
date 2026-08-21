import Foundation
import UserNotifications

/// Keeps notification delivery outside the session state machine. Tests use a
/// recording implementation; the apps inject the system implementation.
@MainActor
public protocol SessionCompletionNotifying: AnyObject {
    func schedule(sessionID: UUID, intent: String, after delay: TimeInterval)
    func cancel(sessionID: UUID)
}

@MainActor
public final class NoopSessionCompletionNotifier: SessionCompletionNotifying {
    public init() {}
    public func schedule(sessionID: UUID, intent: String, after delay: TimeInterval) {}
    public func cancel(sessionID: UUID) {}
}

/// Schedules one local notification for the exact wall-clock finish time.
/// Permission is requested lazily when the first planned session starts.
@MainActor
public final class SystemSessionCompletionNotifier: NSObject, SessionCompletionNotifying,
    UNUserNotificationCenterDelegate
{
    private let center: UNUserNotificationCenter
    private var schedulingTask: Task<Void, Never>?
    private var lastIdentifier: String?

    public override init() {
        self.center = .current()
        super.init()
        center.delegate = self
    }

    public func schedule(sessionID: UUID, intent: String, after delay: TimeInterval) {
        schedulingTask?.cancel()
        if let lastIdentifier {
            center.removePendingNotificationRequests(withIdentifiers: [lastIdentifier])
        }

        let identifier = Self.identifier(for: sessionID)
        lastIdentifier = identifier
        let content = UNMutableNotificationContent()
        content.title = "Focus complete"
        content.body = intent.isEmpty ? "Your focus session is complete." : "“\(intent)” is complete."
        content.sound = .default

        // Notification triggers require a positive interval. A restored session
        // that elapsed while the app was closed should notify immediately.
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, delay), repeats: false)
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)

        schedulingTask = Task { [center] in
            do {
                let allowed = try await center.requestAuthorization(options: [.alert, .sound])
                guard allowed, !Task.isCancelled else { return }
                try await center.add(request)
            } catch {
                // Notifications are supplementary. A denied permission or
                // scheduling failure must never make the timer unusable.
            }
        }
    }

    public func cancel(sessionID: UUID) {
        schedulingTask?.cancel()
        schedulingTask = nil
        let identifier = Self.identifier(for: sessionID)
        center.removePendingNotificationRequests(withIdentifiers: [identifier])
        if lastIdentifier == identifier { lastIdentifier = nil }
    }

    nonisolated public func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping @Sendable (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }

    private static func identifier(for sessionID: UUID) -> String {
        "anchor.session.\(sessionID.uuidString).complete"
    }
}
