import Foundation
import Testing

@testable import AnchorCore

@Suite("Google Calendar sync")
struct CalendarSyncTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private var window: DateInterval {
        CalendarSyncPolicy.syncWindow(now: Date(timeIntervalSince1970: 1_704_067_200), calendar: calendar)
    }

    private func event(
        _ title: String,
        account: String = "acct-1",
        calendar: String = "primary",
        id: String = "evt-1",
        start: Date = Date(timeIntervalSince1970: 1_704_110_400),
        seconds: TimeInterval = 3_600,
        allDay: Bool = false,
        cancelled: Bool = false
    ) -> GoogleCalendarEvent {
        GoogleCalendarEvent(
            accountID: account,
            calendarID: calendar,
            eventID: id,
            title: title,
            start: start,
            end: start.addingTimeInterval(seconds),
            isAllDay: allDay,
            isCancelled: cancelled
        )
    }

    private func block(
        for event: GoogleCalendarEvent,
        state: PlanBlockState = .planned,
        sessionID: UUID? = nil,
        edited: Bool = false
    ) -> PlanBlockRecord {
        PlanBlockRecord(
            id: UUID(),
            isTemplateOverride: edited,
            sessionID: sessionID,
            title: event.title,
            plannedStart: event.start,
            plannedSeconds: Int(event.end.timeIntervalSince(event.start)),
            state: state,
            kind: .commitment,
            externalEventKey: event.linkKey
        )
    }

    // MARK: - Policy

    @Test("A new timed event becomes a commitment creation")
    func createsForNewEvents() {
        let e = event("Standup")
        let plan = CalendarSyncPolicy.plan(
            events: [e], blocks: [], window: window, managedAccountIDs: ["acct-1"]
        )
        #expect(plan.creations == [e])
        #expect(plan.updates.isEmpty && plan.deletions.isEmpty && plan.detachments.isEmpty)
    }

    @Test("An untouched linked block tracks event changes")
    func updatesUntouchedBlock() {
        let e = event("Moved meeting", seconds: 1_800)
        let stale = block(for: event("Old title"))
        let plan = CalendarSyncPolicy.plan(
            events: [e], blocks: [stale], window: window, managedAccountIDs: ["acct-1"]
        )
        #expect(plan.updates == [CalendarBlockUpdate(blockID: stale.id, event: e)])
        #expect(plan.creations.isEmpty && plan.deletions.isEmpty && plan.detachments.isEmpty)
    }

    @Test("Cancelled events delete untouched blocks and detach touched ones")
    func cancellationHandling() {
        let cancelled = event("Gone", cancelled: true)
        let fresh = block(for: event("Gone"))
        let started = block(for: event("Gone"), state: .completed)
        let plan = CalendarSyncPolicy.plan(
            events: [cancelled], blocks: [fresh, started], window: window,
            managedAccountIDs: ["acct-1"]
        )
        #expect(plan.deletions == [fresh.id])
        #expect(plan.detachments == [started.id])
        #expect(plan.creations.isEmpty && plan.updates.isEmpty)
    }

    @Test("Vanished events delete untouched blocks and detach touched ones")
    func vanishedHandling() {
        let e = event("Meeting")
        let fresh = block(for: e)
        let edited = block(for: e, edited: true)
        let plan = CalendarSyncPolicy.plan(
            events: [], blocks: [fresh, edited], window: window, managedAccountIDs: ["acct-1"]
        )
        #expect(plan.deletions == [fresh.id])
        #expect(plan.detachments == [edited.id])
    }

    @Test("A changed event detaches a touched block instead of overwriting")
    func touchedBlockDetachesOnChange() {
        let e = event("Renamed")
        let touched = block(for: event("Original"), edited: true)
        let plan = CalendarSyncPolicy.plan(
            events: [e], blocks: [touched], window: window, managedAccountIDs: ["acct-1"]
        )
        #expect(plan.detachments == [touched.id])
        #expect(plan.updates.isEmpty && plan.deletions.isEmpty)
    }

    @Test("All-day events are not imported")
    func skipsAllDay() {
        let plan = CalendarSyncPolicy.plan(
            events: [event("Offsite", allDay: true)], blocks: [], window: window,
            managedAccountIDs: ["acct-1"]
        )
        #expect(plan.creations.isEmpty)
    }

    @Test("Blocks for unmanaged accounts are never touched")
    func ignoresUnmanagedAccounts() {
        let foreign = block(for: event("Other", account: "acct-2"))
        let plan = CalendarSyncPolicy.plan(
            events: [], blocks: [foreign], window: window, managedAccountIDs: ["acct-1"]
        )
        #expect(plan.deletions.isEmpty && plan.detachments.isEmpty)
    }

    @Test("Blocks outside the window are ignored")
    func ignoresOutOfWindowBlocks() {
        let distant = Date(timeIntervalSince1970: 1_800_000_000)
        let e = event("Far future", start: distant)
        let b = block(for: e)
        let plan = CalendarSyncPolicy.plan(
            events: [], blocks: [b], window: window, managedAccountIDs: ["acct-1"]
        )
        #expect(plan.deletions.isEmpty && plan.detachments.isEmpty)
    }

    @Test("Duplicate links keep one block and clean up the rest")
    func duplicateCleanup() {
        let e = event("Meeting")
        let plan = CalendarSyncPolicy.plan(
            events: [e],
            blocks: [block(for: e), block(for: e)],
            window: window,
            managedAccountIDs: ["acct-1"]
        )
        #expect(plan.deletions.count == 1)
        #expect(plan.creations.isEmpty)
    }

    // MARK: - Service

    @Test("A failed account leaves its blocks completely alone")
    func failedAccountIsIsolated() async {
        let store = FixtureCalendarStore()
        store.eventsByAccount["acct-1"] = [event("Standup")]
        store.failAccounts.insert("acct-2")
        let foreign = block(for: event("Meeting", account: "acct-2"))
        let service = CalendarSyncService(store: store, calendar: calendar)

        let report = await service.sync(
            accounts: [
                CalendarSyncAccount(id: "acct-1", accessToken: "a", selectedCalendarIDs: ["primary"]),
                CalendarSyncAccount(id: "acct-2", accessToken: "b", selectedCalendarIDs: ["primary"]),
            ],
            blocks: [foreign],
            now: Date(timeIntervalSince1970: 1_704_067_200)
        )
        #expect(report.failedAccounts == ["acct-2"])
        #expect(report.creations.count == 1)
        #expect(report.deletions.isEmpty && report.detachments.isEmpty)
    }

    @Test("Events from every selected calendar merge into one pass")
    func mergesCalendars() async {
        let store = FixtureCalendarStore()
        store.eventsByKey["primary"] = [event("A", calendar: "primary", id: "1")]
        store.eventsByKey["team"] = [event("B", calendar: "team", id: "2")]
        let service = CalendarSyncService(store: store, calendar: calendar)
        let report = await service.sync(
            accounts: [CalendarSyncAccount(
                id: "acct-1", accessToken: "a", selectedCalendarIDs: ["primary", "team"]
            )],
            blocks: [],
            now: Date(timeIntervalSince1970: 1_704_067_200)
        )
        #expect(report.creations.count == 2)
    }

    // MARK: - OAuth pieces

    @Test("Authorization request carries PKCE, offline access, and the reversed scheme")
    func authorizationRequestShape() throws {
        let clientID = "abc123.apps.googleusercontent.com"
        let request = try GoogleCalendarConfig.makeAuthorizationRequest(
            clientID: clientID,
            state: "state-1",
            pkce: GooglePKCE()
        )
        let items = URLComponents(url: request.url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        let value = { (name: String) in items.first { $0.name == name }?.value }
        #expect(value("client_id") == clientID)
        #expect(value("redirect_uri") == "com.googleusercontent.apps.abc123:/oauth2callback")
        #expect(value("response_type") == "code")
        #expect(value("access_type") == "offline")
        #expect(value("state") == "state-1")
        #expect(value("code_challenge_method") == "S256")
        #expect(value("code_challenge") != nil)
        #expect(value("scope")?.contains("calendar.readonly") == true)
        #expect(GoogleCalendarConfig.callbackScheme(clientID: clientID) == "com.googleusercontent.apps.abc123")
    }

    @Test("Callback parsing enforces state and surfaces errors")
    func callbackParsing() throws {
        let good = URL(string: "com.googleusercontent.apps.abc:/oauth2callback?code=code-1&state=s1")!
        #expect(try GoogleCalendarConfig.authorizationCode(fromCallback: good, expectedState: "s1") == "code-1")
        #expect(throws: GoogleCalendarError.invalidResponse) {
            try GoogleCalendarConfig.authorizationCode(fromCallback: good, expectedState: "other")
        }
        let denied = URL(string: "com.googleusercontent.apps.abc:/oauth2callback?error=access_denied&state=s1")!
        #expect(throws: GoogleCalendarError.authorizationRejected) {
            try GoogleCalendarConfig.authorizationCode(fromCallback: denied, expectedState: "s1")
        }
    }

    @Test("Token exchange posts form fields and decodes the response")
    func tokenExchange() async throws {
        let http = StubGoogleHTTP()
        http.body = """
        {"access_token":"ya29.token","refresh_token":"1//refresh","expires_in":3600,"id_token":"header.eyJzdWIiOiIxMjMifQ.sig"}
        """
        let client = GoogleTokenClient(http: http)
        let now = Date(timeIntervalSince1970: 1_704_067_200)
        let tokens = try await client.exchange(
            code: "code-1",
            verifier: "verifier",
            redirectURI: "com.googleusercontent.apps.abc:/oauth2callback",
            clientID: "abc.apps.googleusercontent.com",
            now: now
        )
        #expect(tokens.accessToken == "ya29.token")
        #expect(tokens.refreshToken == "1//refresh")
        #expect(tokens.expiresAt == now.addingTimeInterval(3_600))
        let form = String(data: http.lastRequest?.httpBody ?? Data(), encoding: .utf8) ?? ""
        #expect(form.contains("grant_type=authorization_code"))
        #expect(form.contains("code=code-1"))
        #expect(form.contains("code_verifier=verifier"))
    }

    @Test("Refresh failures surface the API error")
    func tokenRefreshFailure() async {
        let http = StubGoogleHTTP()
        http.statusCode = 400
        http.body = #"{"error":"invalid_grant","error_description":"Token has been revoked."}"#
        let client = GoogleTokenClient(http: http)
        await #expect(throws: GoogleCalendarError.api(status: 400, message: "Token has been revoked.")) {
            try await client.refresh("1//stale", clientID: "abc")
        }
    }

    @Test("Calendar list pagination keeps calendars from later pages")
    func calendarListPagination() async throws {
        let http = StubGoogleHTTP()
        http.responsesByPageToken[""] = #"{"items":[{"id":"primary","summary":"Personal","primary":true}],"nextPageToken":"calendar-page-2"}"#
        http.responsesByPageToken["calendar-page-2"] = #"{"items":[{"id":"team","summary":"Team","primary":false}]}"#

        let store = URLSessionGoogleCalendarStore(
            http: http,
            apiBaseURL: URL(string: "https://calendar.test/calendar/v3")!,
            userInfoURL: URL(string: "https://calendar.test/userinfo")!
        )
        let calendars = try await store.calendars(accessToken: "token")

        #expect(calendars.map(\.id) == ["primary", "team"])
        #expect(http.requests.count == 2)
        #expect(http.pageToken(for: http.requests[1]) == "calendar-page-2")
    }

    @Test("Event pagination keeps timed events from later pages")
    func eventPagination() async throws {
        let http = StubGoogleHTTP()
        http.responsesByPageToken[""] = #"{"items":[{"id":"event-1","status":"confirmed","summary":"First","start":{"dateTime":"2026-01-01T10:00:00Z"},"end":{"dateTime":"2026-01-01T11:00:00Z"}}],"nextPageToken":"event-page-2"}"#
        http.responsesByPageToken["event-page-2"] = #"{"items":[{"id":"event-2","status":"confirmed","summary":"Second","start":{"dateTime":"2026-01-02T10:00:00Z"},"end":{"dateTime":"2026-01-02T11:00:00Z"}}]}"#

        let store = URLSessionGoogleCalendarStore(
            http: http,
            apiBaseURL: URL(string: "https://calendar.test/calendar/v3")!,
            userInfoURL: URL(string: "https://calendar.test/userinfo")!
        )
        let events = try await store.events(
            accessToken: "token",
            accountID: "account",
            calendarID: "primary",
            window: DateInterval(
                start: Date(timeIntervalSince1970: 1_767_225_600),
                duration: 86_400 * 3
            )
        )

        #expect(events.map(\.eventID) == ["event-1", "event-2"])
        #expect(http.requests.count == 2)
        #expect(http.pageToken(for: http.requests[1]) == "event-page-2")
    }

    @Test("ID token identity decodes sub, email, and name")
    func idTokenIdentity() {
        // {"sub":"108","email":"me@example.com","name":"Me"} base64url
        let payload = "eyJzdWIiOiIxMDgiLCJlbWFpbCI6Im1lQGV4YW1wbGUuY29tIiwibmFtZSI6Ik1lIn0"
        let token = "header.\(payload).signature"
        let identity = GoogleIDToken.identity(from: token)
        #expect(identity == GoogleAccountIdentity(id: "108", email: "me@example.com", displayName: "Me"))
        #expect(GoogleIDToken.identity(from: "not-a-jwt") == nil)
    }

    @Test("Credentials count a safety margin before expiry")
    func credentialExpiry() {
        let now = Date()
        let fresh = GoogleCredentials(accessToken: "a", refreshToken: "r", expiresAt: now.addingTimeInterval(300))
        let stale = GoogleCredentials(accessToken: "a", refreshToken: "r", expiresAt: now.addingTimeInterval(30))
        #expect(!fresh.isExpired(at: now))
        #expect(stale.isExpired(at: now))
    }
}

