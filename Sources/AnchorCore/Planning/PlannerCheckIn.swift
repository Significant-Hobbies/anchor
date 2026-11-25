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

    public func load() throws -> [UUID: PlannerCheckIn] {
        let files: [URL]
        do {
            files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            return [:]
        }
        var records: [UUID: PlannerCheckIn] = [:]
        for file in files where file.pathExtension == "json" {
            let record = try JSONDecoder().decode(PlannerCheckIn.self, from: Data(contentsOf: file))
            records[record.id] = record
        }
        return records
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
    }
}

public enum PlannerGap {
    /// First opening for the editor's default 30-minute block. Keep the editor
    /// on the chosen day even when no full opening remains.
    public static func suggestedStart(from start: Date, until end: Date, occupied: [DateInterval]) -> Date {
        var candidate = start
        for interval in occupied.sorted(by: { $0.start < $1.start }) where interval.end > candidate {
            if candidate.addingTimeInterval(1800) <= interval.start { break }
            candidate = interval.end
        }
        return candidate.addingTimeInterval(1800) <= end ? candidate : min(start, end.addingTimeInterval(-60))
    }
}
