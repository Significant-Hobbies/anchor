#if os(macOS) || os(iOS)
import AnchorCore
import AuthenticationServices
import Foundation
import SwiftData
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

/// Drives the browser half of the OAuth flow. Injectable so tests (and
/// previews) can complete the flow without opening Safari.
public protocol GoogleAuthSessionRunner: Sendable {
    func authenticate(url: URL, callbackScheme: String) async throws -> URL
}

/// A connected Google account: stable identity plus the owner's calendar
/// selection. Persisted as JSON in UserDefaults — device-local like the
/// Reminders settings, never in the CloudKit schema.
public struct ConnectedGoogleAccount: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var email: String
    public var displayName: String
    public var selectedCalendarIDs: [String]

    public init(id: String, email: String, displayName: String, selectedCalendarIDs: [String] = []) {
        self.id = id
        self.email = email
        self.displayName = displayName
        self.selectedCalendarIDs = selectedCalendarIDs
    }
}

/// Bridges the pure `CalendarSyncService` to the app's SwiftData store, the
/// browser OAuth flow, and device settings. Accounts and selections live in
/// UserDefaults; refresh tokens live in Keychain via `GoogleCredentialStore`.
@MainActor
public final class CalendarSyncCoordinator: NSObject, ObservableObject {
    public static let accountsKey = "anchor.calendar.accounts"
    public static let disconnectedAccountsKey = "anchor.calendar.disconnected-accounts"
    public static let lastSyncKey = "anchor.calendar.last-sync"

    @Published public private(set) var accounts: [ConnectedGoogleAccount] = []
    @Published public private(set) var availableCalendars: [String: [GoogleCalendarInfo]] = [:]
    @Published public private(set) var status: String?
    @Published public private(set) var connectionIssue: String?
    @Published public private(set) var reconnectAccounts: Set<String> = []
    @Published public private(set) var calendarListIssues: [String: String] = [:]
    @Published public private(set) var isConnecting = false

    private let authRunner: any GoogleAuthSessionRunner
    private let tokenClient: GoogleTokenClient
    private let calendarStore: any GoogleCalendarStoreProtocol
    private let credentialStore: any GoogleCredentialStore
    private let service: CalendarSyncService
    private let clientID: String
    private var calendarListRequests: [String: UUID] = [:]
    private var isSyncing = false
    private var syncWaiters: [CheckedContinuation<Void, Never>] = []

    public override init() {
        let store = URLSessionGoogleCalendarStore()
        authRunner = ASWebAuthSessionRunner()
        tokenClient = GoogleTokenClient()
        calendarStore = store
        #if canImport(Security)
        credentialStore = KeychainGoogleCredentialStore()
        #else
        credentialStore = UnconfiguredCredentialStore()
        #endif
        service = CalendarSyncService(store: store)
        clientID = GoogleCalendarConfig.clientID()
        super.init()
        accounts = Self.loadAccounts()
    }

    /// Injectable seam for tests and previews.
    public init(
        authRunner: any GoogleAuthSessionRunner,
        tokenClient: GoogleTokenClient,
        calendarStore: any GoogleCalendarStoreProtocol,
        credentialStore: any GoogleCredentialStore,
        defaults: UserDefaults = .standard,
        clientID: String = GoogleCalendarConfig.clientID()
    ) {
        self.authRunner = authRunner
        self.tokenClient = tokenClient
        self.calendarStore = calendarStore
        self.credentialStore = credentialStore
        self.defaults = defaults
        self.clientID = clientID
        service = CalendarSyncService(store: calendarStore)
        super.init()
        accounts = Self.loadAccounts(defaults: defaults)
    }

    private var defaults: UserDefaults = .standard

    public var isConfigured: Bool { !clientID.isEmpty }
    public var lastSyncedAt: Date? { defaults.object(forKey: Self.lastSyncKey) as? Date }

    // MARK: - Connect / disconnect

