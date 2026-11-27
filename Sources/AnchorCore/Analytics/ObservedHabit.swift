import Foundation

public struct ObservedHabit: Identifiable, Equatable, Sendable {
    public let id: String
    public let title: String
    public let days: Int

    public static func derive(_ observations: [(String, Date)], from start: Date, through end: Date,
                              calendar: Calendar = .current) -> [Self] {
        var dates: [String: Set<Date>] = [:]
        var labels: [String: String] = [:]
        for (raw, date) in observations where date >= start && date <= end {
            let title = raw.split(whereSeparator: \.isWhitespace).joined(separator: " ")
            guard !title.isEmpty else { continue }
            let key = title.lowercased()
            dates[key, default: []].insert(calendar.startOfDay(for: date))
            labels[key] = min(labels[key] ?? title, title)
        }
        return dates.compactMap { key, days in
            guard days.count >= 3, let title = labels[key] else { return nil }
            return Self(id: key, title: title, days: days.count)
        }.sorted { $0.days == $1.days ? $0.id < $1.id : $0.days > $1.days }
    }
}
