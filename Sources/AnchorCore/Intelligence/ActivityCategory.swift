import Foundation

public enum ActivityCategory: String, CaseIterable, Sendable {
    case meeting, fitness, meal, leisure, rest, work, personal, other

    private static let cues: [(ActivityCategory, Set<String>)] = [
        (.meeting, ["standup", "sync", "meeting", "interview", "huddle", "zoom", "retro", "retrospective", "kickoff", "standups", "catchup", "townhall", "demo"]),
        (.work, ["write", "draft", "design", "debug", "build", "study", "research", "coding", "writing", "studying", "implementation", "debugging", "documentation", "planning", "tests", "release", "deploy"]),
        (.fitness, ["gym", "workout", "yoga", "pilates", "swim", "cycling", "jog", "run", "running", "swimming", "walk", "walking", "exercise"]),
        (.meal, ["breakfast", "lunch", "dinner", "brunch", "snack", "meal"]),
        (.leisure, ["game", "gaming", "movie", "concert", "playstation", "xbox", "movies", "cinema", "games"]),
        (.rest, ["sleep", "nap", "sleeping", "bedtime", "break", "meditate", "meditation"]),
        (.personal, ["groceries", "dentist", "laundry", "errands", "appointment", "doctor", "commute", "shopping"])
    ]

    public static func suggestion(for title: String) -> Self {
        let tokens = title.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init)
        let phrase = " " + tokens.joined(separator: " ") + " "
        if title.range(of: #"\b1:1\b"#, options: .regularExpression) != nil { return .meeting }
        if [" stand up ", " 1 on 1 ", " one on one ", " catch up ", " kick off ", " team call ", " board meeting "].contains(where: phrase.contains) {
            return .meeting
        }
        let words = Set(tokens)
        for (category, keywords) in cues where !keywords.isDisjoint(with: words) { return category }
        return .other
    }
}
