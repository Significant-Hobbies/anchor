import Foundation

public enum ActivityCategory: String, CaseIterable, Sendable {
    case meeting, fitness, meal, leisure, rest, work, personal, other

    private static let cues: [(ActivityCategory, Set<String>)] = [
        (.meeting, ["standup", "sync", "meeting", "interview", "huddle", "zoom"]),
        (.work, ["write", "draft", "design", "debug", "build", "study", "research", "coding", "tests", "release", "deploy"]),
        (.fitness, ["gym", "workout", "yoga", "pilates", "swim", "cycling", "jog", "run", "exercise"]),
        (.meal, ["breakfast", "lunch", "dinner", "brunch", "snack"]),
        (.leisure, ["game", "gaming", "movie", "concert", "playstation", "xbox"]),
        (.rest, ["sleep", "nap", "break", "meditate", "meditation"]),
        (.personal, ["groceries", "dentist", "laundry", "errands", "appointment"])
    ]

    public static func suggestion(for title: String) -> Self {
        let words = Set(title.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init))
        for (category, keywords) in cues where !keywords.isDisjoint(with: words) { return category }
        return .other
    }
}
