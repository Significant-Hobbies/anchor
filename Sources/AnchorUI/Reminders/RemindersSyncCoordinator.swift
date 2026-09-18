#if os(macOS) || os(iOS)
import AnchorCore
import Foundation
import SwiftData

/// Bridges the pure `RemindersSyncService` to the app's SwiftData store and
/// device settings. Sync is opt-in and device-local: the toggle and chosen
/// list live in `UserDefaults`, never in the CloudKit-mirrored schema.
@MainActor
public final class RemindersSyncCoordinator: ObservableObject {
    public static let enabledKey = "anchor.reminders.enabled"
    public static let listIDKey = "anchor.reminders.list-id"
    public static let exportDetailsKey = "anchor.reminders.export-details"
    public static let lastSyncKey = "anchor.reminders.last-sync"

    @Published public private(set) var status: String?
    @Published public private(set) var availableLists: [ReminderListInfo] = []

    private var service: RemindersSyncService?
    private var store: (any RemindersStoreProtocol)?
    private var isSyncing = false

    public init() {}

    /// Injectable seam for tests and previews.
    public init(store: any RemindersStoreProtocol) {
        self.store = store
        self.service = RemindersSyncService(store: store)
    }

    private var defaults: UserDefaults { .standard }

    public var isEnabled: Bool { defaults.bool(forKey: Self.enabledKey) }
    public var selectedListID: String? { defaults.string(forKey: Self.listIDKey) }
    public var lastSyncedAt: Date? { defaults.object(forKey: Self.lastSyncKey) as? Date }

    /// Called when the toggle turns on: asks permission, loads lists, runs a
    /// first pass. Returns false when Reminders access was denied.
    @discardableResult
    public func enable() async -> Bool {
        let resolved = await resolvedService()
        guard let resolved else { status = "Reminders is unavailable on this device."; return false }
        do {
            guard try await resolved.store.requestAccess() else {
                status = "Anchor needs Reminders access. Enable it in System Settings."
                return false
            }
            availableLists = (try? await resolved.store.reminderLists()) ?? []
            status = nil
            return true
        } catch {
            status = "Reminders could not be reached."
            return false
        }
    }

    /// One reconcile pass over the current plan window. Applies link
    /// writebacks and external completions, then commits. Safe to call on
    /// every plan change — no-op blocks don't re-upsert.
    public func sync(context: ModelContext, blocks: [PlanBlock]) async {
        guard isEnabled, !isSyncing else { return }
        isSyncing = true
        defer { isSyncing = false }
        guard let resolved = await resolvedService() else { return }

        let records = blocks.map { $0.snapshot() }
        do {
            let report = try await resolved.service.sync(
                blocks: records,
                listID: selectedListID,
                exportDetails: defaults.bool(forKey: Self.exportDetailsKey)
            )
            apply(report: report, to: blocks, context: context)
            defaults.set(report.syncedAt, forKey: Self.lastSyncKey)
            status = report.upserted + report.deleted == 0
                ? "Reminders are up to date."
                : "Synced \(report.upserted) block\(report.upserted == 1 ? "" : "s") to Reminders."
        } catch {
            status = "Reminders sync failed; your plan is unchanged."
        }
    }

    private func apply(report: RemindersSyncReport, to blocks: [PlanBlock], context: ModelContext) {
        let byID = Dictionary(uniqueKeysWithValues: blocks.map { ($0.id, $0) })
        for writeback in report.writebacks {
            guard let block = byID[writeback.blockID] else { continue }
            block.reminderExternalIdentifier = writeback.externalID.isEmpty ? nil : writeback.externalID
            block.reminderLastSyncedAt = writeback.syncedAt
        }
        for blockID in report.externalCompletions {
            byID[blockID]?.complete(at: report.syncedAt)
        }
        try? context.save()
    }

    private func resolvedService() async -> (store: any RemindersStoreProtocol, service: RemindersSyncService)? {
        if let service, let store { return (store, service) }
        let newStore = EventKitRemindersStore()
        let newService = RemindersSyncService(store: newStore)
        store = newStore
        service = newService
        return (newStore, newService)
    }
}
#endif
