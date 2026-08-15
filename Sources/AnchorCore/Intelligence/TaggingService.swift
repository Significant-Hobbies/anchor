import Foundation

// watchOS is the reason this is not a plain `canImport` check: the
// FoundationModels module *does* exist there, but `SystemLanguageModel` is
// marked `@available(watchOS, unavailable)`. Compiling the model path for the
// watch would fail, so the watch always takes the rule-based route and lets the
// phone or Mac re-tag what it captured once the store syncs.
#if canImport(FoundationModels) && !os(watchOS)
import FoundationModels
#endif

/// Groups and tags goals and distractions using Apple's on-device foundation model,
/// falling back to ``HeuristicTagger`` whenever the model is not usable.
///
/// Everything here stays on device. Anchor never sends a distraction note anywhere:
/// the notes are, by their nature, the most private thing in the app.
public struct TaggingService: Sendable {
    private let heuristic = HeuristicTagger()
    /// Lets tests and previews force the deterministic path.
    private let allowsOnDeviceModel: Bool

    public init(allowsOnDeviceModel: Bool = true) {
        self.allowsOnDeviceModel = allowsOnDeviceModel
    }

    // MARK: - Availability

    public enum Availability: Equatable, Sendable {
        case available
        case deviceNotEligible
        case notEnabled
        case modelNotReady
        case unsupportedOS

        public var isAvailable: Bool { self == .available }

        /// Shown in Settings so the user knows why tags say "rules" instead of "on-device model".
        public var explanation: String {
            switch self {
            case .available: "Apple Intelligence is grouping your goals and distractions on this device."
            case .deviceNotEligible: "This device doesn't support Apple Intelligence. Anchor is using built-in rules instead."
            case .notEnabled: "Turn on Apple Intelligence in System Settings for smarter grouping."
            case .modelNotReady: "Apple Intelligence is still downloading. Anchor is using built-in rules until it's ready."
            // Covers both "OS too old" and watchOS, where Apple ships no
            // on-device model at all.
            case .unsupportedOS: "Apple Intelligence isn't available on this device. Anchor is using built-in rules, and your phone or Mac will refine the tags once this syncs."
            }
        }
    }

    public static var availability: Availability {
        #if canImport(FoundationModels) && !os(watchOS)
        switch SystemLanguageModel.default.availability {
        case .available:
            return .available
        case .unavailable(let reason):
            switch reason {
            case .deviceNotEligible: return .deviceNotEligible
            case .appleIntelligenceNotEnabled: return .notEnabled
            case .modelNotReady: return .modelNotReady
            @unknown default: return .modelNotReady
            }
        @unknown default:
            return .modelNotReady
        }
        #else
        return .unsupportedOS
        #endif
    }

    private var useModel: Bool {
        allowsOnDeviceModel && Self.availability.isAvailable
    }

    /// Warm the model up while the user is typing their goal, so the first tag
    /// after they hit start doesn't pay the load cost.
    public func prewarm() {
        #if canImport(FoundationModels) && !os(watchOS)
        guard useModel else { return }
        let session = LanguageModelSession(instructions: Self.distractionInstructions)
        session.prewarm()
        #endif
    }

    // MARK: - Distractions

    public func classifyDistraction(note: String, duringGoal goal: String) async -> DistractionTagging {
        let fallback = heuristic.classifyDistraction(note: note)
        #if canImport(FoundationModels) && !os(watchOS)
        guard useModel else { return fallback }
        do {
            let session = LanguageModelSession(instructions: Self.distractionInstructions)
            // The rule matcher is handed over as a hint rather than discarded.
            // On explicit cues ("slack", "standup") it is reliably right, and the
            // small on-device model otherwise drifts on the subtler boundaries —
            // it read "Slack from Ravi" as a physical interruption without this.
            // The model can still override it, which is the point of asking.
            let prompt = """
            Goal being worked on: \(goal.isEmpty ? "unspecified" : goal)
            Interruption the person wrote down: \(note)
            A keyword matcher suggests: \(fallback.kind.rawValue)
            Use that suggestion unless the wording clearly points elsewhere.
            """
            let response = try await session.respond(
                to: prompt,
                generating: DistractionDraft.self,
                options: GenerationOptions(temperature: 0.1)
            )
            let draft = response.content
            guard let kind = DistractionKind(rawValue: draft.category) else { return fallback }
            return DistractionTagging(
                kind: kind,
                confidence: min(1, max(0, draft.confidence)),
                keywords: Self.normalise(draft.keywords, fallback: fallback.keywords),
                source: .onDeviceModel
            )
        } catch {
            // Guardrail trips, context overflow, assets pulled mid-flight — all of
            // it means the same thing here: use the rules and move on.
            return fallback
        }
        #else
        return fallback
        #endif
    }

    // MARK: - Goals

