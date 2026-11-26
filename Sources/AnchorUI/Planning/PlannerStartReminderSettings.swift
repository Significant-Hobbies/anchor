#if !os(watchOS)
import AnchorCore
import SwiftUI
import UserNotifications

struct PlannerStartReminderSettings: View {
    @AppStorage(PlannerStartReminder.leadKey) private var lead = PlannerStartReminder.defaultLead
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL
    @State private var authorization: UNAuthorizationStatus?
    @State private var alertsDisabled = false

    var body: some View {
        Card(padding: Space.lg) {
            VStack(alignment: .leading, spacing: Space.sm) {
                Picker("Entry reminders", selection: $lead) {
                    Text("Off").tag(-1)
                    Text("At start time").tag(0)
                    ForEach([1, 5, 10, 15, 30], id: \.self) { minutes in
                        Text("\(minutes) min before").tag(minutes)
                    }
                }
                .accessibilityIdentifier("anchor.planner.reminder-lead")
                if lead >= 0 {
                    Text("For upcoming entries on this device, including selected calendars.")
                        .font(.caption).foregroundStyle(.secondary)
                    if authorization == .notDetermined {
                        Button("Allow notifications") {
                            Task {
                                _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
                                await refresh()
                            }
                        }
                    } else if authorization == .denied || alertsDisabled {
                        Text("Turn on alerts for Anchor in notification settings.")
                            .font(.caption)
                        Button("Open notification settings") {
                            #if os(iOS)
                            if let url = URL(string: UIApplication.openNotificationSettingsURLString) { openURL(url) }
                            #else
                            if let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension") { openURL(url) }
                            #endif
                        }
                    }
                }
            }
        }
        .task(id: scenePhase) { if scenePhase == .active { await refresh() } }
        .onChange(of: lead) { Task { await refresh() } }
    }

    private func refresh() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        authorization = settings.authorizationStatus
        alertsDisabled = settings.alertSetting == .disabled
    }
}
#endif
