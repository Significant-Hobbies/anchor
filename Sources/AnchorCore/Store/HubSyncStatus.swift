#if !os(watchOS)
import CryptoKit
import Foundation
import PersonalSyncKit

public enum HubSyncFailure: String, Codable, Equatable, Sendable {
    case signInExpired
    case offline
    case service

    public static func classify(_ error: any Error) -> Self {
        if let syncError = error as? PersonalSyncError,
           case let .server(status, _) = syncError,
           status == 401 || status == 403 {
            return .signInExpired
        }

        if let identityError = error as? PersonalIdentityError {
            switch identityError {
            case .missingSession:
                return .signInExpired
            case let .server(status, _) where status == 401 || status == 403:
                return .signInExpired
            default:
                break
            }
        }

        if let urlError = error as? URLError {
            switch urlError.code {
            case .notConnectedToInternet, .networkConnectionLost,
                 .internationalRoamingOff, .dataNotAllowed:
                return .offline
            default:
                break
            }
        }

        return .service
    }

    public static func classify(accountMessage: String) -> Self {
        let message = accountMessage.lowercased()
        if message.contains("offline") || message.contains("internet connection")
            || message.contains("network connection was lost") {
            return .offline
        }
        return .service
    }

    public func explanation(pendingCount: Int) -> String {
        let waiting = Self.waitingSummary(pendingCount)
        switch self {
        case .signInExpired:
            return "Your Hub sign-in expired. \(waiting) Sign out, then reconnect to retry."
        case .offline:
            return "You're offline. \(waiting) Anchor will retry the next time it can reach the Hub."
        case .service:
            return "The Hub service couldn't complete sync. \(waiting) Try again in a moment."
        }
    }

    private static func waitingSummary(_ count: Int) -> String {
        switch count {
        case 0: "No finished session summaries are waiting locally."
        case 1: "1 finished session summary is safe and waiting locally."
        default: "\(count) finished session summaries are safe and waiting locally."
        }
    }
}

public struct HubSyncReceipt: Codable, Equatable, Sendable {
    public var lastSuccessfulAt: Date?
    public var failure: HubSyncFailure?
    public var failedAt: Date?

    public init(
        lastSuccessfulAt: Date? = nil,
        failure: HubSyncFailure? = nil,
        failedAt: Date? = nil
    ) {
        self.lastSuccessfulAt = lastSuccessfulAt
        self.failure = failure
        self.failedAt = failedAt
    }

    public mutating func recordSuccess(at date: Date) {
        lastSuccessfulAt = date
        failure = nil
        failedAt = nil
    }

    public mutating func recordFailure(_ failure: HubSyncFailure, at date: Date) {
        self.failure = failure
        failedAt = date
    }
}

@MainActor
public struct HubSyncReceiptStore {
    private let defaults: UserDefaults
    private let key: String

    public init(
        defaults: UserDefaults = .standard,
        key: String = "anchor.hub-sync-receipt.v1"
    ) {
        self.defaults = defaults
        self.key = key
    }

    /// Stable IDs, rather than mutable email addresses or bearer tokens, own
    /// receipts and runtime files. The legacy key remains untouched.
    static func namespace(for userID: String) -> String {
        SHA256.hash(data: Data(userID.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    func scoped(to userID: String) -> Self {
        Self(defaults: defaults, key: "\(key).account.\(Self.namespace(for: userID))")
    }

    public func load() -> HubSyncReceipt {
        guard let data = defaults.data(forKey: key),
              let receipt = try? JSONDecoder().decode(HubSyncReceipt.self, from: data)
        else { return HubSyncReceipt() }
        return receipt
    }

    public func save(_ receipt: HubSyncReceipt) {
        guard let data = try? JSONEncoder().encode(receipt) else { return }
        defaults.set(data, forKey: key)
    }
}
#endif
