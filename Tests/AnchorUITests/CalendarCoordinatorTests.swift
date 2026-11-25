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

    @Test("Adding a work account keeps the personal account and selects the new primary calendar")
    func connectSecondAccount() async throws {
        let defaults = freshDefaults()
        let credentials = InMemoryCredentialStore()
        let personal = ConnectedGoogleAccount(id: "personal", email: "me@example.com", displayName: "Personal", selectedCalendarIDs: ["team"])
        try await seedAccount(personal, into: defaults, store: credentials)
        let http = StubGoogleHTTP()
        http.body = #"{"access_token":"new-session","refresh_token":"new-refresh","expires_in":3600}"#
        let coordinator = makeCoordinator(defaults: defaults, http: http, credentials: credentials)

        await coordinator.connect()

        #expect(coordinator.connectionIssue == nil)
        #expect(coordinator.accounts.first == personal)
        #expect(coordinator.accounts.map(\.id) == ["personal", "108"])
        #expect(coordinator.accounts.last?.selectedCalendarIDs == ["primary"])
        let reopened = makeCoordinator(defaults: defaults, credentials: credentials)
        #expect(reopened.accounts == coordinator.accounts)
    }

    @Test("A failed calendar list preserves selections, credentials, and the sign-in error during background sync")
    func calendarListFailurePreservesReconnect() async throws {
        let defaults = freshDefaults()
        let credentials = InMemoryCredentialStore()
        let saved = GoogleCredentials(accessToken: "saved", refreshToken: "saved-refresh", expiresAt: .distantFuture)
        let account = ConnectedGoogleAccount(id: "108", email: "me@example.com", displayName: "Me", selectedCalendarIDs: ["team"])
        try await seedAccount(account, credentials: saved, into: defaults, store: credentials)
        let source = FixtureCalendarStore()
        source.listCalendars = { _ in throw GoogleCalendarError.api(status: 403, message: "private-provider-detail") }
        let http = StubGoogleHTTP()
        http.body = #"{"access_token":"new-session","refresh_token":"new-refresh","expires_in":3600}"#
        let coordinator = makeCoordinator(defaults: defaults, http: http, store: source, credentials: credentials)

        await coordinator.connect()

        let issue = try #require(coordinator.connectionIssue)
        #expect(issue.contains("load calendars") && !issue.contains("private-provider-detail"))
        #expect(coordinator.accounts == [account])
        #expect(try await credentials.load(accountID: "108") == saved)
        let container = try AnchorStore.makeContainer(kind: .inMemory)
        await coordinator.sync(context: ModelContext(container), blocks: [])
        #expect(coordinator.connectionIssue == issue)
    }

    @Test("An old calendar list refresh cannot overwrite the newer connection or clear calendar selections")
    func staleRefreshAfterReconnect() async throws {
        let defaults = freshDefaults()
        let credentials = InMemoryCredentialStore()
        let account = ConnectedGoogleAccount(id: "108", email: "me@example.com", displayName: "Me", selectedCalendarIDs: ["team"])
        try await seedAccount(account, credentials: GoogleCredentials(accessToken: "old", refreshToken: "r", expiresAt: .distantFuture),
                              into: defaults, store: credentials)
        let gate = CalendarRequestGate()
        let source = FixtureCalendarStore()
        source.listCalendars = { token in
            if token == "old" {
                await gate.pauseFirstRequest()
                return [GoogleCalendarInfo(id: "old", title: "Outdated", isPrimary: false)]
            }
            return [GoogleCalendarInfo(id: "team", title: "Current", isPrimary: true)]
        }
        let http = StubGoogleHTTP()
        http.body = #"{"access_token":"new","refresh_token":"new-refresh","expires_in":3600}"#
        let coordinator = makeCoordinator(defaults: defaults, http: http, store: source, credentials: credentials)
        let oldRefresh = Task { await coordinator.refreshCalendars(accountID: "108") }
        await gate.waitForFirstRequest()
        await coordinator.connect()
        await gate.release()
        await oldRefresh.value

        #expect(coordinator.availableCalendars["108"]?.map(\.id) == ["team"])
        #expect(coordinator.accounts.first?.selectedCalendarIDs == ["team"])
        #expect(coordinator.connectionIssue == nil)
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
        coordinator.setCalendarSelected(accountID: "108", calendarID: "primary", selected: false)
        await coordinator.sync(context: context, blocks: blocks)
        #expect(try context.fetch(FetchDescriptor<PlanBlock>()).map(\.id) == [block.id])
        #expect(block.externalEventKey == "108\u{1F}primary\u{1F}evt-9")
        coordinator.setCalendarSelected(accountID: "108", calendarID: "primary", selected: true)
        await coordinator.sync(context: context, blocks: blocks)
        #expect(try context.fetch(FetchDescriptor<PlanBlock>()).map(\.id) == [block.id])
    }

    @Test("Removal wins over an in-flight fetch and a later import from a reopened store")
    func removeDuringImport() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("Calendar.store")
        let container = try AnchorStore.makeContainer(kind: .localOnly, url: url)
        let context = ModelContext(container)
        let start = Date(timeIntervalSince1970: 2_000_000_000)
        let period = DateInterval(start: start, duration: 7 * 86_400)
        let original = GoogleCalendarEvent(accountID: "108", calendarID: "primary", eventID: "series_20330518",
                                          title: "Planning", start: start, end: start.addingTimeInterval(3600))
        var following = original
        following.eventID = "series_20330519"
        following.start = start.addingTimeInterval(86_400)
        following.end = following.start.addingTimeInterval(3600)
        var otherCalendar = original
        otherCalendar.calendarID = "team"
        let defaults = freshDefaults()
        let credentials = InMemoryCredentialStore()
        try await seedAccount(ConnectedGoogleAccount(id: "108", email: "", displayName: "Me", selectedCalendarIDs: ["primary", "team"]),
                              credentials: GoogleCredentials(accessToken: "a", refreshToken: "r", expiresAt: .distantFuture),
                              into: defaults, store: credentials)
        let source = FixtureCalendarStore()
        source.eventsByKey["primary"] = [original, following]
        source.eventsByKey["team"] = [otherCalendar]
        let coordinator = makeCoordinator(defaults: defaults, store: source, credentials: credentials)
        #expect(await coordinator.sync(context: context, window: period) == nil)
        let blocks = try context.fetch(FetchDescriptor<PlanBlock>())
        let item = try #require(blocks.first { $0.externalEventKey == original.linkKey })
        let next = try #require(blocks.first { $0.externalEventKey == following.linkKey })
        let team = try #require(blocks.first { $0.externalEventKey == otherCalendar.linkKey })
        let duplicate = PlanBlock(title: "Earlier imported copy", plannedStart: start, plannedSeconds: 3600)
        duplicate.externalEventKey = original.linkKey
        let authored = PlanBlock(title: "Local plan", plannedStart: start, plannedSeconds: 3600)
        let session = FocusSession(goal: nil, plannedSeconds: 3600, startedAt: start)
        item.sessionID = session.id
        context.insert(duplicate)
        context.insert(authored)
        context.insert(session)
        try context.save()

        let gate = CalendarRequestGate()
        source.beforeEvents = { window in await gate.enter(window) }
        let fetching = Task { await coordinator.sync(context: context, window: period) }
        await gate.waitForFirstRequest()
        let planner = DayPlanService(context: context)
        try planner.removeImportedEvent(key: original.linkKey)
        try planner.removeImportedEvent(key: original.linkKey)
        await gate.release()
        #expect(await fetching.value == nil)

        let reopened = try AnchorStore.makeContainer(kind: .localOnly, url: url)
        let fresh = ModelContext(reopened)
        // Simulate a stale CloudKit copy arriving after the marker.
        let late = PlanBlock(title: "Late duplicate", plannedStart: start, plannedSeconds: 3600)
        late.externalEventKey = original.linkKey
        fresh.insert(late)
        try fresh.save()
        #expect(await coordinator.sync(context: fresh, window: period) == nil)
        #expect(try Set(fresh.fetch(FetchDescriptor<PlanBlock>()).map(\.id)) == [authored.id, next.id, team.id])
        #expect(try fresh.fetch(FetchDescriptor<FocusSession>()).map(\.id) == [session.id])
        #expect(try fresh.fetch(FetchDescriptor<RemovedCalendarOccurrence>()).map(\.eventKey) == [original.linkKey])
    }

    @Test("Overlapping selected periods wait, reuse existing links, and preserve other dates")
    func selectedPeriodDuringSync() async throws {
        let container = try AnchorStore.makeContainer(kind: .inMemory)
        let context = ModelContext(container)
        let defaults = freshDefaults()
        let credentials = InMemoryCredentialStore()
        try await seedAccount(
            ConnectedGoogleAccount(id: "108", email: "", displayName: "Me", selectedCalendarIDs: ["primary"]),
            credentials: GoogleCredentials(accessToken: "a", refreshToken: "r", expiresAt: .distantFuture),
            into: defaults, store: credentials
        )

        let start = Date(timeIntervalSince1970: 2_000_000_000)
        let week = DateInterval(start: start, duration: 7 * 86_400)
        let month = DateInterval(start: start, duration: 31 * 86_400)
        let gate = CalendarRequestGate()
        let source = FixtureCalendarStore()
        source.beforeEvents = { window in await gate.enter(window) }
        source.eventsByKey["primary"] = [
            GoogleCalendarEvent(accountID: "108", calendarID: "primary", eventID: "week",
                                title: "Week", start: start, end: start.addingTimeInterval(3600)),
            GoogleCalendarEvent(accountID: "108", calendarID: "primary", eventID: "month",
                                title: "Month", start: week.end, end: week.end.addingTimeInterval(3600)),
        ]
        let other = PlanBlock(title: "Another year", plannedStart: start.addingTimeInterval(-365 * 86_400),
                              plannedSeconds: 3600)
        other.externalEventKey = "108\u{1F}primary\u{1F}elsewhere"
        context.insert(other)
        try context.save()

        let coordinator = makeCoordinator(defaults: defaults, store: source, credentials: credentials)
        let first = Task { await coordinator.sync(context: context, window: week) }
        await gate.waitForFirstRequest()
        Task { await gate.release() }
        let second = await coordinator.sync(context: context, window: month)
        #expect(second == nil)
        #expect(await first.value == nil)
        #expect(await gate.windows == [week, month])
        let blocks = try context.fetch(FetchDescriptor<PlanBlock>())
        #expect(blocks.map(\.title).sorted() == ["Another year", "Month", "Week"])
    }

    @Test("Authentication failure for a selected period surfaces an issue and preserves imported entries")
    func selectedPeriodError() async throws {
        let container = try AnchorStore.makeContainer(kind: .inMemory)
        let context = ModelContext(container)
        let defaults = freshDefaults()
        let credentials = InMemoryCredentialStore()
        try await seedAccount(ConnectedGoogleAccount(id: "108", email: "", displayName: "Me", selectedCalendarIDs: ["primary"]),
                              into: defaults, store: credentials)
        let period = DateInterval(start: Date(timeIntervalSince1970: 2_000_000_000), duration: 7 * 86_400)
        let imported = PlanBlock(title: "Saved", plannedStart: period.start, plannedSeconds: 1800)
        imported.externalEventKey = "108\u{1F}primary\u{1F}old"
        context.insert(imported)
        try context.save()
        let coordinator = makeCoordinator(defaults: defaults, credentials: credentials)
        let issue = await coordinator.sync(context: context, window: period)
        #expect(issue != nil && issue == coordinator.status)
        #expect(coordinator.lastSyncedAt == nil)
        #expect(try context.fetch(FetchDescriptor<PlanBlock>()).map(\.id) == [imported.id])
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
    var beforeEvents: (@Sendable (DateInterval) async -> Void)?
    var listCalendars: (@Sendable (String) async throws -> [GoogleCalendarInfo])?

    func accountIdentity(accessToken _: String) async throws -> GoogleAccountIdentity {
        GoogleAccountIdentity(id: "108", email: "me@example.com", displayName: "Me")
    }

    func calendars(accessToken: String) async throws -> [GoogleCalendarInfo] {
        if let listCalendars { return try await listCalendars(accessToken) }
        return [
            GoogleCalendarInfo(id: "primary", title: "Personal", isPrimary: true),
            GoogleCalendarInfo(id: "team", title: "Team", isPrimary: false),
        ]
    }

    func events(
        accessToken _: String,
        accountID _: String,
        calendarID: String,
        window: DateInterval
    ) async throws -> [GoogleCalendarEvent] {
        await beforeEvents?(window)
        return (eventsByKey[calendarID] ?? []).filter { $0.start < window.end && $0.end > window.start }
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


private actor CalendarRequestGate {
    private(set) var windows: [DateInterval] = []
    private var didStart = false
    private var firstRequest: CheckedContinuation<Void, Never>?
    private var paused: CheckedContinuation<Void, Never>?

    func enter(_ window: DateInterval) async {
        windows.append(window)
        guard windows.count == 1 else { return }
        await pauseFirstRequest()
    }

    func pauseFirstRequest() async {
        didStart = true
        firstRequest?.resume()
        await withCheckedContinuation { paused = $0 }
    }

    func waitForFirstRequest() async {
        if !didStart { await withCheckedContinuation { firstRequest = $0 } }
    }

    func release() { paused?.resume() }
}
