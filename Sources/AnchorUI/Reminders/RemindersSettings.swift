#if os(macOS) || os(iOS)
import AnchorCore
import SwiftUI

/// The Reminders preference group. The toggle is device-local (UserDefaults),
/// the list picker only appears after permission is granted, and the status
/// line always states plainly what the last sync did.
public struct RemindersSettings: View {
    @Environment(\.anchorTheme) private var theme
    @ObservedObject private var coordinator: RemindersSyncCoordinator
    @AppStorage(RemindersSyncCoordinator.enabledKey) private var enabled = false
    @AppStorage(RemindersSyncCoordinator.listIDKey) private var listID = ""
    @AppStorage(RemindersSyncCoordinator.exportDetailsKey) private var exportDetails = false

    public init(coordinator: RemindersSyncCoordinator) {
        _coordinator = ObservedObject(wrappedValue: coordinator)
    }

    public var body: some View {
        PreferenceGroup("Reminders", subtitle: "Show today's plan in Apple Reminders") {
            VStack(alignment: .leading, spacing: Space.sm) {
                PreferenceInfoRow(
                    systemImage: "checklist",
                    title: "Sync planned blocks",
                    detail: "Creates one reminder per planned block for today and the next seven days. Completing either side updates the other."
                ) {
                    Toggle("", isOn: enabledBinding)
                        .labelsHidden()
                        .accessibilityLabel("Sync planned blocks to Reminders")
                }

                if enabled {
                    PreferenceDivider()

                    if coordinator.availableLists.count > 1 {
                        PreferenceInfoRow(
                            systemImage: "list.bullet",
                            title: "Reminders list",
                            detail: "Where new reminders appear"
                        ) {
                            Picker("", selection: $listID) {
                                Text("Default list").tag("")
                                ForEach(coordinator.availableLists) { list in
                                    Text(list.title).tag(list.id)
                                }
                            }
                            .labelsHidden()
                            .accessibilityLabel("Reminders list")
                        }
                        PreferenceDivider()
                    }

                    PreferenceInfoRow(
                        systemImage: "note.text",
                        title: "Include block details",
                        detail: "Off by default. Distraction and session notes are never exported."
                    ) {
                        Toggle("", isOn: $exportDetails)
                            .labelsHidden()
                            .accessibilityLabel("Include block details in reminders")
                    }
                }

                if let status = coordinator.status {
                    PreferenceDivider()
                    Text(status)
                        .font(.caption)
                        .foregroundStyle(theme.textSecondary)
                        .padding(.horizontal, Space.md)
                        .padding(.bottom, Space.sm)
                } else if enabled, let lastSync = coordinator.lastSyncedAt {
                    PreferenceDivider()
                    Text("Last synced \(lastSync.formatted(date: .omitted, time: .shortened))")
                        .font(.caption)
                        .foregroundStyle(theme.textTertiary)
                        .padding(.horizontal, Space.md)
                        .padding(.bottom, Space.sm)
                }
            }
        }
    }

    private var enabledBinding: Binding<Bool> {
        Binding(
            get: { enabled },
            set: { newValue in
                if newValue {
                    Task {
                        if await coordinator.enable() {
                            enabled = true
                        }
                    }
                } else {
                    enabled = false
                }
            }
        )
    }
}
#endif
