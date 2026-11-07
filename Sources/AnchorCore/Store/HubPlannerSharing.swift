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
        var consentGeneration: String?
        var explicitProjectClearSessionIDs: Set<String>?
        var pendingPlannerApprovalNames: Set<String>?
    }
    let fileURL: URL
    init(directory: URL) { fileURL = directory.appending(path: "anchor-hub-planner-sharing.json") }
    func load() throws -> State? {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        let value = try JSONDecoder().decode(State.self, from: Data(contentsOf: fileURL))
        guard !value.owner.isEmpty else { throw HubHistoryOwnershipError.invalidOwner }
        return value
    }
    private func state(for owner: String) throws -> State {
        guard !owner.isEmpty else { throw HubHistoryOwnershipError.invalidOwner }
        let previous = try load()
        guard previous == nil || previous?.owner == owner else { throw HubHistoryOwnershipError.differentAccount }
        return previous ?? State(owner: owner, enabled: false, names: [])
    }
    private func persist(_ state: State) throws {
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(state).write(to: fileURL, options: .atomic)
    }
    func save(owner: String, enabled: Bool, names: Set<String>) throws {
        var state = try state(for: owner)
        if enabled && (!state.enabled || state.consentGeneration == nil) {
            state.enabledAt = Date()
            state.consentGeneration = UUID().uuidString.lowercased()
        }
        state.enabled = enabled
        state.names.formUnion(names)
        state.pendingPlannerApprovalNames = state.pendingPlannerApprovalNames?.subtracting(names)
        try persist(state)
    }
    func markExplicitProjectClears(owner: String, sessionIDs: Set<UUID>) throws {
        guard !sessionIDs.isEmpty else { return }
        var state = try state(for: owner)
        state.explicitProjectClearSessionIDs = (state.explicitProjectClearSessionIDs ?? []).union(sessionIDs.map(\.uuidString))
        try persist(state)
    }
    func updatePendingApproval(owner: String, names: Set<String>) throws {
        var state = try state(for: owner)
        state.pendingPlannerApprovalNames = names
        try persist(state)
    }
}
#endif
