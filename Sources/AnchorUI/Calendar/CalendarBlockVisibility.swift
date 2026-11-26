#if !os(watchOS)
import AnchorCore
import SwiftData
import SwiftUI

/// Calendar selection is local to this device. Copies imported on a different
/// device stay visible unless the owner explicitly hides their source here.
@MainActor
struct CalendarBlockVisibility: DynamicProperty {
    @AppStorage(CalendarSyncCoordinator.accountsKey) private var accountsData = Data()
    @AppStorage(CalendarSyncCoordinator.disconnectedAccountsKey) private var disconnectedData = Data()
    @Query private var removals: [RemovedCalendarOccurrence]

    var removedBlockIDs: Set<String> { Set(removals.flatMap(\.removedBlockIDs)) }

    func filter(_ blocks: [PlanBlock]) -> [PlanBlock] {
        Self.filter(blocks, accountsData: accountsData, disconnectedData: disconnectedData, removed: Set(removals.map(\.eventKey)))
    }

    static func filter(_ blocks: [PlanBlock], accountsData: Data, disconnectedData: Data,
                       removed: Set<String>) -> [PlanBlock] {
        let accounts = (try? JSONDecoder().decode([ConnectedGoogleAccount].self, from: accountsData)) ?? []
        let disconnected = (try? JSONDecoder().decode(Set<String>.self, from: disconnectedData)) ?? []
        return Self.filter(blocks, accounts: accounts, disconnected: disconnected, removed: removed)
    }

    static func filter(_ blocks: [PlanBlock], accounts: [ConnectedGoogleAccount],
                       disconnected: Set<String>, removed: Set<String>) -> [PlanBlock] {
        let selections = Dictionary(accounts.map { ($0.id, Set($0.selectedCalendarIDs)) },
                                    uniquingKeysWith: { first, _ in first })
        return blocks.filter { block in
            guard let key = block.externalEventKey else { return true }
            if removed.contains(key) { return false }
            guard let source = GoogleCalendarEvent.linkedCalendar(key),
                  CalendarSyncPolicy.isUntouched(block.snapshot()) else { return true }
            if let selected = selections[source.accountID] { return selected.contains(source.calendarID) }
            return !disconnected.contains(source.accountID)
        }
    }
}
#endif