    public func classifyGoal(title: String, notes: String) async -> GoalTagging {
        let fallback = heuristic.classifyGoal(title: title, notes: notes)
        #if canImport(FoundationModels) && !os(watchOS)
        guard useModel else { return fallback }
        do {
            let session = LanguageModelSession(instructions: Self.goalInstructions)
            var prompt = notes.isEmpty ? "Goal: \(title)" : "Goal: \(title)\nNotes: \(notes)"
            prompt += "\nA keyword matcher suggests: \(fallback.theme.rawValue)"
            prompt += "\nUse that suggestion unless the wording clearly points elsewhere."
            let response = try await session.respond(
                to: prompt,
                generating: GoalDraft.self,
                options: GenerationOptions(temperature: 0.1)
            )
            let draft = response.content
            guard let theme = GoalTheme(rawValue: draft.theme) else { return fallback }
            return GoalTagging(
                theme: theme,
                keywords: Self.normalise(draft.keywords, fallback: fallback.keywords),
                source: .onDeviceModel
            )
        } catch {
            return fallback
        }
        #else
        return fallback
        #endif
    }

    // MARK: - Summaries

    /// A short, plain-language read on a week of data. Optional garnish: when the
    /// model is unavailable the analytics screen simply omits it rather than
    /// showing a worse machine-written sentence.
    public func summarise(_ brief: String) async -> String? {
        #if canImport(FoundationModels) && !os(watchOS)
        guard useModel else { return nil }
        do {
            let session = LanguageModelSession(instructions: Self.summaryInstructions)
            let response = try await session.respond(
                to: brief,
                options: GenerationOptions(temperature: 0.3)
            )
            let text = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
            return text.isEmpty ? nil : text
        } catch {
            return nil
        }
        #else
        return nil
        #endif
    }

    // MARK: - Helpers

    static func normalise(_ keywords: [String], fallback: [String]) -> [String] {
        var seen = Set<String>()
        let cleaned = keywords
            .map { $0.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.count > 2 && $0.count < 24 }
            .filter { seen.insert($0).inserted }
            .prefix(4)
        return cleaned.isEmpty ? fallback : Array(cleaned)
    }

    private static let distractionInstructions = """
    You sort interruptions that broke someone's focus into a fixed set of categories.

    Pick exactly one category from the allowed list. Guidance:
    - "message" is a chat or text arriving from a person, through any app —
      Slack, WhatsApp, iMessage, Discord, SMS. The app is what matters, not who sent it.
    - "notification" is an impersonal alert with no human on the other end.
    - "person" is ONLY for someone physically present interrupting in the room.
      If it arrived through a screen, it is never "person".
    - "rabbitHole" is searching or reading that drifted off-task.
    - "socialFeed" is scrolling a feed.
    - "wanderingThought" is the mind drifting with no external trigger.
    - "otherWork" is real work, but not the work they sat down to do.
    - Use "other" only when nothing else fits.

    Worked examples:
    - "Slack from Ravi about the invoice" -> message
    - "Ravi asked me about deploy timing on Slack" -> message
    - "Roommate walked in to chat" -> person
    - "Phone buzzed with a delivery alert" -> notification
    - "Opened Hacker News without thinking" -> socialFeed
    - "Ended up reading three Wikipedia pages on typography" -> rabbitHole
    - "Remembered I never replied to the landlord" -> wanderingThought
    - "Jumped over to fix an unrelated bug" -> otherWork

    Also give 2 to 4 short lowercase keywords drawn from the person's own words, so
    repeated interruptions of the same thing can be grouped together.

    Report confidence honestly. Never invent detail that isn't in the note.
    """

    private static let goalInstructions = """
    You sort work goals into a fixed set of themes so someone can see what kind of
    work they actually protect time for. Pick exactly one theme from the allowed
    list, and give 2 to 4 short lowercase keywords taken from the goal's own words.

    Judge by the activity, not the subject matter. Worked examples:
    - "Finish the token refresh" -> building
    - "Ship the auth rewrite" -> building
    - "Draft the launch post" -> writing
    - "Study for the exam" -> learning
    - "Q3 roadmap" -> planning
    - "Reply to the client thread" -> communication
    - "Do my taxes" -> admin
    - "Redesign the settings screen" -> creative

    Anything that builds, fixes, refactors or ships software is "building", even when
    the words sound routine. Use "other" only when nothing else fits.
    """

    private static let summaryInstructions = """
    You write two or three sentences about someone's focus period, addressed to them
    as "you". Start with a capital letter and write in full sentences.

    Do not list the statistics back — they can already see them. Lead with the single
    most useful observation in the data (the pattern, the outlier, the thing that
    costs them most), then support it with at most two figures. Prefer a comparison
    over a bare total.

    Never invent a number you were not given, and quote figures exactly as written.
    No preamble, no encouragement, no advice the data doesn't directly support.
    """
}

#if canImport(FoundationModels) && !os(watchOS)

/// Structured output shapes. Kept `internal` — callers see the domain types.
@Generable
struct DistractionDraft {
    @Guide(
        description: "The single best-fitting category for this interruption.",
        .anyOf(DistractionKind.allCases.map(\.rawValue))
    )
    var category: String

    @Guide(description: "2 to 4 short lowercase keywords from the person's own wording.", .maximumCount(4))
    var keywords: [String]

    @Guide(description: "How confident you are in the category, from 0 to 1.", .range(0...1))
    var confidence: Double
}

@Generable
struct GoalDraft {
    @Guide(
        description: "The single best-fitting theme for this goal.",
        .anyOf(GoalTheme.allCases.map(\.rawValue))
    )
    var theme: String

    @Guide(description: "2 to 4 short lowercase keywords from the goal's own wording.", .maximumCount(4))
    var keywords: [String]
}

#endif
