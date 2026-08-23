#if !os(watchOS)
import AnchorCore
import Foundation
import PersonalSyncKit
import Testing

@Suite("Significant Hobbies Hub status")
struct HubSyncStatusTests {
    @Test
    func classifiesExpiredOfflineAndServiceFailures() {
        #expect(
            HubSyncFailure.classify(PersonalSyncError.server(status: 401, message: "expired"))
                == .signInExpired
        )
        #expect(
            HubSyncFailure.classify(URLError(.notConnectedToInternet)) == .offline
        )
        #expect(
            HubSyncFailure.classify(PersonalSyncError.server(status: 503, message: "down"))
                == .service
        )
        #expect(HubSyncFailure.classify(PersonalSyncError.invalidResponse) == .service)
        #expect(
            HubSyncFailure.classify(accountMessage: "The Internet connection appears to be offline.")
                == .offline
        )
        #expect(
            HubSyncFailure.classify(accountMessage: "The personal account service is unavailable.")
                == .service
        )
    }

    @Test
    func failureCopyReportsSafePendingSummaries() {
        #expect(
            HubSyncFailure.offline.explanation(pendingCount: 2)
                == "You're offline. 2 finished session summaries are safe and waiting locally. Anchor will retry the next time it can reach the Hub."
        )
        #expect(
            HubSyncFailure.signInExpired.explanation(pendingCount: 1)
                .contains("Sign out, then reconnect")
        )
    }

    @Test @MainActor
    func receiptSurvivesRelaunchAndSuccessClearsFailure() throws {
        let suite = "anchor-hub-sync-tests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = HubSyncReceiptStore(defaults: defaults, key: "receipt")
        let failureDate = Date(timeIntervalSince1970: 100)
        let successDate = Date(timeIntervalSince1970: 200)

        var receipt = HubSyncReceipt()
        receipt.recordFailure(.offline, at: failureDate)
        store.save(receipt)

        #expect(store.load() == receipt)

        receipt.recordSuccess(at: successDate)
        store.save(receipt)
        let restored = store.load()
        #expect(restored.lastSuccessfulAt == successDate)
        #expect(restored.failure == nil)
        #expect(restored.failedAt == nil)
    }
}
#endif