    /// Runs the OAuth flow: browser sign-in, code exchange, identity lookup,
    /// calendar list. Connecting the same Google identity again refreshes its
    /// credentials and calendar list without duplicating the account.
    @discardableResult
    public func connect(reconnecting expected: ConnectedGoogleAccount? = nil) async -> Bool {
        guard !clientID.isEmpty else {
            connectionIssue = "Google sign-in is not configured in this build yet."
            return false
        }
        guard !isConnecting else { return false }
        connectionIssue = nil
        isConnecting = true
        defer { isConnecting = false }
        do {
            let request = try GoogleCalendarConfig.makeAuthorizationRequest(clientID: clientID)
            let callback = try await authRunner.authenticate(
                url: request.url,
                callbackScheme: GoogleCalendarConfig.callbackScheme(clientID: clientID)
            )
            let code = try GoogleCalendarConfig.authorizationCode(
                fromCallback: callback,
                expectedState: request.state
            )
            let tokens = try await tokenClient.exchange(
                code: code,
                verifier: request.verifier,
                redirectURI: request.redirectURI,
                clientID: clientID
            )
            guard let refreshToken = tokens.refreshToken else {
                throw GoogleCalendarError.missingRefreshToken
            }
            let identity: GoogleAccountIdentity
            if let decoded = tokens.idToken.flatMap(GoogleIDToken.identity(from:)) {
                identity = decoded
            } else {
                identity = try await calendarStore.accountIdentity(accessToken: tokens.accessToken)
            }
            if let expected, expected.id != identity.id {
                connectionIssue = "Choose \(expected.email.isEmpty ? expected.displayName : expected.email) in Google to reconnect this calendar."
                return false
            }
            let calendars: [GoogleCalendarInfo]
            do {
                calendars = try await calendarStore.calendars(accessToken: tokens.accessToken)
            } catch {
                connectionIssue = "Couldn’t load calendars for \(identity.displayName). "
                    + Self.connectionMessage(for: error)
                return false
            }
            guard expected == nil || accounts.contains(where: { $0.id == identity.id }) else {
                connectionIssue = "This account was removed during sign-in. Add it again to reconnect."
                return false
            }
            try await credentialStore.save(
                GoogleCredentials(
                    accessToken: tokens.accessToken,
                    refreshToken: refreshToken,
                    expiresAt: tokens.expiresAt
                ),
                accountID: identity.id
            )
            calendarListRequests.removeValue(forKey: identity.id)
            calendarListIssues.removeValue(forKey: identity.id)
            availableCalendars[identity.id] = calendars
            let previous = accounts.first(where: { $0.id == identity.id })
            var account = previous
                ?? ConnectedGoogleAccount(
                    id: identity.id,
                    email: identity.email,
                    displayName: identity.displayName
                )
            account.email = identity.email
            account.displayName = identity.displayName
            let fetchedIDs = Set(calendars.map(\.id))
            account.selectedCalendarIDs = previous?.selectedCalendarIDs.filter { fetchedIDs.contains($0) }
                ?? calendars.filter(\.isPrimary).map(\.id)
            upsert(account)
            var disconnected = disconnectedAccountIDs
            if disconnected.remove(account.id) != nil { persistDisconnected(disconnected) }
            reconnectAccounts.remove(account.id)
            connectionIssue = nil
            return true
        } catch let error as ASWebAuthenticationSessionError where error.code == .canceledLogin {
            connectionIssue = nil
        } catch {
            connectionIssue = Self.connectionMessage(for: error)
        }
        return false
    }

    private static func connectionMessage(for error: Error) -> String {
        if let googleError = error as? GoogleCalendarError { return googleError.connectionMessage }
        return "Google sign-in could not be completed. Check your connection and try again."
    }

    /// Forget the local account and revoke the grant. Shared block links
    /// remain intact so another connected device does not reimport duplicates.
    public func disconnect(accountID: String, context _: ModelContext, blocks _: [PlanBlock]) async {
        if let credentials = try? await credentialStore.load(accountID: accountID) {
            await tokenClient.revoke(credentials.refreshToken)
        }
        try? await credentialStore.delete(accountID: accountID)
        reconnectAccounts.remove(accountID)
        accounts.removeAll { $0.id == accountID }
        persistAccounts()
        availableCalendars.removeValue(forKey: accountID)
        calendarListRequests.removeValue(forKey: accountID)
        calendarListIssues.removeValue(forKey: accountID)

        persistDisconnected(disconnectedAccountIDs.union([accountID]))
        status = "Calendar account disconnected."
    }

    // MARK: - Calendar selection

    public func isCalendarSelected(accountID: String, calendarID: String) -> Bool {
        accounts.first(where: { $0.id == accountID })?.selectedCalendarIDs.contains(calendarID) == true
    }

    public func setCalendarSelected(accountID: String, calendarID: String, selected: Bool) {
        guard var account = accounts.first(where: { $0.id == accountID }) else { return }
        if selected && !account.selectedCalendarIDs.contains(calendarID) {
            account.selectedCalendarIDs.append(calendarID)
        } else if !selected {
            account.selectedCalendarIDs.removeAll { $0 == calendarID }
        }
        upsert(account)
        if account.selectedCalendarIDs.isEmpty { reconnectAccounts.remove(accountID) }
    }

