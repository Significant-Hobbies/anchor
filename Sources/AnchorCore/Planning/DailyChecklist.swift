import Foundation

public struct DailyChecklist: Codable, Equatable {
    public struct Item: Codable, Identifiable, Equatable {
        public let id: UUID
        public let title: String
        fileprivate var checkedDates: Set<String> = []

        public func isChecked(on date: String) -> Bool {
            checkedDates.contains(date)
        }
    }

    public fileprivate(set) var items: [Item] = []

    public static func dateKey(for date: Date, timeZone: TimeZone = .current) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let day = calendar.dateComponents([.year, .month, .day], from: date)
        return "\(day.year ?? 0)-\(day.month ?? 0)-\(day.day ?? 0)"
    }

    public static func availableDates(at now: Date, timeZone: TimeZone = .current) -> [String] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let today = dateKey(for: now, timeZone: timeZone)
        guard let yesterday = calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: now))
        else { return [today] }
        return [today, dateKey(for: yesterday, timeZone: timeZone)]
    }
}

public struct DailyChecklistStore {
    private let url: URL

    public init(storeURL: URL) {
        url = storeURL.appendingPathExtension("daily-checklist.json")
    }

    public func load() throws -> DailyChecklist {
        try load(from: url)
    }

    public func add(_ title: String) throws -> DailyChecklist {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return try load() }
        return try update { $0.items.append(.init(id: UUID(), title: title)) }
    }

    public func remove(_ id: UUID) throws -> DailyChecklist {
        try update { $0.items.removeAll { $0.id == id } }
    }

    public enum EditError: Error {
        case dateClosed
        case itemRemoved
    }

    public func setChecked(_ checked: Bool, itemID: UUID, on day: String,
                           now: () -> Date = Date.init, timeZone: () -> TimeZone = { .current }) throws -> DailyChecklist {
        try update { checklist in
            let dates = DailyChecklist.availableDates(at: now(), timeZone: timeZone())
            guard dates.contains(day) else { throw EditError.dateClosed }
            guard let index = checklist.items.firstIndex(where: { $0.id == itemID }) else { throw EditError.itemRemoved }
            for index in checklist.items.indices {
                checklist.items[index].checkedDates.formIntersection(dates)
            }
            if checked {
                checklist.items[index].checkedDates.insert(day)
            } else {
                checklist.items[index].checkedDates.remove(day)
            }
        }
    }

    private func load(from file: URL) throws -> DailyChecklist {
        do {
            return try JSONDecoder().decode(DailyChecklist.self, from: Data(contentsOf: file))
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            return DailyChecklist()
        }
    }

    private func update(_ edit: (inout DailyChecklist) throws -> Void) throws -> DailyChecklist {
        var coordinationError: NSError?
        var result: Result<DailyChecklist, Error>?
        NSFileCoordinator().coordinate(writingItemAt: url, options: .forReplacing, error: &coordinationError) { file in
            result = Result {
                var checklist = try load(from: file)
                try edit(&checklist)
                try JSONEncoder().encode(checklist).write(to: file, options: .atomic)
                return checklist
            }
        }
        if let coordinationError { throw coordinationError }
        guard let result else { throw CocoaError(.fileWriteUnknown) }
        return try result.get()
    }
}