private final class FixtureCalendarStore: GoogleCalendarStoreProtocol, @unchecked Sendable {
    var eventsByAccount: [String: [GoogleCalendarEvent]] = [:]
    var eventsByKey: [String: [GoogleCalendarEvent]] = [:]
    var failAccounts: Set<String> = []

    func accountIdentity(accessToken _: String) async throws -> GoogleAccountIdentity {
        GoogleAccountIdentity(id: "sub", email: "a@b.c", displayName: "A")
    }

    func calendars(accessToken _: String) async throws -> [GoogleCalendarInfo] {
        [GoogleCalendarInfo(id: "primary", title: "Primary", isPrimary: true)]
    }

    func events(
        accessToken _: String,
        accountID: String,
        calendarID: String,
        window _: DateInterval
    ) async throws -> [GoogleCalendarEvent] {
        if failAccounts.contains(accountID) {
            throw GoogleCalendarError.api(status: 401, message: "unauthorized")
        }
        return eventsByAccount[accountID] ?? eventsByKey[calendarID] ?? []
    }
}

private final class StubGoogleHTTP: GoogleHTTPClient, @unchecked Sendable {
    var statusCode = 200
    var body = "{}"
    var lastRequest: URLRequest?
    var requests: [URLRequest] = []
    var responsesByPageToken: [String: String] = [:]

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        lastRequest = request
        requests.append(request)
        let pageToken = pageToken(for: request) ?? ""
        let responseBody = responsesByPageToken[pageToken] ?? body
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: statusCode,
            httpVersion: nil,
            headerFields: nil
        )!
        return (Data(responseBody.utf8), response)
    }

    func pageToken(for request: URLRequest) -> String? {
        URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?
            .queryItems?
            .first { $0.name == "pageToken" }?
            .value
    }
}
