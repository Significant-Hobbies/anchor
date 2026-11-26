import Foundation

/// An owner's account of a slot. A linked copy shares the source block's ID,
/// but its editable fields are independent of the calendar and focus timer.
public struct DayLedgerEntry: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public var title: String
    public var start: Date
    public var end: Date
    public var notes: String

    public init(id: UUID = UUID(), title: String, start: Date, end: Date, notes: String = "") {
        self.id = id
        self.title = title
        self.start = start
        self.end = end
        self.notes = notes
    }

    public func seconds(in period: DateInterval) -> Double {
        max(0, min(end, period.end).timeIntervalSince(max(start, period.start)))
    }
}

public struct DayLedgerComparison {
    public let plans: [DayLedgerEntry]
    public let actuals: [DayLedgerEntry]
    public let matched, changed, unrecorded, unplanned: Int
    public let plannedSeconds, recordedSeconds: Double
    public let linkedVarianceSeconds, unplannedSeconds: Double

    public init(period: DateInterval, plans: [DayLedgerEntry], actuals: [DayLedgerEntry]) {
        self.plans = plans.filter { $0.seconds(in: period) > 0 }.sorted { ($0.start, $0.title) < ($1.start, $1.title) }
        self.actuals = actuals.filter { $0.seconds(in: period) > 0 }.sorted { ($0.start, $0.title) < ($1.start, $1.title) }
        let byID = Dictionary(actuals.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let planIDs = Set(plans.map(\.id))
        var same = 0, different = 0
        var variance: Double = 0
        for plan in self.plans {
            guard let actual = byID[plan.id] else { continue }
            variance += actual.seconds(in: period) - plan.seconds(in: period)
            if plan == actual { same += 1 } else { different += 1 }
        }
        matched = same
        changed = different
        unrecorded = self.plans.count - same - different
        let extras = self.actuals.filter { !planIDs.contains($0.id) }
        unplanned = extras.count
        unplannedSeconds = extras.reduce(0) { $0 + $1.seconds(in: period) }
        // Actuals moved in from a plan outside the period also contribute here.
        let localIDs = Set(self.plans.map(\.id))
        linkedVarianceSeconds = variance + self.actuals.filter {
            planIDs.contains($0.id) && !localIDs.contains($0.id)
        }.reduce(0) { $0 + $1.seconds(in: period) }
        plannedSeconds = self.plans.reduce(0) { $0 + $1.seconds(in: period) }
        recordedSeconds = self.actuals.reduce(0) { $0 + $1.seconds(in: period) }
    }
}

/// One atomic, device-private file per entry. Coordinated compare-and-swap
/// keeps two windows from silently replacing a more recent edit.
public struct DayLedgerStore {
    private let folder: URL
    public init(storeURL: URL) { folder = storeURL.appendingPathExtension("actual-entries") }

    public func load() throws -> [DayLedgerEntry] {
        let files: [URL]
        do { files = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil) }
        catch let error as CocoaError where error.code == .fileReadNoSuchFile { return [] }
        return try files.filter { $0.pathExtension == "json" }.map { url in
            let entry = try JSONDecoder().decode(DayLedgerEntry.self, from: Data(contentsOf: url))
            guard entry.id == UUID(uuidString: url.deletingPathExtension().lastPathComponent) else {
                throw CocoaError(.fileReadCorruptFile)
            }
            return entry
        }
    }

    public func save(_ entry: DayLedgerEntry, replacing previous: DayLedgerEntry?) throws {
        guard entry.end > entry.start, !entry.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw CocoaError(.fileWriteInvalidFileName)
        }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        var location = folder
        var flags = URLResourceValues()
        flags.isExcludedFromBackup = true
        try location.setResourceValues(flags)
        try change(id: entry.id, from: previous, to: entry)
    }

    public func remove(_ previous: DayLedgerEntry) throws {
        try change(id: previous.id, from: previous, to: nil)
    }

    private func change(id: UUID, from previous: DayLedgerEntry?, to entry: DayLedgerEntry?) throws {
        let url = folder.appendingPathComponent(id.uuidString).appendingPathExtension("json")
        var coordinationError: NSError?
        var writeError: Error?
        NSFileCoordinator().coordinate(writingItemAt: url, options: entry == nil ? .forDeleting : .forReplacing, error: &coordinationError) { destination in
            do {
                let existing: DayLedgerEntry?
                do { existing = try JSONDecoder().decode(DayLedgerEntry.self, from: Data(contentsOf: destination)) }
                catch let error as CocoaError where error.code == .fileReadNoSuchFile { existing = nil }
                if existing == entry { return }
                guard existing == previous else { throw CocoaError(.fileWriteFileExists) }
                if let entry {
                    try JSONEncoder().encode(entry).write(to: destination, options: .atomic)
                } else {
                    try FileManager.default.removeItem(at: destination)
                }
            } catch { writeError = error }
        }
        if let coordinationError { throw coordinationError }
        if let writeError { throw writeError }
    }
}
