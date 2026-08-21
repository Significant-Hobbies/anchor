import Foundation
import SwiftData

/// A durable area of work above an individual goal or focus session.
///
/// Projects are deliberately lightweight: selecting one is optional, and older
/// sessions remain valid without one. Every stored field has a default and the
/// inverse relationship is optional so the model remains CloudKit-compatible.
@Model
public final class Project {
    public var id: UUID = UUID()
    public var name: String = ""
    public var notes: String = ""
    public var createdAt: Date = Date()
    public var archivedAt: Date?
    public var symbolName: String = "folder"
    public var tintIndex: Int = 0
    /// Default rate copied into new sessions so later rate changes do not
    /// rewrite historical earnings.
    public var hourlyRate: Double = 0
    public var currencyCode: String = "USD"

    @Relationship(deleteRule: .nullify, inverse: \FocusSession.project)
    public var sessions: [FocusSession]?

    public init(
        id: UUID = UUID(),
        name: String,
        notes: String = "",
        createdAt: Date = Date(),
        symbolName: String = "folder",
        tintIndex: Int = 0,
        hourlyRate: Double = 0,
        currencyCode: String = "USD"
    ) {
        self.id = id
        self.name = name
        self.notes = notes
        self.createdAt = createdAt
        self.symbolName = symbolName
        self.tintIndex = tintIndex
        self.hourlyRate = max(0, hourlyRate)
        self.currencyCode = currencyCode.isEmpty ? "USD" : currencyCode.uppercased()
    }

    public var isArchived: Bool { archivedAt != nil }
}
