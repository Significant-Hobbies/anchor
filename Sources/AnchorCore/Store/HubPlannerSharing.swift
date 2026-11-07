#if !os(watchOS)
import Foundation

/// Device-local consent and provenance; never enters CloudKit or an account payload.
/// Turning sharing off retains affiliation so a later account cannot adopt the planner.
struct HubPlannerSharingStore {
    struct State: Codable, Equatable {
        var owner: String
        var enabled: Bool
        var names: Set<String>
        var enabledAt: Date?
    }
    let fileURL: URL
    init(directory: URL) { fileURL = directory.appending(path: "anchor-hub-planner-sharing.json") }
    func load() throws -> State? {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        let value = try JSONDecoder().decode(State.self, from: Data(contentsOf: fileURL))
        guard !value.owner.isEmpty else { throw HubHistoryOwnershipError.invalidOwner }
        return value
    }
    func save(owner: String, enabled: Bool, names: Set<String>) throws {
        guard !owner.isEmpty else { throw HubHistoryOwnershipError.invalidOwner }
        let previous = try load()
        guard previous == nil || previous?.owner == owner else { throw HubHistoryOwnershipError.differentAccount }
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let enabledAt = enabled ? (previous?.enabled == true ? previous?.enabledAt ?? Date() : Date()) : previous?.enabledAt
        let state = State(owner: owner, enabled: enabled, names: (previous?.names ?? []).union(names), enabledAt: enabledAt)
        try JSONEncoder().encode(state).write(to: fileURL, options: .atomic)
    }
}
#endif
