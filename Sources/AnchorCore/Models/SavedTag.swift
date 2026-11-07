import Foundation
import SwiftData

/// A user-created label that can be reused across sessions and distractions.
///
/// Entries store the tag's stable UUID as a string instead of a many-to-many
/// relationship. That keeps the CloudKit graph simple and lets a tag be renamed
/// without rewriting every entry that uses it.
@Model
public final class SavedTag {
    public var id: UUID = UUID()
    public var name: String = ""
    public var createdAt: Date = Date()
    public var archivedAt: Date?
    public var tintIndex: Int = 0

    public init(
        id: UUID = UUID(),
        name: String,
        createdAt: Date = Date(),
        tintIndex: Int = 0
    ) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.tintIndex = tintIndex
    }

    public var storageID: String { id.uuidString }

    /// Older account records may use lowercase UUIDs; labels compare stable
    /// storage IDs exactly. Keep non-UUID legacy values unchanged.
    static func normalizedStorageIDs(_ values: [String]) -> [String] {
        values.map { UUID(uuidString: $0)?.uuidString ?? $0 }
    }
    public var isArchived: Bool { archivedAt != nil }
}
