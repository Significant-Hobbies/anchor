import Foundation

public enum HubHistoryOwnershipError: LocalizedError {
    case approvalRequired, differentAccount, activeSession, invalidOwner

    public var errorDescription: String? {
        switch self {
        case .approvalRequired: "Approve local history for this Hub account before syncing."
        case .differentAccount: "This device's Hub history belongs to another account. Sign in to that account to sync."
        case .activeSession: "Finish the active focus session before approving Hub history."
        case .invalidOwner: "The saved Hub approval could not be read. Local history is preserved."
        }
    }
}

/// A device-local approval. Session-level ownership travels separately in iCloud.
public struct HubHistoryOwnershipStore: Sendable {
    private let fileURL: URL
    public init(directory: URL) {
        fileURL = directory.appending(path: "anchor-hub-history-owner.json")
    }
    public func owner() throws -> String? {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        guard let value = try? JSONDecoder().decode(String.self, from: Data(contentsOf: fileURL)),
              !value.isEmpty else { throw HubHistoryOwnershipError.invalidOwner }
        return value
    }
    public func approve(_ userID: String) throws {
        guard !userID.isEmpty else { throw HubHistoryOwnershipError.invalidOwner }
        if let existing = try owner() {
            guard existing == userID else { throw HubHistoryOwnershipError.differentAccount }
            return
        }
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(userID).write(to: fileURL, options: .atomic)
    }
}
