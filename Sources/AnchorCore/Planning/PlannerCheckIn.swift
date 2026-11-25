import Foundation

public enum PlannerOutcome: String, CaseIterable, Codable, Sendable {
    case successful = "Successful"
    case unsuccessful = "Unsuccessful"
    case blocked = "Blocked"

    public var symbol: String {
        switch self {
        case .successful: "checkmark.circle"
        case .unsuccessful: "xmark.circle"
        case .blocked: "pause.circle"
        }
    }
}

/// A local check-in survives calendar removal and can still be resolved after
/// its original block disappears. Nothing here enters a synced model.
public struct PlannerCheckIn: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var title: String
    public var plannedStart: Date
    public var outcome: PlannerOutcome
    public var reason: String

    public init(id: UUID, title: String, plannedStart: Date, outcome: PlannerOutcome, reason: String) {
        self.id = id
        self.title = title
        self.plannedStart = plannedStart
        self.outcome = outcome
        self.reason = outcome == .blocked ? reason.trimmingCharacters(in: .whitespacesAndNewlines) : ""
    }
}

public struct PlannerCheckInStore {
    public enum ValidationError: Error { case missingBlockerReason }
    private let directory: URL

    public init(storeURL: URL) {
        directory = storeURL.appendingPathExtension("planner-check-ins")
    }

    public func load() throws -> (records: [UUID: PlannerCheckIn], hasUnreadableFiles: Bool) {
        let files: [URL]
        do {
            files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            return ([:], false)
        }
        var records: [UUID: PlannerCheckIn] = [:]
        var hasUnreadableFiles = false
        for file in files where file.pathExtension == "json" {
            do {
                let record = try JSONDecoder().decode(PlannerCheckIn.self, from: Data(contentsOf: file))
                guard UUID(uuidString: file.deletingPathExtension().lastPathComponent) == record.id else {
                    hasUnreadableFiles = true
                    continue
                }
                records[record.id] = record
            } catch { hasUnreadableFiles = true }
        }
        return (records, hasUnreadableFiles)
    }

    public func save(_ record: PlannerCheckIn) throws {
        guard record.outcome != .blocked || !record.reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ValidationError.missingBlockerReason
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                               attributes: [.posixPermissions: 0o700])
        var folder = directory
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try folder.setResourceValues(values)
        let file = folder.appendingPathComponent(record.id.uuidString + ".json")
        try JSONEncoder().encode(record).write(to: file, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
    }
}

public enum PlannerGap {
    /// Prefer a full half hour, otherwise use the longest remaining opening
    /// that fits the editor's five-minute duration increments.
    public static func opening(from start: Date, until end: Date, occupied: [DateInterval]) -> DateInterval? {
        var candidate = start
        var best: DateInterval?
        func consider(until boundary: Date) {
            let seconds = min(1800, floor(boundary.timeIntervalSince(candidate) / 300) * 300)
            if seconds >= 300 && seconds > (best?.duration ?? 0) {
                best = DateInterval(start: candidate, duration: seconds)
            }
        }
        for interval in occupied.sorted(by: { $0.start < $1.start }) where interval.end > candidate {
            consider(until: min(interval.start, end))
            if best?.duration == 1800 || interval.start >= end { return best }
            candidate = max(candidate, interval.end)
        }
        consider(until: end)
        return best
    }
}
