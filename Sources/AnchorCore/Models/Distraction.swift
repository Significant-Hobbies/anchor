import Foundation
import SwiftData

/// Something that pulled at you mid-session.
///
/// The point of capturing it is twofold: it gets the thought out of your head so
/// you can go back to work, and it accumulates into the only honest record of
/// what actually costs you focus.
@Model
public final class Distraction {
    public var id: UUID = UUID()
    public var capturedAt: Date = Date()

    /// What the user typed, in their own words. The raw material for tagging.
    // Legacy mirrored fields retain their exact schema names for CloudKit.
    // Only migration reads them; new user content uses the private accessors.
    var note: String = ""

    @Transient var privateDraft: LocalDistractionNotes.Content?

    public var privateNote: String {
        get { privateContent.note }
        set { privateDraft = .init(note: newValue, keywords: privateContent.keywords) }
    }

    private var privateContent: LocalDistractionNotes.Content {
        if let privateDraft { return privateDraft }
        if let context = modelContext, let vault = context.localDistractionNotes,
           let record = try? vault.read(id) { return record.current }
        return .init(note: note, keywords: keywords)
    }

    /// Category assigned on-device. Nil until tagging runs (or if it fails).
    public var kindRaw: String?
    /// Confidence 0...1 from the on-device classifier; 1 when set by hand.
    public var kindConfidence: Double = 0
    /// True when the user picked the category themselves — never re-tag those.
    public var kindIsUserSet: Bool = false

    /// On-device keywords used to cluster near-identical distractions together.
    var keywords: [String] = []

    public var privateKeywords: [String] {
        get { privateContent.keywords }
        set { privateDraft = .init(note: privateContent.note, keywords: newValue) }
    }

    /// Stable IDs of reusable tags explicitly selected by the user.
    public var tagIDStrings: [String] = []

    /// How many seconds into the session it landed. Lets analytics answer
    /// "when in a session do I break?" without recomputing from timestamps.
    public var offsetSeconds: Double = 0

    /// Did parking it work? False means this one ended the session.
    public var didReturnToFocus: Bool = true

    /// The user can come back later and tick off parked items.
    public var handledAt: Date?

    public var session: FocusSession?

    public init(
        id: UUID = UUID(),
        note: String,
        capturedAt: Date = Date(),
        offsetSeconds: Double = 0,
        session: FocusSession? = nil,
        didReturnToFocus: Bool = true,
        tagIDStrings: [String] = []
    ) {
        self.id = id
        self.privateDraft = .init(note: note, keywords: [])
        self.capturedAt = capturedAt
        self.offsetSeconds = offsetSeconds
        self.session = session
        self.didReturnToFocus = didReturnToFocus
        self.tagIDStrings = tagIDStrings
    }

    public var kind: DistractionKind? {
        get { kindRaw.flatMap(DistractionKind.init(rawValue:)) }
        set {
            kindRaw = newValue?.rawValue
        }
    }

    /// Resolved category for display — falls back to `.other` so UI never shows a hole.
    public var displayKind: DistractionKind { kind ?? .other }

    public var isHandled: Bool { handledAt != nil }
}

/// The taxonomy the on-device model classifies into.
///
/// Deliberately small. A taxonomy you can hold in your head is one you will
/// actually act on; thirty buckets would just produce a prettier shrug.
public enum DistractionKind: String, CaseIterable, Codable, Sendable {
    // External — the world came to you.
    case message
    case notification
    case person
    case meeting
    case email

    // Internal — you went to it.
    case wanderingThought
    case rabbitHole
    case socialFeed
    case entertainment

    // Neither, really.
    case otherWork
    case chore
    case bodily
    case environment
    case other

    public var label: String {
        switch self {
        case .message: "Message"
        case .notification: "Notification"
        case .person: "Someone in person"
        case .meeting: "Meeting"
        case .email: "Email"
        case .wanderingThought: "Wandering thought"
        case .rabbitHole: "Rabbit hole"
        case .socialFeed: "Social feed"
        case .entertainment: "Entertainment"
        case .otherWork: "Different work"
        case .chore: "Chore"
        case .bodily: "Body"
        case .environment: "Environment"
        case .other: "Other"
        }
    }

    public var symbolName: String {
        switch self {
        case .message: "message"
        case .notification: "bell.badge"
        case .person: "person.wave.2"
        case .meeting: "person.2"
        case .email: "envelope"
        case .wanderingThought: "cloud"
        case .rabbitHole: "arrow.down.right.circle"
        case .socialFeed: "square.grid.2x2"
        case .entertainment: "play.rectangle"
        case .otherWork: "arrow.triangle.branch"
        case .chore: "basket"
        case .bodily: "figure.walk"
        case .environment: "speaker.wave.3"
        case .other: "questionmark.circle"
        }
    }

    /// Where the pull came from. The single most actionable split in the data:
    /// external distractions are a settings problem, internal ones are a you problem.
    public var origin: DistractionOrigin {
        switch self {
        case .message, .notification, .person, .meeting, .email, .environment:
            .external
        case .wanderingThought, .rabbitHole, .socialFeed, .entertainment:
            .internal
        case .otherWork, .chore, .bodily, .other:
            .mixed
        }
    }
}

public enum DistractionOrigin: String, Codable, Sendable, CaseIterable {
    case external
    case `internal`
    case mixed

    public var label: String {
        switch self {
        case .external: "Came to you"
        case .internal: "You went to it"
        case .mixed: "Mixed"
        }
    }
}
