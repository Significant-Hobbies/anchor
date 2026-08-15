import Foundation

/// Deterministic fallback classifier.
///
/// This exists because Apple Intelligence is not universally available: the
/// device may be ineligible, the user may have it switched off, or the model
/// assets may still be downloading. In all of those cases Anchor still has to
/// produce useful analytics, so tagging degrades instead of disappearing.
///
/// It is also what the tests assert against, since a language model's output is
/// not a stable thing to write assertions about.
public struct HeuristicTagger: Sendable {
    public init() {}

    /// Ordered most-specific first: the first bucket with a hit wins, so
    /// "slack message from mum" lands on `.message`, not `.person`.
    private static let distractionCues: [(DistractionKind, [String])] = [
        (.meeting, ["meeting", "standup", "stand-up", "call with", "zoom", "huddle", "1:1", "one on one", "interview", "sync"]),
        (.message, ["slack", "whatsapp", "imessage", "text from", "texted", "dm", "discord", "telegram", "message", "messaged", "signal", "chat"]),
        (.email, ["email", "inbox", "gmail", "mail from", "newsletter"]),
        (.notification, ["notification", "badge", "popup", "pop-up", "alert", "banner", "buzzed", "pinged", "ping"]),
        (.socialFeed, ["twitter", "x.com", "instagram", "reddit", "linkedin", "tiktok", "facebook", "threads", "hacker news", "hn", "feed", "scroll", "scrolling"]),
        (.entertainment, ["youtube", "netflix", "twitch", "video", "podcast", "music", "spotify", "game", "gaming", "movie", "show"]),
        (.rabbitHole, ["rabbit hole", "wikipedia", "googling", "googled", "searching", "looked up", "research", "docs", "stack overflow", "tangent", "went down"]),
        (.person, ["knocked", "walked in", "asked me", "colleague", "roommate", "wife", "husband", "partner", "kid", "kids", "mum", "mom", "dad", "someone", "stopped by", "tapped me"]),
        (.chore, ["laundry", "dishes", "clean", "tidy", "grocery", "groceries", "errand", "package", "delivery", "bill", "chore", "shopping"]),
        (.bodily, ["hungry", "food", "snack", "coffee", "tea", "water", "bathroom", "toilet", "tired", "sleepy", "stretch", "walk", "headache", "sore"]),
        (.environment, ["noise", "noisy", "loud", "construction", "traffic", "hot", "cold", "bright", "music next door", "neighbour", "neighbor"]),
        (.otherWork, ["other task", "another task", "different project", "bug", "ticket", "pr ", "code review", "deploy", "urgent", "fire", "escalation", "switched to"]),
        (.wanderingThought, ["thought", "remembered", "wondering", "worried", "anxious", "daydream", "mind wandered", "zoned out", "idea", "overthinking"]),
    ]

    private static let goalCues: [(GoalTheme, [String])] = [
        (.building, ["build", "code", "implement", "ship", "fix", "refactor", "debug", "feature", "api", "app", "deploy", "migrate", "test"]),
        (.writing, ["write", "writing", "draft", "essay", "blog", "post", "chapter", "copy", "documentation", "docs", "report", "email"]),
        (.learning, ["learn", "study", "read", "course", "revise", "practice", "tutorial", "paper", "lecture", "exam"]),
        (.planning, ["plan", "roadmap", "strategy", "scope", "spec", "outline", "prioritis", "prioritiz", "backlog", "review", "retro"]),
        (.communication, ["reply", "respond", "call", "meeting", "outreach", "follow up", "follow-up", "interview", "message", "client"]),
        (.admin, ["invoice", "tax", "expense", "admin", "paperwork", "form", "book", "schedule", "inbox", "cleanup", "organis", "organiz"]),
        (.creative, ["design", "sketch", "draw", "paint", "edit", "video", "music", "photo", "brand", "logo", "ui", "mock"]),
    ]

    public func classifyDistraction(note: String) -> DistractionTagging {
        let haystack = note.lowercased()
        for (kind, cues) in Self.distractionCues {
            if cues.contains(where: haystack.contains) {
                return DistractionTagging(
                    kind: kind,
                    confidence: 0.5,
                    keywords: Self.keywords(from: note),
                    source: .heuristic
                )
            }
        }
        return DistractionTagging(
            kind: .other,
            confidence: 0.2,
            keywords: Self.keywords(from: note),
            source: .heuristic
        )
    }

    public func classifyGoal(title: String, notes: String = "") -> GoalTagging {
        let haystack = (title + " " + notes).lowercased()
        for (theme, cues) in Self.goalCues where cues.contains(where: haystack.contains) {
            return GoalTagging(theme: theme, keywords: Self.keywords(from: title), source: .heuristic)
        }
        return GoalTagging(theme: .other, keywords: Self.keywords(from: title), source: .heuristic)
    }

    /// Content words, lowercased and de-duplicated. Used to cluster near-identical
    /// notes ("slack from Ravi" / "Ravi slacked me") into one row in analytics.
    static func keywords(from text: String, limit: Int = 4) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for raw in text.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber }) {
            let word = String(raw)
            guard word.count > 2, !stopWords.contains(word), seen.insert(word).inserted else { continue }
            result.append(word)
            if result.count == limit { break }
        }
        return result
    }

    private static let stopWords: Set<String> = [
        "the", "and", "for", "but", "was", "were", "has", "had", "have", "with", "that", "this",
        "from", "about", "into", "just", "got", "get", "gets", "getting", "now", "then", "than",
        "some", "someone", "something", "kept", "keep", "keeps", "want", "wanted", "need", "needed",
        "really", "very", "again", "back", "out", "off", "over", "started", "start", "check",
        "checking", "checked", "look", "looking", "looked", "went", "going", "goes", "not", "you",
        "your", "his", "her", "their", "them", "they", "she", "him", "its", "our", "who", "why",
        "how", "what", "when", "where", "all", "any", "one", "two", "did", "does", "doing", "done",
    ]
}

// MARK: - Results

public enum TagSource: String, Codable, Sendable {
    /// Apple's on-device foundation model.
    case onDeviceModel
    /// Keyword rules.
    case heuristic
    /// The user chose it.
    case user
}

public struct DistractionTagging: Equatable, Sendable {
    public var kind: DistractionKind
    public var confidence: Double
    public var keywords: [String]
    public var source: TagSource

    public init(kind: DistractionKind, confidence: Double, keywords: [String], source: TagSource) {
        self.kind = kind
        self.confidence = confidence
        self.keywords = keywords
        self.source = source
    }
}

public struct GoalTagging: Equatable, Sendable {
    public var theme: GoalTheme
    public var keywords: [String]
    public var source: TagSource

    public init(theme: GoalTheme, keywords: [String], source: TagSource) {
        self.theme = theme
        self.keywords = keywords
        self.source = source
    }
}
