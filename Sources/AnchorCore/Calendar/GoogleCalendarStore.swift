import Foundation

/// A calendar exposed by one connected Google account.
public struct GoogleCalendarInfo: Sendable, Equatable, Identifiable {
    public var id: String
    public var title: String
    public var isPrimary: Bool

    public init(id: String, title: String, isPrimary: Bool) {
        self.id = id
        self.title = title
        self.isPrimary = isPrimary
    }
}

/// A value-type mirror of a Google Calendar event. The sync core reconciles
/// `PlanBlockRecord` snapshots against these — the API shape never reaches the
/// plan logic.
public struct GoogleCalendarEvent: Sendable, Equatable, Identifiable {
    public var accountID: String
    public var calendarID: String
    public var eventID: String
    public var title: String
    public var start: Date
    public var end: Date
    public var isAllDay: Bool
    public var isCancelled: Bool

    public init(
        accountID: String,
        calendarID: String,
        eventID: String,
        title: String,
        start: Date,
        end: Date,
        isAllDay: Bool = false,
        isCancelled: Bool = false
    ) {
        self.accountID = accountID
        self.calendarID = calendarID
        self.eventID = eventID
        self.title = title
        self.start = start
        self.end = end
        self.isAllDay = isAllDay
        self.isCancelled = isCancelled
    }

    /// The durable join between an event and its imported block. Events are
    /// fetched with `singleEvents=true`, so recurring instances carry distinct
    /// IDs and therefore distinct keys.
    public var linkKey: String { "\(accountID)\u{1F}\(calendarID)\u{1F}\(eventID)" }

    public var id: String { linkKey }

    /// The account portion of the key, used to scope or strip an account's
    /// links without touching anyone else's.
    public static func linkPrefix(accountID: String) -> String { "\(accountID)\u{1F}" }
}

/// Everything sync needs from the Google Calendar API, injectable so tests
/// supply a deterministic store.
public protocol GoogleCalendarStoreProtocol: Sendable {
    /// Display identity for a freshly connected account.
    func accountIdentity(accessToken: String) async throws -> GoogleAccountIdentity
    func calendars(accessToken: String) async throws -> [GoogleCalendarInfo]
    /// Timed and cancelled events in the window for one calendar.
    func events(
        accessToken: String,
        accountID: String,
        calendarID: String,
        window: DateInterval
    ) async throws -> [GoogleCalendarEvent]
}

/// URLSession-backed Calendar API client. Requests are read-only by
/// construction — the OAuth scope is `calendar.readonly`.
public struct URLSessionGoogleCalendarStore: GoogleCalendarStoreProtocol {
    public var http: any GoogleHTTPClient
    public var apiBaseURL: URL
    public var userInfoURL: URL

    public init(
        http: any GoogleHTTPClient = URLSession.shared,
        apiBaseURL: URL = GoogleCalendarConfig.apiBaseURL,
        userInfoURL: URL = GoogleCalendarConfig.userInfoURL
    ) {
        self.http = http
        self.apiBaseURL = apiBaseURL
        self.userInfoURL = userInfoURL
    }

    public func accountIdentity(accessToken: String) async throws -> GoogleAccountIdentity {
        let (data, _) = try await get(userInfoURL, accessToken: accessToken)
        let body = try JSONDecoder().decode(UserInfoBody.self, from: data)
        return GoogleAccountIdentity(
            id: body.sub,
            email: body.email ?? "",
            displayName: body.name ?? body.email ?? "Google account"
        )
    }

    public func calendars(accessToken: String) async throws -> [GoogleCalendarInfo] {
        let baseURL = apiBaseURL.appending(path: "users/me/calendarList")
        var pageToken: String?
        var calendars: [GoogleCalendarInfo] = []

        repeat {
            let url = try Self.url(baseURL, queryItems: [], pageToken: pageToken)
            let (data, _) = try await get(url, accessToken: accessToken)
            let list = try JSONDecoder().decode(CalendarListBody.self, from: data)
            calendars += list.items.map {
                GoogleCalendarInfo(
                    id: $0.id,
                    title: $0.summaryOverride ?? $0.summary,
                    isPrimary: $0.primary ?? false
                )
            }
            pageToken = list.nextPageToken
        } while pageToken != nil

        return calendars
    }

