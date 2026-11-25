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

    private let inSheet: Bool

    public init(coordinator: CalendarSyncCoordinator, inSheet: Bool = false) {
        self.inSheet = inSheet
        _coordinator = ObservedObject(wrappedValue: coordinator)
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: Space.md) {
            if !inSheet {
                Label("Google Calendar", systemImage: "calendar").font(.headline)
            }
            if let issue = coordinator.connectionIssue {
                Label(issue, systemImage: "exclamationmark.triangle")
                    .font(.subheadline).foregroundStyle(theme.caution)
            }
            if !coordinator.isConfigured {
                Text("Calendar import is unavailable in this build.")
                    .foregroundStyle(theme.textSecondary)
            } else if coordinator.accounts.isEmpty {
                Text("Connect Google Calendar to see timed events in the day or week you open.")
                    .foregroundStyle(theme.textSecondary)
                connectButton
                syncStatus
            } else {
                syncStatus
                ForEach(coordinator.accounts) { account in
                    accountSection(account)
                }
                connectButton
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var connectButton: some View {
        Button {
            Task { await coordinator.connect() }
        } label: {
            Label(coordinator.isConnecting ? "Connecting…" :
                    (coordinator.accounts.isEmpty ? "Connect account" : "Add another account"),
                  systemImage: "plus")
        }
        .buttonStyle(.borderless)
        .disabled(coordinator.isConnecting)
        .accessibilityIdentifier("anchor.calendar.connect")
    }

    @ViewBuilder private var syncStatus: some View {
        if let status = coordinator.status {
            Text(status).font(.subheadline).foregroundStyle(theme.textSecondary)
        } else if !coordinator.accounts.isEmpty, let lastSync = coordinator.lastSyncedAt {
            Text("Last synced \(lastSync.formatted(date: .omitted, time: .shortened))")
                .font(.subheadline).foregroundStyle(theme.textSecondary)
        }
    }

    private func accountSection(_ account: ConnectedGoogleAccount) -> some View {
        let calendars = coordinator.availableCalendars[account.id] ?? []
        let ordered = calendars.filter(\.isPrimary) + calendars.filter { !$0.isPrimary }
        return VStack(alignment: .leading, spacing: Space.sm) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(account.displayName.isEmpty ? account.email : account.displayName)
                        .font(.headline)
                    if !account.displayName.isEmpty, !account.email.isEmpty,
                       account.displayName.caseInsensitiveCompare(account.email) != .orderedSame {
                        Text(account.email).font(.caption).foregroundStyle(theme.textSecondary)
                    }
                }
                Spacer()
                Menu {
                    Button("Refresh calendars", systemImage: "arrow.clockwise") {
                        Task { await coordinator.refreshCalendars(accountID: account.id) }
                    }
                    Button("Sync now", systemImage: "arrow.triangle.2.circlepath") {
                        Task { await coordinator.sync(context: context, blocks: planBlocks) }
                    }
                    Button("Disconnect", role: .destructive) {
                        Task {
                            await coordinator.disconnect(accountID: account.id, context: context, blocks: planBlocks)
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle").font(.title3)
                        .frame(minWidth: 32, minHeight: 32)
                }
                #if os(macOS)
                .menuStyle(.borderlessButton)
                #endif
                .menuIndicator(.hidden)
                .fixedSize()
                .accessibilityLabel("More actions for \(account.displayName)")
            }
            if let issue = coordinator.calendarListIssues[account.id] {
                Text(issue).font(.subheadline).foregroundStyle(theme.caution)
            }
            if calendars.isEmpty {
                Text("Refresh calendars from the account menu to load the list.")
                    .font(.subheadline).foregroundStyle(theme.textSecondary)
            } else {
                Text("Show in Today").font(.subheadline.weight(.medium)).foregroundStyle(theme.textSecondary)
                VStack(spacing: 0) {
                    ForEach(ordered) { calendar in
                        if calendar.id != ordered.first?.id { Divider() }
                        Toggle(isOn: selectionBinding(accountID: account.id, calendarID: calendar.id)) {
                            HStack(spacing: Space.xs) {
                                let usesAddress = calendar.isPrimary && calendar.title.caseInsensitiveCompare(account.email) == .orderedSame
                                Text(usesAddress ? "Primary calendar" : calendar.title)
                                if calendar.isPrimary && !usesAddress {
                                    Text("Primary").font(.caption).foregroundStyle(theme.textSecondary)
                                }
                                Spacer(minLength: 0)
                            }
                            .frame(minHeight: 40)
                            .contentShape(Rectangle())
                        }
                        .padding(.horizontal, Space.sm)
                        .accessibilityIdentifier("anchor.calendar.toggle.\(calendar.id)")
                    }
                }
                .padding(.horizontal, Space.xs)
                .background(theme.surface, in: .rect(cornerRadius: Radius.md))
                .overlay { RoundedRectangle(cornerRadius: Radius.md).strokeBorder(theme.hairline) }
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
