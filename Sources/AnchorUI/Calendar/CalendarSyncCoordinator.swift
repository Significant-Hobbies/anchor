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
    public static let lastSyncKey = "anchor.calendar.last-sync"

    @Published public private(set) var accounts: [ConnectedGoogleAccount] = []
    @Published public private(set) var availableCalendars: [String: [GoogleCalendarInfo]] = [:]
    @Published public private(set) var status: String?
    @Published public private(set) var isConnecting = false

    private let authRunner: any GoogleAuthSessionRunner
    private let tokenClient: GoogleTokenClient
    private let calendarStore: any GoogleCalendarStoreProtocol
    private let credentialStore: any GoogleCredentialStore
    private let service: CalendarSyncService
    private let clientID: String
    private var isSyncing = false

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
    public func connect() async {
        guard !clientID.isEmpty else {
            status = "Google sign-in is not configured in this build yet."
            return
        }
        guard !isConnecting else { return }
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
            try await credentialStore.save(
                GoogleCredentials(
                    accessToken: tokens.accessToken,
                    refreshToken: refreshToken,
                    expiresAt: tokens.expiresAt
                ),
                accountID: identity.id
            )
            let calendars = (try? await calendarStore.calendars(accessToken: tokens.accessToken)) ?? []
            availableCalendars[identity.id] = calendars
            var account = accounts.first(where: { $0.id == identity.id })
                ?? ConnectedGoogleAccount(
                    id: identity.id,
                    email: identity.email,
                    displayName: identity.displayName
                )
            account.email = identity.email
            account.displayName = identity.displayName
            let fetchedIDs = Set(calendars.map(\.id))
            let kept = account.selectedCalendarIDs.filter { fetchedIDs.contains($0) }
            account.selectedCalendarIDs = kept.isEmpty
                ? calendars.filter(\.isPrimary).map(\.id)
                : kept
            upsert(account)
            status = nil
        } catch let error as ASWebAuthenticationSessionError where error.code == .canceledLogin {
            status = nil
        } catch {
            status = "Google sign-in could not be completed. Nothing was connected."
        }
    }

    /// Stops imports for the account: revokes the grant (best-effort), drops
    /// the Keychain credentials and the account record, and unlinks the
    /// account's imported blocks. Block contents — including past check-offs
    /// and history — are kept.
    public func disconnect(accountID: String, context: ModelContext, blocks: [PlanBlock]) async {
        if let credentials = try? await credentialStore.load(accountID: accountID) {
            await tokenClient.revoke(credentials.refreshToken)
        }
        try? await credentialStore.delete(accountID: accountID)
        accounts.removeAll { $0.id == accountID }
        persistAccounts()
        availableCalendars.removeValue(forKey: accountID)

        let prefix = GoogleCalendarEvent.linkPrefix(accountID: accountID)
        var detached = false
        for block in blocks where block.externalEventKey?.hasPrefix(prefix) == true {
            block.externalEventKey = nil
            detached = true
        }
        if detached { try? context.save() }
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
    }

    /// Refreshes the calendar list for a connected account — used after
    /// connect and by the settings surface on appear.
    public func refreshCalendars(accountID: String) async {
        guard let token = try? await accessToken(for: accountID) else { return }
        availableCalendars[accountID] = (try? await calendarStore.calendars(accessToken: token)) ?? []
    }

    // MARK: - Sync

    /// One import pass over every connected account. Access tokens are
    /// refreshed lazily; an account that cannot authenticate is skipped and
    /// its blocks are left completely untouched.
    public func sync(context: ModelContext, blocks: [PlanBlock]) async {
        guard isConfigured, !accounts.isEmpty, !isSyncing else { return }
        isSyncing = true
        defer { isSyncing = false }

        var syncAccounts: [CalendarSyncAccount] = []
        var unauthenticated = 0
        for account in accounts where !account.selectedCalendarIDs.isEmpty {
            do {
                let token = try await accessToken(for: account.id)
                syncAccounts.append(CalendarSyncAccount(
                    id: account.id,
                    accessToken: token,
                    selectedCalendarIDs: Set(account.selectedCalendarIDs)
                ))
            } catch {
                unauthenticated += 1
            }
        }

        let report = await service.sync(
            accounts: syncAccounts,
            blocks: blocks.map { $0.snapshot() }
        )
        apply(report: report, to: blocks, context: context)
        defaults.set(report.syncedAt, forKey: Self.lastSyncKey)

        let skipped = report.failedAccounts.count + unauthenticated
        status = if skipped > 0 {
            "\(skipped) calendar account\(skipped == 1 ? "" : "s") could not be reached; its blocks were left alone."
        } else if report.creations.isEmpty && report.updates.isEmpty
            && report.deletions.isEmpty && report.detachments.isEmpty {
            "Calendars are up to date."
        } else {
            "Imported \(report.creations.count) event\(report.creations.count == 1 ? "" : "s") from Google Calendar."
        }
    }

    private func apply(report: CalendarSyncReport, to blocks: [PlanBlock], context: ModelContext) {
        let byID = Dictionary(uniqueKeysWithValues: blocks.map { ($0.id, $0) })
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
        try? context.save()
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
