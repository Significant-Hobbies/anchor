import Foundation
import SwiftData
import Testing

@testable import AnchorCore
@testable import AnchorUI

@MainActor
@Suite("Calendar sync coordinator")
struct CalendarCoordinatorTests {
    private let clientID = "test.apps.googleusercontent.com"

    private func makeCoordinator(
        defaults: UserDefaults,
        http: StubGoogleHTTP = StubGoogleHTTP(),
        store: FixtureCalendarStore = FixtureCalendarStore(),
        credentials: InMemoryCredentialStore = InMemoryCredentialStore(),
        runner: FakeAuthRunner = FakeAuthRunner()
    ) -> CalendarSyncCoordinator {
        CalendarSyncCoordinator(
            authRunner: runner,
            tokenClient: GoogleTokenClient(http: http),
            calendarStore: store,
            credentialStore: credentials,
            defaults: defaults,
            clientID: clientID
        )
    }

    private func freshDefaults() -> UserDefaults {
        UserDefaults(suiteName: "calendar-tests-\(UUID().uuidString)")!
    }

    private func seedAccount(
        _ account: ConnectedGoogleAccount,
        credentials: GoogleCredentials? = nil,
        into defaults: UserDefaults,
        store: InMemoryCredentialStore
    ) async throws {
        defaults.set(try JSONEncoder().encode([account]), forKey: CalendarSyncCoordinator.accountsKey)
        if let credentials {
            try await store.save(credentials, accountID: account.id)
        }
    }

    @Test("Connect stores the account, its credentials, and defaults to the primary calendar")
    func connectPersistsAccount() async throws {
        let defaults = freshDefaults()
        let http = StubGoogleHTTP()
        let payload = "eyJzdWIiOiIxMDgiLCJlbWFpbCI6Im1lQGV4YW1wbGUuY29tIiwibmFtZSI6Ik1lIn0"
        http.body = """
        {"access_token":"ya29.a","refresh_token":"1//r","expires_in":3600,"id_token":"h.\(payload).s"}
        """
        let credentials = InMemoryCredentialStore()
        let coordinator = makeCoordinator(defaults: defaults, http: http, credentials: credentials)

        await coordinator.connect()

        let account = try #require(coordinator.accounts.first)
        #expect(account.id == "108")
        #expect(account.email == "me@example.com")
        #expect(account.selectedCalendarIDs == ["primary"])
        #expect(coordinator.availableCalendars["108"]?.count == 2)
        let saved = try await credentials.load(accountID: "108")
        #expect(saved?.refreshToken == "1//r")
    }

    @Test("Sync imports events as fixed commitment blocks linked to the event")
    func syncCreatesBlocks() async throws {
        let container = try AnchorStore.makeContainer(kind: .inMemory)
        let context = ModelContext(container)
        let defaults = freshDefaults()
        let credentials = InMemoryCredentialStore()
        let store = FixtureCalendarStore()
        store.eventsByKey["primary"] = [
            GoogleCalendarEvent(
                accountID: "108", calendarID: "primary", eventID: "evt-9",
                title: "Design review",
                start: Date().addingTimeInterval(3_600),
                end: Date().addingTimeInterval(5_400)
            )
        ]
        try await seedAccount(
            ConnectedGoogleAccount(id: "108", email: "me@example.com", displayName: "Me", selectedCalendarIDs: ["primary"]),
            credentials: GoogleCredentials(
                accessToken: "ya29.a",
                refreshToken: "1//r",
                expiresAt: Date().addingTimeInterval(3_600)
            ),
            into: defaults,
            store: credentials
        )
        let coordinator = makeCoordinator(defaults: defaults, store: store, credentials: credentials)

        await coordinator.sync(context: context, blocks: [])

        let blocks = try context.fetch(FetchDescriptor<PlanBlock>())
        let block = try #require(blocks.first)
        #expect(blocks.count == 1)
        #expect(block.title == "Design review")
        #expect(block.kind == .commitment)
        #expect(block.flexibility == .fixed)
        #expect(block.externalEventKey == "108\u{1F}primary\u{1F}evt-9")
    }

