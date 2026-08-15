import Foundation
import SwiftData

/// A thing you are trying to move forward. Sessions are always run *against* a goal,
/// so every minute of focus and every distraction has somewhere to land.
///
/// CloudKit-compatible by construction: every attribute has a default, every
/// relationship is optional, and there are no unique constraints.
@Model
public final class Goal {
    public var id: UUID = UUID()
    public var title: String = ""
    public var notes: String = ""
    public var createdAt: Date = Date()
    public var archivedAt: Date?

    /// SF Symbol chosen by the user, or suggested on-device.
    public var symbolName: String = "target"
    /// Index into `AnchorPalette.goalTints` — stored as an Int so the schema stays primitive.
    public var tintIndex: Int = 0

    /// Theme assigned on-device by ``GoalTagger``. Groups goals that are really the same work.
    public var themeRaw: String?
    /// Free-form labels, on-device generated, used for grouping in analytics.
    public var keywords: [String] = []

    @Relationship(deleteRule: .nullify, inverse: \FocusSession.goal)
    public var sessions: [FocusSession]?

    public init(
        id: UUID = UUID(),
        title: String,
        notes: String = "",
        createdAt: Date = Date(),
        symbolName: String = "target",
        tintIndex: Int = 0
    ) {
        self.id = id
        self.title = title
        self.notes = notes
        self.createdAt = createdAt
        self.symbolName = symbolName
        self.tintIndex = tintIndex
    }

    public var isArchived: Bool { archivedAt != nil }

    public var theme: GoalTheme? {
        get { themeRaw.flatMap(GoalTheme.init(rawValue:)) }
        set { themeRaw = newValue?.rawValue }
    }
}

/// The on-device model sorts goals into these buckets so analytics can answer
/// "what kind of work do I actually protect?" without the user tagging anything.
public enum GoalTheme: String, CaseIterable, Codable, Sendable {
    case building
    case writing
    case learning
    case planning
    case communication
    case admin
    case creative
    case other

    public var label: String {
        switch self {
        case .building: "Building"
        case .writing: "Writing"
        case .learning: "Learning"
        case .planning: "Planning"
        case .communication: "Communication"
        case .admin: "Admin"
        case .creative: "Creative"
        case .other: "Other"
        }
    }

    public var symbolName: String {
        switch self {
        case .building: "hammer"
        case .writing: "square.and.pencil"
        case .learning: "book"
        case .planning: "map"
        case .communication: "bubble.left.and.bubble.right"
        case .admin: "tray.full"
        case .creative: "paintbrush"
        case .other: "circle.dashed"
        }
    }
}
