#if os(macOS) || os(iOS)
import AnchorCore
import SwiftData
import SwiftUI

/// The Google Calendar preference group. Accounts and calendar choices are
/// device-local; the status line always states plainly what the last sync did.
public struct CalendarSettings: View {
    @Environment(\.anchorTheme) private var theme
    @Environment(\.modelContext) private var context
    @Query(sort: \PlanBlock.plannedStart) private var planBlocks: [PlanBlock]
    @ObservedObject private var coordinator: CalendarSyncCoordinator

    public init(coordinator: CalendarSyncCoordinator) {
        _coordinator = ObservedObject(wrappedValue: coordinator)
    }

    public var body: some View {
        PreferenceGroup("Calendars", subtitle: "Bring real commitments into Today") {
            VStack(alignment: .leading, spacing: Space.sm) {
                if !coordinator.isConfigured {
                    PreferenceInfoRow(
                        systemImage: "calendar.badge.exclamationmark",
                        title: "Google Calendar",
                        detail: "Calendar import isn't configured in this build yet."
                    )
                } else {
                    PreferenceInfoRow(
                        systemImage: "calendar",
                        title: "Google Calendar",
                        detail: "Imports timed events as commitment blocks for today and the next seven days. Read-only — nothing is sent back."
                    ) {
                        Button(coordinator.isConnecting ? "Connecting…" : "Connect account") {
                            Task { await coordinator.connect() }
                        }
                        .buttonStyle(QuietButtonStyle(expands: false))
                        .disabled(coordinator.isConnecting)
                        .accessibilityIdentifier("anchor.calendar.connect")
                    }

                    ForEach(coordinator.accounts) { account in
                        PreferenceDivider()
                        accountSection(account)
                    }

                    if let status = coordinator.status {
                        PreferenceDivider()
                        Text(status)
                            .font(.caption)
                            .foregroundStyle(theme.textSecondary)
                            .padding(.horizontal, Space.md)
                            .padding(.bottom, Space.sm)
                    } else if !coordinator.accounts.isEmpty, let lastSync = coordinator.lastSyncedAt {
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
    }

    @ViewBuilder
    private func accountSection(_ account: ConnectedGoogleAccount) -> some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            HStack(spacing: Space.sm) {
                Image(systemName: "person.crop.circle")
                    .foregroundStyle(theme.textSecondary)
                    .frame(width: 28, height: 28)
                    .background(theme.textSecondary.opacity(0.10), in: .circle)
                VStack(alignment: .leading, spacing: 2) {
                    Text(account.displayName)
                        .font(.body.weight(.medium))
                        .foregroundStyle(theme.textPrimary)
                    if !account.email.isEmpty {
                        Text(account.email)
                            .font(.caption)
                            .foregroundStyle(theme.textSecondary)
                    }
                }
                Spacer(minLength: Space.sm)
                Menu {
                    Button("Refresh calendars", systemImage: "arrow.clockwise") {
                        Task { await coordinator.refreshCalendars(accountID: account.id) }
                    }
                    Button("Sync now", systemImage: "arrow.triangle.2.circlepath") {
                        Task { await coordinator.sync(context: context, blocks: planBlocks) }
                    }
                    Button("Disconnect", role: .destructive) {
                        Task {
                            await coordinator.disconnect(
                                accountID: account.id,
                                context: context,
                                blocks: planBlocks
                            )
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .frame(width: 32, height: 32)
                        .contentShape(.rect)
                }
                .menuIndicator(.hidden)
                .accessibilityLabel("More actions for \(account.displayName)")
            }
            .padding(.horizontal, Space.md)

            let calendars = coordinator.availableCalendars[account.id] ?? []
            if calendars.isEmpty {
                Text("No calendars loaded yet — refresh to list this account's calendars.")
                    .font(.caption)
                    .foregroundStyle(theme.textTertiary)
                    .padding(.horizontal, Space.md)
            } else {
                ForEach(calendars) { calendar in
                    Toggle(isOn: selectionBinding(accountID: account.id, calendarID: calendar.id)) {
                        HStack(spacing: Space.xs) {
                            Text(calendar.title)
                                .font(.subheadline)
                                .foregroundStyle(theme.textPrimary)
                            if calendar.isPrimary {
                                Text("Primary")
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(theme.textTertiary)
                            }
                        }
                    }
                    .tint(theme.accent)
                    .padding(.horizontal, Space.md)
                    .accessibilityIdentifier("anchor.calendar.toggle.\(calendar.id)")
                }
            }
        }
        .task {
            if (coordinator.availableCalendars[account.id] ?? []).isEmpty {
                await coordinator.refreshCalendars(accountID: account.id)
            }
        }
    }

    private func selectionBinding(accountID: String, calendarID: String) -> Binding<Bool> {
        Binding(
            get: { coordinator.isCalendarSelected(accountID: accountID, calendarID: calendarID) },
            set: { coordinator.setCalendarSelected(accountID: accountID, calendarID: calendarID, selected: $0) }
        )
    }
}
#endif
