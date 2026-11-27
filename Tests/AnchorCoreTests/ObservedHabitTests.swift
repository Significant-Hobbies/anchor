import Foundation
import Testing
@testable import AnchorCore

@Test("Habit insights count distinct recorded days, ignore future activity and merge title variants")
func recurringActivityDays() {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    let day = Date(timeIntervalSince1970: 86400)
    let end = day.addingTimeInterval(3 * 86400)
    let observations = [
        ("Walk", day), ("walk", day), (" Walk ", day.addingTimeInterval(86400)),
        ("Walk", day.addingTimeInterval(2 * 86400)), ("Walk", end.addingTimeInterval(86400)),
        ("Gym", day), ("Gym", end), ("Gym", day.addingTimeInterval(-86400))
    ]
    let insights = ObservedHabit.derive(observations, from: day, through: end, calendar: calendar)
    #expect(insights.map(\.id) == ["walk"])
    #expect(insights.first?.days == 3)
}