    @Test("Disconnect unlinks imported blocks, drops credentials, and forgets the account")
    func disconnectCleansUp() async throws {
        let container = try AnchorStore.makeContainer(kind: .inMemory)
        let context = ModelContext(container)
        let defaults = freshDefaults()
        let credentials = InMemoryCredentialStore()
        let http = StubGoogleHTTP()
        let block = PlanBlock(
            title: "Imported meeting",
            plannedStart: Date().addingTimeInterval(3_600),
            plannedSeconds: 1_800,
            kind: .commitment,
            flexibility: .fixed
        )
        block.externalEventKey = "108\u{1F}primary\u{1F}evt-1"
        context.insert(block)
        try context.save()
        try await seedAccount(
            ConnectedGoogleAccount(id: "108", email: "me@example.com", displayName: "Me", selectedCalendarIDs: ["primary"]),
            credentials: GoogleCredentials(
                accessToken: "ya29.a",
                refreshToken: "1//r",
                expiresAt: Date().addingTimeInterval(3_600)
            ),
            into: defaults,
            store: credentials
        )
        let coordinator = makeCoordinator(defaults: defaults, http: http, credentials: credentials)
        let blocks = try context.fetch(FetchDescriptor<PlanBlock>())

        await coordinator.disconnect(accountID: "108", context: context, blocks: blocks)

        #expect(coordinator.accounts.isEmpty)
        #expect(block.externalEventKey == nil)
        #expect(block.title == "Imported meeting")
        #expect(try await credentials.load(accountID: "108") == nil)
        #expect(http.lastRequest?.url?.absoluteString.contains("revoke") == true)
    }
}

private final class InMemoryCredentialStore: GoogleCredentialStore, @unchecked Sendable {
    var storage: [String: GoogleCredentials] = [:]

    func load(accountID: String) async throws -> GoogleCredentials? { storage[accountID] }
    func save(_ credentials: GoogleCredentials, accountID: String) async throws {
        storage[accountID] = credentials
    }
    func delete(accountID: String) async throws { storage.removeValue(forKey: accountID) }
}

private final class FixtureCalendarStore: GoogleCalendarStoreProtocol, @unchecked Sendable {
    var eventsByKey: [String: [GoogleCalendarEvent]] = [:]

    func accountIdentity(accessToken _: String) async throws -> GoogleAccountIdentity {
        GoogleAccountIdentity(id: "108", email: "me@example.com", displayName: "Me")
    }

    func calendars(accessToken _: String) async throws -> [GoogleCalendarInfo] {
        [
            GoogleCalendarInfo(id: "primary", title: "Personal", isPrimary: true),
            GoogleCalendarInfo(id: "team", title: "Team", isPrimary: false),
        ]
    }

    func events(
        accessToken _: String,
        accountID _: String,
        calendarID: String,
        window _: DateInterval
    ) async throws -> [GoogleCalendarEvent] {
        eventsByKey[calendarID] ?? []
    }
}

/// Answers the auth request with a well-formed callback for the same state —
/// the equivalent of the user completing sign-in.
private final class FakeAuthRunner: GoogleAuthSessionRunner, @unchecked Sendable {
    func authenticate(url: URL, callbackScheme: String) async throws -> URL {
        let state = URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?.first { $0.name == "state" }?.value ?? ""
        return URL(string: "\(callbackScheme):/oauth2callback?code=fake-code&state=\(state)")!
    }
}

private final class StubGoogleHTTP: GoogleHTTPClient, @unchecked Sendable {
    var statusCode = 200
    var body = "{}"
    var lastRequest: URLRequest?

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        lastRequest = request
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: statusCode,
            httpVersion: nil,
            headerFields: nil
        )!
        return (Data(body.utf8), response)
    }
}