    /// Refreshes the calendar list for a connected account — used after
    /// connect and by the settings surface on appear.
    public func refreshCalendars(accountID: String) async {
        guard accounts.contains(where: { $0.id == accountID }) else { return }
        let request = UUID()
        calendarListRequests[accountID] = request
        do {
            let token = try await accessToken(for: accountID)
            let calendars = try await calendarStore.calendars(accessToken: token)
            guard calendarListRequests[accountID] == request else { return }
            availableCalendars[accountID] = calendars
            calendarListIssues.removeValue(forKey: accountID)
        } catch {
            guard calendarListRequests[accountID] == request, !Task.isCancelled else { return }
            calendarListIssues[accountID] = "Couldn’t refresh calendars. " + Self.connectionMessage(for: error)
        }
    }

    // MARK: - Sync

    public func sync(context: ModelContext, blocks _: [PlanBlock]) async {
        _ = await sync(context: context, window: CalendarSyncPolicy.syncWindow(now: Date()))
    }

    /// Import the displayed period. Each caller awaits its own period, even when
    /// a rolling import or another window is already in flight.
    @discardableResult
    public func sync(context: ModelContext, window: DateInterval) async -> String? {
        guard isConfigured, !accounts.isEmpty, !Task.isCancelled else { return nil }
        if isSyncing {
            await withCheckedContinuation { syncWaiters.append($0) }
        }
        isSyncing = true
        defer {
            if syncWaiters.isEmpty { isSyncing = false }
            else { syncWaiters.removeFirst().resume() }
        }
        guard !Task.isCancelled else { return nil }

        let requested = accounts.filter { !$0.selectedCalendarIDs.isEmpty }
        var syncAccounts: [CalendarSyncAccount] = []
        var expiredAccess: Set<String> = []
        var accessFailures: [String: String] = [:]
        for account in requested {
            do {
                let token = try await accessToken(for: account.id)
                syncAccounts.append(CalendarSyncAccount(
                    id: account.id,
                    accessToken: token,
                    selectedCalendarIDs: Set(account.selectedCalendarIDs)
                ))
            } catch {
                if GoogleCalendarError.requiresReconnect(error, refreshingAccess: true) { expiredAccess.insert(account.id) }
                accessFailures[account.id] = GoogleCalendarError.importMessage(for: error, refreshingAccess: true)
            }
        }

        let batch = await service.fetch(accounts: syncAccounts, window: window)
        guard !Task.isCancelled else { return nil }
        let eligible = Set(requested.filter { accounts.contains($0) }.map(\.id))
        reconnectAccounts = expiredAccess.union(batch.reconnectAccounts).intersection(eligible)
        guard !eligible.isEmpty else { return nil }
        guard !context.hasChanges else {
            return syncFailure("Calendar import paused while planner edits are being saved. Try again.")
        }

        let report: CalendarSyncReport
        do {
            let linked = FetchDescriptor<PlanBlock>(predicate: #Predicate { $0.externalEventKey != nil })
            let blocks = try context.fetch(linked)
            // Read after the network await so a removal during import also wins.
            let removals = try context.fetch(FetchDescriptor<RemovedCalendarOccurrence>())
            report = batch.reconcile(blocks: blocks.map { $0.snapshot() }, eligibleAccountIDs: eligible,
                                     removedEventKeys: Set(removals.map(\.eventKey)), now: Date())
            let markers = Dictionary(grouping: removals, by: \.eventKey)
            let stale = blocks.filter { block in block.externalEventKey.map { markers[$0] != nil } ?? false }
            for (key, copies) in Dictionary(grouping: stale, by: { $0.externalEventKey! }) {
                RemovedCalendarOccurrence.remember(key: key, blockIDs: copies.map(\.id),
                                                   existing: markers[key] ?? [], in: context)
            }
            try apply(report: report, to: blocks, context: context)
        } catch {
            context.rollback()
            return syncFailure("Anchor could not save the calendar import. Try again.")
        }

        let failures = accessFailures.merging(report.failureReasons) { _, reason in reason }
        let details = requested.compactMap { account -> String? in
            guard eligible.contains(account.id), let reason = failures[account.id] else { return nil }
            let label = account.email.isEmpty ? account.displayName : account.email
            return "\(label) — \(reason)"
        }
        if details.count < eligible.count { defaults.set(report.syncedAt, forKey: Self.lastSyncKey) }
        if !details.isEmpty {
            return syncFailure((details + ["Previously imported entries were kept."]).joined(separator: "\n"))
        }
        if report.creations.isEmpty && report.updates.isEmpty && report.deletions.isEmpty && report.detachments.isEmpty {
            status = "Calendars are up to date."
        } else {
            status = "Imported \(report.creations.count) event\(report.creations.count == 1 ? "" : "s") from Google Calendar."
        }
        return nil
    }

    private func syncFailure(_ message: String) -> String {
        status = message
        return message
    }

    private func apply(report: CalendarSyncReport, to blocks: [PlanBlock], context: ModelContext) throws {
        let byID = Dictionary(blocks.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        for event in report.creations {
            context.insert(PlanBlock(
                title: event.title,
                plannedStart: event.start,
                plannedSeconds: max(60, Int(event.end.timeIntervalSince(event.start))),
                kind: .commitment,
                flexibility: .fixed
            ).withExternalEventKey(event.linkKey))
        }
        for update in report.updates {
            guard let block = byID[update.blockID] else { continue }
            block.title = update.event.title
            block.plannedStart = update.event.start
            block.plannedSeconds = max(60, Int(update.event.end.timeIntervalSince(update.event.start)))
            block.updatedAt = report.syncedAt
        }
        for blockID in report.deletions {
            if let block = byID[blockID] { context.delete(block) }
        }
        for blockID in report.detachments {
            byID[blockID]?.externalEventKey = nil
        }
        if context.hasChanges { try context.save() }
    }

    // MARK: - Tokens and persistence

    private func accessToken(for accountID: String) async throws -> String {
        guard let credentials = try await credentialStore.load(accountID: accountID) else {
            throw GoogleCalendarError.missingRefreshToken
        }
        guard credentials.isExpired() else { return credentials.accessToken }
        let tokens = try await tokenClient.refresh(
            credentials.refreshToken,
            clientID: clientID
        )
        let updated = GoogleCredentials(
            accessToken: tokens.accessToken,
            refreshToken: tokens.refreshToken ?? credentials.refreshToken,
            expiresAt: tokens.expiresAt
        )
        try await credentialStore.save(updated, accountID: accountID)
        return updated.accessToken
    }

    private func upsert(_ account: ConnectedGoogleAccount) {
        if let index = accounts.firstIndex(where: { $0.id == account.id }) {
            accounts[index] = account
        } else {
            accounts.append(account)
        }
        persistAccounts()
    }

    private var disconnectedAccountIDs: Set<String> {
        guard let data = defaults.data(forKey: Self.disconnectedAccountsKey) else { return [] }
        return (try? JSONDecoder().decode(Set<String>.self, from: data)) ?? []
    }

    private func persistDisconnected(_ ids: Set<String>) {
        defaults.set(try? JSONEncoder().encode(ids), forKey: Self.disconnectedAccountsKey)
    }

    private func persistAccounts() {
        guard let data = try? JSONEncoder().encode(accounts) else { return }
        defaults.set(data, forKey: Self.accountsKey)
    }

    private static func loadAccounts(defaults: UserDefaults = .standard) -> [ConnectedGoogleAccount] {
        guard let data = defaults.data(forKey: accountsKey),
              let accounts = try? JSONDecoder().decode([ConnectedGoogleAccount].self, from: data)
        else { return [] }
        return accounts
    }
}

private extension PlanBlock {
    func withExternalEventKey(_ key: String) -> PlanBlock {
        externalEventKey = key
        return self
    }
}

/// Fallback for platforms without Security — satisfies the seam but stores
/// nothing, so connect always reports failure rather than pretending.
private struct UnconfiguredCredentialStore: GoogleCredentialStore {
    func load(accountID _: String) async throws -> GoogleCredentials? { nil }
    func save(_: GoogleCredentials, accountID _: String) async throws {
        throw GoogleCalendarError.keychain(status: 0)
    }
    func delete(accountID _: String) async throws {}
}

/// The real browser flow. Mirrors the Hub sign-in pattern: ephemeral-cookie
/// off so the Google account chooser is available, presentation anchor from
/// the front window.
private final class ASWebAuthSessionRunner: NSObject,
    GoogleAuthSessionRunner,
    ASWebAuthenticationPresentationContextProviding,
    @unchecked Sendable
{
    private var session: ASWebAuthenticationSession?

    func authenticate(url: URL, callbackScheme: String) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            // The completion handler may run on Safari's XPC executor — keep
            // it nonisolated; resuming the continuation is thread-safe.
            let completion: ASWebAuthenticationSession.CompletionHandler = { callbackURL, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let callbackURL {
                    continuation.resume(returning: callbackURL)
                } else {
                    continuation.resume(throwing: GoogleCalendarError.invalidResponse)
                }
            }
            let session = ASWebAuthenticationSession(
                url: url,
                callbackURLScheme: callbackScheme,
                completionHandler: completion
            )
            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = false
            self.session = session
            guard session.start() else {
                self.session = nil
                continuation.resume(throwing: GoogleCalendarError.invalidResponse)
                return
            }
        }
    }

    func presentationAnchor(for _: ASWebAuthenticationSession) -> ASPresentationAnchor {
        #if os(iOS)
        return UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow) ?? ASPresentationAnchor()
        #elseif os(macOS)
        return NSApplication.shared.keyWindow ?? NSWindow()
        #endif
    }
}
#endif