    private static func url(
        _ baseURL: URL,
        queryItems: [URLQueryItem],
        pageToken: String?
    ) throws -> URL {
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            throw GoogleCalendarError.invalidResponse
        }
        components.queryItems = queryItems
        if let pageToken {
            components.queryItems?.append(URLQueryItem(name: "pageToken", value: pageToken))
        }
        guard let url = components.url else { throw GoogleCalendarError.invalidResponse }
        return url
    }

    public func events(
        accessToken: String,
        accountID: String,
        calendarID: String,
        window: DateInterval
    ) async throws -> [GoogleCalendarEvent] {
        let baseURL = apiBaseURL
            .appending(path: "calendars")
            .appending(path: calendarID)
            .appending(path: "events")
        let formatter = ISO8601DateFormatter()
        let queryItems = [
            URLQueryItem(name: "timeMin", value: formatter.string(from: window.start)),
            URLQueryItem(name: "timeMax", value: formatter.string(from: window.end)),
            URLQueryItem(name: "singleEvents", value: "true"),
            URLQueryItem(name: "orderBy", value: "startTime"),
            // Cancelled events must be visible so their imported blocks can
            // be removed rather than silently going stale.
            URLQueryItem(name: "showDeleted", value: "true"),
            URLQueryItem(name: "maxResults", value: "250"),
        ]
        var pageToken: String?
        var events: [GoogleCalendarEvent] = []

        repeat {
            let url = try Self.url(baseURL, queryItems: queryItems, pageToken: pageToken)
            let (data, _) = try await get(url, accessToken: accessToken)
            let list = try JSONDecoder().decode(EventListBody.self, from: data)
            events += list.items.compactMap { item in
                let cancelled = item.status == "cancelled"
                let timed = Self.parseInterval(item)
                if !cancelled && timed == nil { return nil }
                return GoogleCalendarEvent(
                    accountID: accountID,
                    calendarID: calendarID,
                    eventID: item.id,
                    title: item.summary ?? "",
                    start: timed?.start ?? window.start,
                    end: timed?.end ?? window.start,
                    isAllDay: timed == nil,
                    isCancelled: cancelled
                )
            }
            pageToken = list.nextPageToken
        } while pageToken != nil

        return events
    }

    /// Returns the event's real interval for timed events, `nil` for all-day
    /// ones (which v1 does not import). Cancelled entries often keep their
    /// original times but are allowed through either way.
    private static func parseInterval(_ item: EventItem) -> (start: Date, end: Date)? {
        guard let startRaw = item.start?.dateTime, let endRaw = item.end?.dateTime,
              let start = Self.parseDateTime(startRaw), let end = Self.parseDateTime(endRaw)
        else { return nil }
        return (start, end)
    }

    private static func parseDateTime(_ raw: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: raw) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: raw)
    }

    private func get(_ url: URL, accessToken: String) async throws -> (Data, HTTPURLResponse) {
        var request = URLRequest(url: url)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await http.send(request)
        guard (200..<300).contains(response.statusCode) else {
            throw GoogleCalendarError.api(
                status: response.statusCode,
                message: String(data: data, encoding: .utf8)?.prefix(160).description
                    ?? "request failed"
            )
        }
        return (data, response)
    }

    private struct UserInfoBody: Decodable {
        let sub: String
        let email: String?
        let name: String?
    }

    private struct CalendarListBody: Decodable {
        struct Entry: Decodable {
            let id: String
            let summary: String
            let summaryOverride: String?
            let primary: Bool?
        }
        let items: [Entry]
        let nextPageToken: String?
    }

    private struct EventListBody: Decodable {
        let items: [EventItem]
        let nextPageToken: String?
    }

    struct EventItem: Decodable {
        struct Point: Decodable {
            let dateTime: String?
        }
        let id: String
        let status: String?
        let summary: String?
        let start: Point?
        let end: Point?
    }
}
